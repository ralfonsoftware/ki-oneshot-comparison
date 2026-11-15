import AppIntents
import Foundation

private typealias DialogIntentResult = IntentResultContainer<Never, Never, Never, IntentDialog>

struct LogMeterReadingIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Meter Reading"
    static let description = IntentDescription("Save a cumulative Main Meter reading without opening the app.")
    static let openAppWhenRun = false

    @Parameter(title: "kWh", requestValueDialog: "What is the cumulative meter value in kWh?")
    var kwh: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$kwh) kWh")
    }

    init() {}
    init(kwh: String) { self.kwh = kwh }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await MainActor.run {
            guard let value = InputValidation.reading(kwh) else { throw RepositoryError.invalidReading }
            let repository = DataRepository(context: PersistenceController.shared.container.mainContext)
            switch try repository.saveReading(kwh: value) {
            case .alreadySaved:
                return DialogIntentResult.result(dialog: IntentDialog(stringLiteral: String(localized: "Already saved")))
            case .saved:
                if try repository.openPrompt() != nil {
                    return DialogIntentResult.result(dialog: IntentDialog(stringLiteral: String(localized: "Saved. This reading is lower than the previous one — open Energy Tracker to classify it.")))
                }
                let status = try EnergyEngine.status(repository: repository)
                let message = String(format: String(localized: "Saved %@ kWh · %@"), EnergyFormat.kwh(value), status.status?.label ?? String(localized: "Not enough data yet"))
                return DialogIntentResult.result(dialog: IntentDialog(stringLiteral: message))
            }
        }
    }
}

struct GetEnergyStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Energy Status"
    static let description = IntentDescription("Answer with your current energy pace in one sentence.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            let repository = DataRepository(context: PersistenceController.shared.container.mainContext)
            guard let status = try? EnergyEngine.status(repository: repository), let value = status.status else {
                return DialogIntentResult.result(dialog: IntentDialog(stringLiteral: String(localized: "Log your first reading to get started")))
            }
            return DialogIntentResult.result(dialog: IntentDialog(stringLiteral: "\(value.label) — \(status.shortSentence)"))
        }
    }
}

struct LogEventIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Event"
    static let description = IntentDescription("Save an energy-related event without opening the app.")
    static let openAppWhenRun = false

    @Parameter(title: "Text", requestValueDialog: "What happened?")
    var text: String

    static var parameterSummary: some ParameterSummary { Summary("Log event \(\.$text)") }
    init() {}
    init(text: String) { self.text = text }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await MainActor.run {
            let repository = DataRepository(context: PersistenceController.shared.container.mainContext)
            let event = try repository.addEvent(description: text)
            return DialogIntentResult.result(dialog: IntentDialog(stringLiteral: String(format: String(localized: "Saved event: %@"), event.eventDescription)))
        }
    }
}

struct EnergyTrackerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogMeterReadingIntent(), phrases: [
            "Log a meter reading in \(.applicationName)",
            "Erfasse einen Zählerstand in \(.applicationName)"
        ], shortTitle: "Log Meter Reading", systemImageName: "bolt")
        AppShortcut(intent: GetEnergyStatusIntent(), phrases: [
            "Get my energy status in \(.applicationName)",
            "Wie ist mein Energiestatus in \(.applicationName)"
        ], shortTitle: "Get Energy Status", systemImageName: "chart.line.uptrend.xyaxis")
        AppShortcut(intent: LogEventIntent(), phrases: [
            "Log an energy event in \(.applicationName)",
            "Erfasse ein Energieereignis in \(.applicationName)"
        ], shortTitle: "Log Event", systemImageName: "text.bubble")
    }
}
