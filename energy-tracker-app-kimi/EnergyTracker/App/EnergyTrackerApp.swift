import SwiftUI
import UserNotifications
import CloudKit

@main
struct EnergyTrackerApp: App {
    private let notificationDelegate = EnergyNotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    @AppStorage("appearance") private var appearance = "system"
    @StateObject private var persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(persistence.storeRevision)
                .preferredColorScheme(appearance == "system" ? nil : appearance == "light" ? .light : .dark)
                .task { await persistence.refreshAccount() }
                .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
                    Task { await persistence.refreshAccount() }
                }
        }
        .modelContainer(persistence.container)
    }
}
