# Roteador 1.3

Controlador iPhone do Vivo Chip no Galaxy A15. Versão 1.3, build 4.

O IP continua em AppStorage. O pareamento é gravado atomicamente em um arquivo privado em Application Support, com proteção completa de dados do iOS e excluído dos backups. Uma leitura de confirmação precisa coincidir com o código antes de mostrar sucesso. O pareamento não depende mais de permissões de Keychain da assinatura usada para instalar o IPA. Senha mestre e PIN continuam no Keychain com autenticação local.

O aplicativo migra um pareamento do Keychain antigo quando consegue lê-lo. Se a instalação perdeu o acesso a esse item, é necessário colar o código do A15 novamente. A versão aparece na tela para distinguir o aplicativo instalado.

A colagem aceita o texto completo exibido no Android, desde que contenha um único código de pareamento válido. Testar a conexão também salva um código válido colado no campo. Códigos incompletos não substituem o pareamento salvo.

A CI compila para iPhone arm64 e executa o teste de interface com o simulador sem assinatura nem entitlement de Keychain. O teste cobre colagem real pelo PasteButton, código e IP após encerrar/reabrir, atualização do código ao testar a conexão e preservação do pareamento anterior após uma entrada inválida.

O IPA é unsigned e deve ser assinado para instalar no aparelho. Atualize a instalação mantendo o mesmo identificador. Desinstalar o aplicativo remove seu arquivo privado de pareamento.
