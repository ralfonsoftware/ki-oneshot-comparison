import SwiftUI
import SwiftData
import UserNotifications

/// Shared container for the app process, including App Intents that run without UI.
@MainActor
enum AppEnvironment {
    static let container: ModelContainer = Persistence.makeContainer(role: .app)
    static let store = EnergyStore(container: container)
    static let sync = SyncMonitor()
    static let model = AppModel(store: store, sync: sync)
}

@main
struct EnergyTrackerApp: App {
    @State private var model = AppEnvironment.model
    @AppStorage("appearance") private var appearance: Appearance = .system
    @Environment(\.scenePhase) private var scenePhase
    private let notificationDelegate = NotificationDelegate()

    init() {
        notificationDelegate.model = AppEnvironment.model
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.store)
                .modelContainer(AppEnvironment.container)
                .preferredColorScheme(appearance.colorScheme)
                .task { await model.start() }
                .onOpenURL { url in
                    if let link = DeepLink(url: url) { model.open(link) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .energyPendingDeepLink)) { _ in
                    model.consumePendingAction()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.store.reload()
                        model.consumePendingAction()
                    }
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Log Reading") { model.present(.logReading) }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(model.store.data.isEmpty)
                Button("Log Event") { model.present(.logEvent) }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(model.store.data.isEmpty)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings") { model.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// Per-Apple-device appearance (FR-26).
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }
}
