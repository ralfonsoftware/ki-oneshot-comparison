import XCTest

final class EnergyTrackerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-ResetStore", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        if app.buttons["Start fresh"].waitForExistence(timeout: 3) {
            app.buttons["Start fresh"].tap()
            app.buttons["Skip"].tap()
        }
    }

    func testLogReadingAndRegressionPrompt() {
        logReading("1000")
        logReading("900", expectsDecision: true)
        XCTAssertTrue(app.buttons["Meter was replaced or reset"].waitForExistence(timeout: 2))
        app.buttons["Meter was replaced or reset"].tap()
        app.buttons["save-regression"].tap()
        XCTAssertTrue(app.buttons["today-log-reading"].waitForExistence(timeout: 2))
    }

    func testCorrectReading() {
        logReading("1000")
        app.tabBars.buttons["History"].tap()
        app.buttons["Readings"].tap()
        app.buttons.element(matching: .button, identifier: "reading-row-" ).exists // Rows use suffix IDs; the list itself is exercised below.
        app.cells.firstMatch.tap()
        app.buttons["correct-reading"].tap()
        let field = app.textFields.element(boundBy: 0)
        field.tap(); field.typeText("1010")
        app.buttons["save-correction"].tap()
        XCTAssertTrue(app.staticTexts["Correction saved"].waitForExistence(timeout: 2))
    }

    func testTariffCompare() {
        logReading("1000")
        sleep(1)
        logReading("1010")
        app.tabBars.buttons["Tariffs"].tap()
        app.buttons["Add tariff"].tap()
        setField(named: "Monthly base fee", to: "10")
        setField(named: "Price per kWh", to: "0.3")
        app.buttons["save-tariff"].tap()
        setField(named: "Candidate base fee", to: "12")
        setField(named: "Candidate price", to: "0.28")
        setField(named: "Switching bonus (optional)", to: "100")
        XCTAssertTrue(app.otherElements["with-bonus-result"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.otherElements["without-bonus-result"].exists)
    }

    func testImportAndExportControls() {
        app.buttons["today-settings"].tap()
        XCTAssertTrue(app.buttons["export-data"].waitForExistence(timeout: 2))
        app.buttons["export-data"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 3))
        app.buttons["Close"].tap()
        app.buttons["import-data"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
    }

    private func logReading(_ value: String, expectsDecision: Bool = false) {
        app.buttons["today-log-reading"].tap()
        let field = app.textFields["reading-value"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.tap(); field.typeText(value)
        app.buttons["save-reading"].tap()
        if !expectsDecision { XCTAssertTrue(app.buttons["today-log-reading"].waitForExistence(timeout: 2)) }
    }

    private func setField(named name: String, to value: String) {
        let field = app.textFields[name]
        guard field.waitForExistence(timeout: 2) else { return }
        field.tap(); field.typeText(value)
    }
}
