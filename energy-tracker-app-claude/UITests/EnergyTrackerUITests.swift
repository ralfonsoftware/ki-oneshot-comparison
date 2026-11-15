import XCTest

/// UI tests (§11, Testability): log reading, regression prompt, correction, tariff compare, import, export.
/// The app runs with an in-memory store (`-ETUITesting`); data is seeded through the import path.
final class EnergyTrackerUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Helpers

    private func iso(_ daysAgo: Double) -> String {
        let date = Date().addingTimeInterval(-daysAgo * 86_400)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date).replacingOccurrences(of: "Z", with: "+00:00")
    }

    /// A v2 export file with a 3000 kWh baseline, readings 30 and 0 days ago, and an optional tariff.
    private func seedJSON(withTariff: Bool = false) -> String {
        let meter = "b6f1f6b0-6b8b-4d3a-9b1a-000000000003"
        let tariffs = withTariff ? """
        [{"id":"b6f1f6b0-6b8b-4d3a-9b1a-000000000006","monthlyBaseFee":10.00,"pricePerKwh":0.3000,"currency":"EUR",
          "contractStartDate":"2025-01-01T00:00:00+00:00","contractPeriodMonths":24,"createdAtUtc":"2025-01-01T08:30:00+00:00"}]
        """ : "[]"
        let json = """
        {"formatVersion":"v2","exportedAtUtc":"\(iso(0))",
         "household":{"id":"b6f1f6b0-6b8b-4d3a-9b1a-000000000001","createdAtUtc":"2025-01-05T08:00:00+00:00","locale":"en-US","currency":"EUR",
           "yearlyBaselineKwh":3000,"trendingThresholdKwh":100,"lowConfidenceGapDays":45,"tariffCheckCadenceMonths":3,
           "aiPlausibilityEnabled":false,"aiPlausibilityBackendConfigured":false,"aiPlausibilityBackendLabel":null},
         "householdMembers":[],
         "mainMeter":{"id":"\(meter)","createdAtUtc":"2025-01-05T09:00:00+00:00","digitCapacityKwh":null},
         "meterReadings":[
           {"id":"b6f1f6b0-6b8b-4d3a-9b1a-000000000010","mainMeterId":"\(meter)","kwhValue":10000,"readingTimestamp":"\(iso(30))","idempotencyKey":"b6f1f6b0-6b8b-4d3a-9b1a-000000000010","createdAtUtc":"\(iso(30))"},
           {"id":"b6f1f6b0-6b8b-4d3a-9b1a-000000000011","mainMeterId":"\(meter)","kwhValue":10240,"readingTimestamp":"\(iso(0.01))","idempotencyKey":"b6f1f6b0-6b8b-4d3a-9b1a-000000000011","createdAtUtc":"\(iso(0.01))"}],
         "meterRegressionPrompts":[],"tariffs":\(tariffs),"events":[],"rooms":[],"powerPoints":[],"devices":[],
         "smartPlugReadings":[],"statusSnapshots":[],"auditCorrections":[]}
        """
        return Data(json.utf8).base64EncodedString()
    }

    private func launch(seed: String? = nil, importFile: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ETUITesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if let seed { app.launchEnvironment["ETUITestSeedJSON"] = seed }
        if let importFile { app.launchEnvironment["ETUITestImportJSON"] = importFile }
        app.launch()
        return app
    }

    private func logReading(_ app: XCUIApplication, _ value: String) {
        app.buttons["logReadingButton"].tap()
        let field = app.textFields["kwhField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(value)
        app.buttons["saveReading"].tap()
    }

    private func openTab(_ app: XCUIApplication, _ name: String) {
        let tab = app.tabBars.buttons[name]
        if tab.waitForExistence(timeout: 2) { tab.tap() } else { app.buttons[name].firstMatch.tap() }
    }

    // MARK: Tests

    func testOnboardingAndLogReading() {
        let app = launch()
        XCTAssertTrue(app.buttons["startFresh"].waitForExistence(timeout: 5))
        app.buttons["startFresh"].tap()
        let baseline = app.textFields["onboardingBaseline"]
        XCTAssertTrue(baseline.waitForExistence(timeout: 5))
        baseline.tap()
        baseline.typeText("3000")
        app.buttons["onboardingNext"].tap()
        app.buttons["onboardingDone"].tap()

        XCTAssertTrue(app.staticTexts["Log your first reading to get started"].waitForExistence(timeout: 5))
        logReading(app, "12345.6")
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 5))
    }

    func testStatusAfterSeedAndLogReading() {
        let app = launch(seed: seedJSON())
        XCTAssertTrue(app.otherElements["statusCard"].waitForExistence(timeout: 10) || app.buttons["statusCard"].waitForExistence(timeout: 2))
        logReading(app, "10250")
        let saved = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Saved ·'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
    }

    func testRegressionPrompt() {
        let app = launch(seed: seedJSON())
        XCTAssertTrue(app.buttons["logReadingButton"].waitForExistence(timeout: 10))
        logReading(app, "120")
        // The prompt replaces the Log Reading sheet.
        let reset = app.buttons["chooseReset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'lower than the one before'")).firstMatch.exists)
        app.buttons["chooseRollover"].tap()
        let capacity = app.textFields["capacityField"]
        XCTAssertTrue(capacity.waitForExistence(timeout: 5))
        capacity.tap()
        capacity.typeText("100000")
        app.buttons["saveRollover"].tap()
        XCTAssertFalse(app.otherElements["regressionCard"].waitForExistence(timeout: 2))
    }

    func testRegressionPromptLaterKeepsItOpen() {
        let app = launch(seed: seedJSON())
        XCTAssertTrue(app.buttons["logReadingButton"].waitForExistence(timeout: 10))
        logReading(app, "120")
        XCTAssertTrue(app.buttons["chooseReset"].waitForExistence(timeout: 5))
        app.buttons["Later"].tap()
        XCTAssertTrue(app.staticTexts["1 reading needs a decision"].waitForExistence(timeout: 5))
    }

    func testCorrection() {
        let app = launch(seed: seedJSON())
        XCTAssertTrue(app.buttons["logReadingButton"].waitForExistence(timeout: 10))
        openTab(app, "History")
        app.buttons["Readings"].tap()
        let firstRow = app.cells.firstMatch.exists ? app.cells.firstMatch : app.buttons.matching(NSPredicate(format: "label CONTAINS 'kWh'")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.tap()
        app.buttons["correctButton"].tap()
        let field = app.textFields["correctionField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.clearAndType("10230")
        app.buttons["saveCorrection"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Original value'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testTariffCompare() {
        let app = launch(seed: seedJSON(withTariff: true))
        XCTAssertTrue(app.buttons["logReadingButton"].waitForExistence(timeout: 10))
        openTab(app, "Tariffs")
        let price = app.textFields["candidatePrice"]
        XCTAssertTrue(price.waitForExistence(timeout: 5))
        price.tap()
        price.typeText("0.25")
        let fee = app.textFields["candidateFee"]
        fee.tap()
        fee.typeText("10")
        XCTAssertTrue(app.staticTexts["With bonus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Without bonus effect"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == 'Worth switching'")).firstMatch.exists)
    }

    func testImportIntoEmptyDataSet() {
        let app = launch(importFile: seedJSON(withTariff: true))
        XCTAssertTrue(app.buttons["onboardingImport"].waitForExistence(timeout: 5))
        app.buttons["onboardingImport"].tap()
        app.buttons["chooseFile"].tap()
        let confirm = app.buttons["confirmImport"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Readings"].exists)
        confirm.tap()
        XCTAssertTrue(app.buttons["logReadingButton"].waitForExistence(timeout: 15))
    }

    func testImportRejectsInvalidFile() {
        let bad = Data(#"{"formatVersion":"v1"}"#.utf8).base64EncodedString()
        let app = launch(importFile: bad)
        app.buttons["onboardingImport"].tap()
        app.buttons["chooseFile"].tap()
        XCTAssertTrue(app.staticTexts["'formatVersion' must be \"v2\"."].waitForExistence(timeout: 5))
    }

    func testExportOpensShareSheet() {
        let app = launch(seed: seedJSON())
        XCTAssertTrue(app.buttons["logReadingButton"].waitForExistence(timeout: 10))
        app.buttons["settingsButton"].tap()
        let export = app.buttons["exportButton"]
        for _ in 0..<6 where !export.isHittable { app.swipeUp() }
        export.tap()
        let shareSheet = app.otherElements["ActivityListView"]
        let found = shareSheet.waitForExistence(timeout: 10)
            || app.buttons["Save to Files"].waitForExistence(timeout: 2)
            || app.collectionViews.cells.firstMatch.waitForExistence(timeout: 2)
        XCTAssertTrue(found)
    }
}

extension XCUIElement {
    func clearAndType(_ text: String) {
        tap()
        if let current = value as? String, !current.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        typeText(text)
    }
}
