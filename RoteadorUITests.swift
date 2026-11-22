import XCTest
import UIKit

final class RoteadorUITests: XCTestCase {
    private let firstCode = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    private let nextCode = "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE="

    private func dismissAlert(_ app: XCUIApplication, expected: String) {
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 25))
        XCTAssertTrue(app.alerts.staticTexts[expected].exists, app.alerts.firstMatch.debugDescription)
        app.alerts.buttons["OK"].tap()
    }

    private func paste(_ text: String, into app: XCUIApplication) {
        UIPasteboard.general.string = text
        let paste = app.buttons["pastePairing"]
        XCTAssertTrue(paste.waitForExistence(timeout: 10))
        paste.tap()
    }

    func testPairingButtonsShowFeedbackAndSave() {
        let app = XCUIApplication()
        app.launch()
        let save = app.buttons["savePairing"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        dismissAlert(app, expected: "Use o código exibido no A15.")

        let host = app.textFields["deviceAddress"]
        host.tap()
        host.typeText("127.0.0.1")
        paste("Use o IP do A15 e o código abaixo no iPhone.\n\n" + firstCode, into: app)
        save.tap()
        dismissAlert(app, expected: "Código salvo. Teste a conexão com o A15.")
        XCTAssertEqual(app.staticTexts["pairingStatus"].label, "Código salvo neste iPhone.")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.textFields["deviceAddress"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["deviceAddress"].value as? String, "127.0.0.1")
        XCTAssertEqual(app.staticTexts["pairingStatus"].label, "Código salvo neste iPhone.")
        app.buttons["savePairing"].tap()
        dismissAlert(app, expected: "Código salvo. Teste a conexão com o A15.")

        // A valid pasted replacement must also be persisted when testing the connection.
        paste(nextCode, into: app)
        app.buttons["testConnection"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 25))
        XCTAssertFalse(app.alerts.staticTexts["Nenhum valor salvo para este campo."].exists)
        XCTAssertFalse(app.alerts.staticTexts["Use o código exibido no A15."].exists)
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["testConnection"].isEnabled)
        XCTAssertEqual(app.staticTexts["pairingStatus"].label, "Código salvo neste iPhone.")

        XCUIDevice.shared.press(.home)
        app.activate()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.textFields["deviceAddress"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["deviceAddress"].value as? String, "127.0.0.1")
        XCTAssertEqual(app.staticTexts["pairingStatus"].label, "Código salvo neste iPhone.")
        app.buttons["savePairing"].tap()
        dismissAlert(app, expected: "Código salvo. Teste a conexão com o A15.")

        // An incomplete code must never replace the durable saved value.
        paste("123456", into: app)
        app.buttons["savePairing"].tap()
        dismissAlert(app, expected: "Use o código exibido no A15.")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["savePairing"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["pairingStatus"].label, "Código salvo neste iPhone.")
        app.buttons["savePairing"].tap()
        dismissAlert(app, expected: "Código salvo. Teste a conexão com o A15.")
        XCTAssertTrue(app.staticTexts["appVersion"].label.contains("1.3"))
    }
}
