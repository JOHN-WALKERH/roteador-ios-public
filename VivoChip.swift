import SwiftUI
import UIKit
import CryptoKit
import Network
import Security
import LocalAuthentication

@main
struct VivoChipApp: App {
    var body: some Scene { WindowGroup { ControlView() } }
}

private enum Failure: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let value) = self { return value }
        return nil
    }
}

private enum Vault {
    static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "vivochip.remote.local",
         kSecAttrAccount as String: account]
    }

    static func save(_ value: String, account: String, protected: Bool = true) throws {
        var entry = base(account)
        let data = Data(value.utf8)
        entry[kSecValueData as String] = data
        if protected {
            guard let control = SecAccessControlCreateWithFlags(nil,
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, nil) else {
                throw Failure.message("Ative o código do iPhone para guardar as senhas.")
            }
            entry[kSecAttrAccessControl as String] = control
        } else {
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        var status = SecItemAdd(entry as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(base(account) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary)
        }
        guard status == errSecSuccess else {
            throw Failure.message("Não foi possível salvar no Chaves do iPhone (erro \(status)).")
        }
    }

    static func read(_ account: String) throws -> String {
        let context = LAContext()
        context.localizedReason = "Acesse a credencial do roteador"
        var query = base(account)
        query[kSecUseAuthenticationContext as String] = context
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            throw Failure.message("Nenhum valor salvo para este campo.")
        }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw Failure.message("O acesso ao Chaves não foi autorizado.")
        }
        return value
    }
}

private final class RemoteExchange {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "vivochip.exchange")
    private let key: SymmetricKey
    private let request: Data
    private var buffer = Data()
    private var completion: ((Result<String, Error>) -> Void)?

    init(address: String, pairing: String, action: String, current: String, replacement: String) throws {
        guard let data = Data(base64Encoded: pairing), data.count == 32 else {
            throw Failure.message("Use o código de pareamento mostrado no A15.")
        }
        key = SymmetricKey(data: data)
        request = try JSONSerialization.data(withJSONObject:
            ["action": action, "current": current, "replacement": replacement])
        connection = NWConnection(host: NWEndpoint.Host(address), port: 45422, using: .tcp)
    }

    func run() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.completion = { continuation.resume(with: $0) }
                self.connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready: self.exchange()
                    case .failed(let error): self.finish(.failure(error))
                    default: break
                    }
                }
                self.connection.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + 16) { [weak self] in
                    self?.finish(.failure(Failure.message("O A15 não confirmou. Confira a conexão.")))
                }
            }
        }
    }

    private func exchange() {
        line { challenge in
            do {
                guard challenge.count == 32 else { throw Failure.message("Resposta inesperada do A15.") }
                let sealed = try AES.GCM.seal(self.request, using: self.key,
                    authenticating: challenge + Data([1]))
                guard let combined = sealed.combined else {
                    throw Failure.message("Falha ao proteger o comando.")
                }
                self.connection.send(content: Data((combined.base64EncodedString() + "\n").utf8),
                    completion: .contentProcessed { error in
                        if let error { self.finish(.failure(error)); return }
                        self.line { data in
                            do {
                                let box = try AES.GCM.SealedBox(combined: data)
                                let plain = try AES.GCM.open(box, using: self.key,
                                    authenticating: challenge + Data([2]))
                                guard let parsed = try JSONSerialization.jsonObject(with: plain) as? [String: String],
                                      let result = parsed["result"] else {
                                    throw Failure.message("Resposta inesperada do A15.")
                                }
                                self.finish(.success(result))
                            } catch { self.finish(.failure(error)) }
                        }
                    })
            } catch { self.finish(.failure(error)) }
        }
    }

    private func line(_ handler: @escaping (Data) -> Void) {
        if let end = buffer.firstIndex(of: 10) {
            let frame = Data(buffer[..<end])
            buffer.removeSubrange(...end)
            guard let data = Data(base64Encoded: frame) else {
                finish(.failure(Failure.message("Resposta inválida do A15.")))
                return
            }
            handler(data)
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, complete, error in
            if let error { self.finish(.failure(error)); return }
            if let data { self.buffer.append(data) }
            if self.buffer.count > 2048 || (complete && !self.buffer.contains(10)) {
                self.finish(.failure(Failure.message("A conexão foi encerrada antes da confirmação.")))
                return
            }
            self.line(handler)
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard let completion else { return }
        self.completion = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        completion(result)
    }
}

private enum Credential: String, Identifiable {
    case pin, master
    var id: String { rawValue }
    var title: String { self == .pin ? "Alterar senha do PIN" : "Alterar senha mestre" }
    var name: String { self == .pin ? "senha do PIN" : "senha mestre" }
    var maximum: Int { self == .pin ? 8 : 12 }
}

private struct ControlView: View {
    @Environment(\.scenePhase) private var phase
    @AppStorage("deviceAddress") private var address = ""
    @State private var pairing = ""
    @State private var master = ""
    @State private var pin = ""
    @State private var current = ""
    @State private var replacement = ""
    @State private var confirmation = ""
    @State private var credential: Credential?
    @State private var message = ""
    @State private var busy = false
    @State private var confirmStart = false
    @State private var confirmStop = false
    @State private var showFeedback = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Estado") {
                    if busy {
                        ProgressView("Aguardando resposta do A15...")
                    }
                    Text(message.isEmpty ? "Preencha o IP e cole o c\u{00F3}digo de pareamento do A15." : message)
                        .accessibilityIdentifier("actionStatus")
                }
                Section("Galaxy A15") {
                    TextField("IP do A15", text: $address)
                        .accessibilityIdentifier("deviceAddress")
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                    SecureField("Código de pareamento", text: $pairing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("pairingCode")
                    Button("Salvar pareamento") { savePairing() }
                        .accessibilityIdentifier("savePairing")
                        .disabled(busy)
                    Button("Testar conexão") { send("status") }.disabled(busy)
                        .accessibilityIdentifier("testConnection")
                    Button("Ligar roteador") { confirmStart = true }.disabled(busy)
                    Button("Desligar roteador", role: .destructive) { confirmStop = true }
                        .disabled(busy)
                }

                Section("Credenciais no iPhone") {
                    secretRow("Senha mestre", account: "master", value: $master)
                    secretRow("PIN de acesso", account: "pin", value: $pin)
                    NavigationLink("Guardar credenciais existentes") { ImportCredentialsView() }
                }

                Section("Alterar no A15") {
                    Button(Credential.pin.title) { edit(.pin) }.disabled(busy)
                    Button(Credential.master.title) { edit(.master) }.disabled(busy)
                }
                if !message.isEmpty { Section { Text(message) } }
            }
            .buttonStyle(.borderless)
            .navigationTitle("Roteador")
            .alert("Roteador", isPresented: $showFeedback) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message)
            }
            .onChange(of: message) { value in
                if !busy && !value.isEmpty { showFeedback = true }
            }
            .onChange(of: busy) { value in
                if !value && !message.isEmpty { showFeedback = true }
            }
            .confirmationDialog("Desligar o roteador do A15?", isPresented: $confirmStop) {
                Button("Desligar roteador", role: .destructive) { send("stop") }
            }
        }
        .confirmationDialog("Ligar o roteador do A15?", isPresented: $confirmStart) {
            Button("Ligar roteador") { send("start") }
        }
        .sheet(item: $credential) { selected in
            NavigationStack {
                Form {
                    Section("Autorizar alteração") {
                        SecureField("Senha mestre atual", text: $current).keyboardType(.numberPad)
                        Button("Usar senha mestre salva") {
                            do { current = try Vault.read("master") }
                            catch { message = error.localizedDescription }
                        }
                    }
                    Section("Nova " + selected.name) {
                        SecureField("Digite de 4 a \(selected.maximum) dígitos", text: $replacement)
                            .keyboardType(.numberPad)
                        SecureField("Confirme a nova " + selected.name, text: $confirmation)
                            .keyboardType(.numberPad)
                        Button(selected.title) { send(selected.rawValue) }.disabled(busy)
                    }
                    if !message.isEmpty { Section { Text(message) } }
                }
                .buttonStyle(.borderless)
                .navigationTitle(selected.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fechar") { credential = nil }.disabled(busy)
                    }
                }
            }
            .interactiveDismissDisabled(busy)
        }
        .onAppear { restorePairing() }
        .onChange(of: phase) { value in
            if value == .background {
                master = ""; pin = ""; current = ""; replacement = ""; confirmation = ""
            }
        }
    }

    private func restorePairing() {
        // A saved pairing stays in Keychain; never copy it into UserDefaults.
        guard pairing.isEmpty else { return }
        if let saved = try? Vault.read("pairing") {
            pairing = saved
        }
    }

    private func edit(_ selection: Credential) {
        current = ""; replacement = ""; confirmation = ""; message = ""
        credential = selection
    }

    private func secretRow(_ title: String, account: String, value: Binding<String>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(value.wrappedValue.isEmpty ? "••••••" : value.wrappedValue)
                    .monospaced()
            }
            Spacer()
            Button {
                if !value.wrappedValue.isEmpty {
                    value.wrappedValue = ""
                    return
                }
                do {
                    let revealed = try Vault.read(account)
                    value.wrappedValue = revealed
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 15_000_000_000)
                        if value.wrappedValue == revealed { value.wrappedValue = "" }
                    }
                } catch { message = error.localizedDescription }
            } label: {
                Image(systemName: value.wrappedValue.isEmpty ? "eye" : "eye.slash")
                    .accessibilityLabel(value.wrappedValue.isEmpty ? "Mostrar \(title)" : "Ocultar \(title)")
            }
            .buttonStyle(.borderless)
        }
    }

    private func savePairing() {
        defer { showFeedback = !message.isEmpty }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        message = ""
        let code = pairing.components(separatedBy: .whitespacesAndNewlines).joined()
        guard Data(base64Encoded: code)?.count == 32 else {
            message = "Use o código exibido no A15."
            return
        }
        do {
            try Vault.save(code, account: "pairing", protected: false)
            address = address.trimmingCharacters(in: .whitespacesAndNewlines)
            pairing = code
            message = "Código salvo. Teste a conexão com o A15."
        } catch { message = error.localizedDescription }
    }

    private func send(_ command: String) {
        defer { if !busy && !message.isEmpty { showFeedback = true } }
        guard !busy else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        message = ""
        let host = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { message = "Preencha o IP do A15."; return }
        let changing = command == "pin" || command == "master"
        let next = changing ? replacement : ""
        if changing && (next != confirmation || !valid(next, maximum: command == "pin" ? 8 : 12)) {
            message = "Confirme o valor. Use 4 a \(command == "pin" ? 8 : 12) dígitos."
            return
        }
        do {
            let code = try Vault.read("pairing")
            let password = command == "status" ? "" : (current.isEmpty ? try Vault.read("master") : current)
            let exchange = try RemoteExchange(address: host, pairing: code, action: command,
                                              current: password, replacement: next)
            busy = true
            message = "Aguardando o A15…"
            Task { @MainActor in
                defer { busy = false }
                do {
                    let result = try await exchange.run()
                    switch result {
                    case "connected": message = "A15 conectado."
                    case "hotspot_on": message = "Roteador ligado. O A15 confirmou."
                    case "hotspot_off": message = "Roteador desligado. O A15 confirmou."
                    case "hotspot_managed_block": message = "O bloqueio gerenciado do roteador está ativo no A15."
                    case "hotspot_start_unavailable", "hotspot_start_denied":
                        message = "O Android do A15 recusou a ativação remota."
                    case "hotspot_start_unconfirmed": message = "O A15 não confirmou a ativação do roteador."
                    case "invalid_command" where command == "start":
                        message = "Atualize o Vivo Chip do A15 para usar o comando Ligar roteador."
                    case "hotspot_unconfirmed": message = "O A15 não conseguiu confirmar que o roteador apagou."
                    case "shizuku_unavailable": message = "O Shizuku está indisponível no A15."
                    case "invalid_master": message = "A senha mestre atual está incorreta."
                    case "retry_later": message = "Aguarde alguns segundos antes de tentar novamente."
                    case "credentials_must_differ": message = "O PIN e a senha mestre precisam ser diferentes."
                    case "invalid_format": message = "O A15 recusou o formato do novo valor."
                    case "save_failed": message = "O A15 não confirmou a gravação."
                    case "saved" where changing:
                        current = ""; replacement = ""; confirmation = ""
                        if command == "master" { master = "" } else { pin = "" }
                        do {
                            try Vault.save(next, account: command)
                            message = command == "pin"
                                ? "Senha do PIN alterada no A15 e salva no Chaves do iPhone."
                                : "Senha mestre alterada no A15 e salva no Chaves do iPhone."
                        } catch {
                            replacement = next
                            message = "Alterado no A15. O iPhone não conseguiu salvar. Guarde o novo valor em Credenciais."
                        }
                    default: message = "O A15 não confirmou o comando."
                    }
                } catch { message = error.localizedDescription }
            }
        } catch { message = error.localizedDescription }
    }
}

private struct ImportCredentialsView: View {
    @State private var master = ""
    @State private var pin = ""
    @State private var message = ""
    @State private var showFeedback = false

    var body: some View {
        Form {
            SecureField("Senha mestre atual", text: $master).keyboardType(.numberPad)
            SecureField("PIN de acesso atual", text: $pin).keyboardType(.numberPad)
            Button("Salvar no Chaves") {
                defer { showFeedback = !message.isEmpty }
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                message = ""
                guard (!master.isEmpty || !pin.isEmpty),
                      master.isEmpty || valid(master, maximum: 12),
                      pin.isEmpty || valid(pin, maximum: 8) else {
                    message = "Preencha o PIN com 4 a 8 dígitos e a senha mestre com 4 a 12."
                    return
                }
                do {
                    if !master.isEmpty { try Vault.save(master, account: "master"); master = "" }
                    if !pin.isEmpty { try Vault.save(pin, account: "pin"); pin = "" }
                    message = "Valores guardados no Chaves deste iPhone."
                } catch { message = error.localizedDescription }
            }
            if !message.isEmpty { Text(message) }
        }
        .buttonStyle(.borderless)
        .navigationTitle("Guardar credenciais")
        .alert("Credenciais", isPresented: $showFeedback) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message)
        }
        .onChange(of: message) { value in
            if !value.isEmpty { showFeedback = true }
        }
    }
}

private func valid(_ value: String, maximum: Int) -> Bool {
    (4...maximum).contains(value.utf8.count) && value.utf8.allSatisfy { (48...57).contains($0) }
}
