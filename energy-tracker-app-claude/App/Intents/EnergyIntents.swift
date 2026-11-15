import AppIntents
import Foundation
import EnergyCore

// FR-23. Intents run in the app process without opening the app, and use the same store, validation,
// duplicate and regression rules as the app.

struct IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    var message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

struct LogMeterReadingIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Meter Reading"
    static let description = IntentDescription("Saves a Main Meter reading with the current time and tells you the new status.")
    static let openAppWhenRun = false

    @Parameter(title: "kWh", description: "The value shown on the meter.", requestValueDialog: "What does the meter show, in kWh?")
    var kwh: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$kwh) kWh")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let store = AppEnvironment.store
        store.reload()
        // Siri and Shortcuts hand over a Double; its shortest decimal representation is what the user said or typed.
        guard kwh.isFinite, let value = Decimal(invariant: String(kwh)) else {
            throw IntentFailure(message: String(localized: "Enter a number, for example 12345.6."))
        }
        do {
            switch try store.logReading(kwh: value, at: Date()) {
            case .alreadySaved:
                let text = String(localized: "Already saved.")
                return .result(value: text, dialog: "\(text)")
            case .saved(_, let status, _, let triggeredRegression):
                let text: String
                if triggeredRegression {
                    text = String(localized: "Saved. This reading is lower than the previous one — open Energy Tracker to classify it.")
                } else if let r = status.result {
                    text = String(localized: "Saved \(Format.kwhWithUnit(value)). \(StatusCopy.spoken(r))")
                } else {
                    text = String(localized: "Saved \(Format.kwhWithUnit(value)).")
                }
                return .result(value: text, dialog: "\(text)")
            }
        } catch let error as StoreError {
            throw IntentFailure(message: error.errorDescription ?? "")
        }
    }
}

struct GetEnergyStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Energy Status"
    static let description = IntentDescription("Tells you in one sentence whether your electricity use is on track.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let store = AppEnvironment.store
        store.reload()
        let text: String
        switch store.data.status() {
        case .defined(let r):
            text = r.isLowConfidence ? "\(StatusCopy.spoken(r)) \(StatusCopy.lowConfidence(r))." : StatusCopy.spoken(r)
        case .undefined(let reason):
            text = StatusCopy.undefined(reason) + "."
        }
        return .result(value: text, dialog: "\(text)")
    }
}

struct LogEventIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Event"
    static let description = IntentDescription("Saves a short note about something that affects consumption, such as being away.")
    static let openAppWhenRun = false

    @Parameter(title: "Event", description: "For example: away 2 weeks, sauna 3h.", requestValueDialog: "What happened?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log event \(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppEnvironment.store
        store.reload()
        do {
            try store.addEvent(text: text, occurredAt: Date(), tag: nil)
        } catch let error as StoreError {
            throw IntentFailure(message: error.errorDescription ?? "")
        }
        return .result(dialog: "\(String(localized: "Event saved."))")
    }
}

struct EnergyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogMeterReadingIntent(),
            phrases: [
                "Log a meter reading in \(.applicationName)",
                "Log meter reading with \(.applicationName)",
                "New \(.applicationName) reading",
            ],
            shortTitle: "Log Reading",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: GetEnergyStatusIntent(),
            phrases: [
                "Get my \(.applicationName) status",
                "Is my electricity on track in \(.applicationName)",
                "\(.applicationName) status",
            ],
            shortTitle: "Energy Status",
            systemImageName: "gauge.with.dots.needle.33percent"
        )
        AppShortcut(
            intent: LogEventIntent(),
            phrases: [
                "Log an event in \(.applicationName)",
                "Add a note to \(.applicationName)",
            ],
            shortTitle: "Log Event",
            systemImageName: "note.text.badge.plus"
        )
    }
}
