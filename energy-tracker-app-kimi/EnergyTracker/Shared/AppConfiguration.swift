import Foundation

enum AppConfiguration {
    static let bundleIdentifier = "com.ralfehlert.EnergyTracker"
    static let appGroupIdentifier = "group.com.ralfehlert.EnergyTracker"
    static let cloudKitContainerIdentifier = "iCloud.com.ralfehlert.EnergyTracker"
    static let logReadingURL = URL(string: "energytracker://log-reading")!
    static let logEventURL = URL(string: "energytracker://log-event")!
    static let tariffsURL = URL(string: "energytracker://tariffs")!

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITesting")
    }

    static var isLocalStoreOnly: Bool {
        isUITesting || ProcessInfo.processInfo.arguments.contains("-LocalStoreOnly")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
