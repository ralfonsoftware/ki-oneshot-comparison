import AppIntents
import Foundation

/// Opens the app on the Log Reading sheet. Compiled into the app and the widget extension so Control Center
/// controls and widgets can use it; it always runs in the app because it opens the app.
struct OpenLogReadingIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Log Reading"
    static let description = IntentDescription("Opens Energy Tracker ready to log a meter reading.")
    static let openAppWhenRun = true
    static let isDiscoverable = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppConfig.sharedDefaults.set(DeepLink.logReading.rawValue, forKey: "pendingDeepLink")
        NotificationCenter.default.post(name: .energyPendingDeepLink, object: nil)
        return .result()
    }
}

extension Notification.Name {
    static let energyPendingDeepLink = Notification.Name("EnergyTrackerPendingDeepLink")
}
