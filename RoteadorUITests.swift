import XCTest

final class RoteadorUITests: XCTestCase {
    func testPairingButtonsShowFeedbackAndSave() {
        let app = XCUIApplication()
        app.launch()
        let save = app.buttons["savePairing"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["Use o c\u{00F3}digo exibido no A15."].exists)
        app.alerts.buttons["OK"].tap()
        // A second invalid tap must still get feedback, even with the same message.
        save.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        let field = app.secureTextFields["pairingCode"]
        field.tap()
        field.typeText("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
        save.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["C\u{00F3}digo salvo. Teste a conex\u{00E3}o com o A15."].exists)
        app.alerts.buttons["OK"].tap()
        let host = app.textFields["deviceAddress"]
        host.tap()
        host.typeText("127.0.0.1")
        app.buttons["testConnection"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 25))
        XCTAssertFalse(app.alerts.staticTexts["Nenhum valor salvo para este campo."].exists)
        // A closed local port must produce a visible failure and release busy state.
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["testConnection"].isEnabled)
        // Both values survive a full app restart.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.textFields["deviceAddress"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["deviceAddress"].value as? String, "127.0.0.1")
        app.buttons["savePairing"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["C\u{00F3}digo salvo. Teste a conex\u{00E3}o com o A15."].exists)
        app.alerts.buttons["OK"].tap()

    }
}
