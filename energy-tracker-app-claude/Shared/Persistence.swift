import Foundation
import SwiftData
import os

enum AppConfig {
    /// App Group shared by the app and the widget extension (§11, Shared store).
    static var appGroupIdentifier: String { info("ETAppGroupIdentifier") ?? "group.de.ralfonsoftware.EnergyTracker" }
    /// CloudKit container `iCloud.<bundle id>`. Empty disables sync (local only).
    static var cloudKitContainerIdentifier: String? { info("ETCloudKitContainerIdentifier").flatMap { $0.isEmpty ? nil : $0 } }
    static let urlScheme = "energytracker"

    static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-ETUITesting") }

    private static func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    /// Shared, per-Apple-device preferences (never synced).
    static var sharedDefaults: UserDefaults {
        if isUITesting { return .standard }
        return UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
}

enum DeepLink: String {
    case logReading = "log-reading"
    case logEvent = "log-event"
    case today
    case tariffs
    case compare

    var url: URL { URL(string: "\(AppConfig.urlScheme)://\(rawValue)")! }

    init?(url: URL) {
        guard url.scheme == AppConfig.urlScheme, let host = url.host() else { return nil }
        self.init(rawValue: host)
    }
}

let log = Logger(subsystem: "de.ralfonsoftware.EnergyTracker", category: "app")

/// Creates the shared model container.
enum Persistence {
    enum Role {
        /// The app: mirrors to CloudKit when available.
        case app
        /// Widgets: read the same store, never mirror.
        case widget
    }

    static var storeURL: URL {
        let base: URL
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupIdentifier) {
            base = group.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        } else {
            base = URL.applicationSupportDirectory
        }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // Readable after first unlock so Lock Screen widgets work (§11, Security).
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: base.path())
        return base.appending(path: "EnergyTracker.store")
    }

    /// Whether the container was created with CloudKit mirroring.
    nonisolated(unsafe) private(set) static var isCloudMirroringActive = false

    static func makeContainer(role: Role) -> ModelContainer {
        let schema = Schema(versionedSchema: EnergySchemaV1.self)
        if AppConfig.isUITesting {
            let config = ModelConfiguration("UITest", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, migrationPlan: EnergyMigrationPlan.self, configurations: [config])
        }
        if role == .app, let containerId = AppConfig.cloudKitContainerIdentifier {
            do {
                let config = ModelConfiguration("EnergyTracker", schema: schema, url: storeURL, cloudKitDatabase: .private(containerId))
                let container = try ModelContainer(for: schema, migrationPlan: EnergyMigrationPlan.self, configurations: [config])
                isCloudMirroringActive = true
                return container
            } catch {
                log.error("CloudKit-backed store failed, falling back to local only: \(error.localizedDescription, privacy: .public)")
            }
        }
        do {
            let config = ModelConfiguration("EnergyTracker", schema: schema, url: storeURL, allowsSave: role == .app, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, migrationPlan: EnergyMigrationPlan.self, configurations: [config])
        } catch {
            log.fault("Local store failed: \(error.localizedDescription, privacy: .public)")
            let config = ModelConfiguration("Fallback", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, configurations: [config])
        }
    }
}
