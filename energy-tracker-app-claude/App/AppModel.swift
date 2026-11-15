import Foundation
import SwiftUI
import Observation
import UserNotifications
import EnergyCore

enum AppSection: String, Hashable, CaseIterable, Identifiable {
    case today, history, tariffs, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: String(localized: "Today")
        case .history: String(localized: "History")
        case .tariffs: String(localized: "Tariffs")
        case .settings: String(localized: "Settings")
        }
    }

    var symbol: String {
        switch self {
        case .today: "gauge.with.dots.needle.33percent"
        case .history: "chart.xyaxis.line"
        case .tariffs: "eurosign.circle"
        case .settings: "gearshape"
        }
    }
}

/// One sheet at a time (§9.3). A follow-up replaces the current sheet.
enum ActiveSheet: Identifiable, Hashable {
    case logReading
    case logEvent
    case editEvent(UUID)
    case regression(UUID)
    case correctReading(UUID)
    case settings
    case duplicateTariffs(CalendarDate)
    case addTariff
    case editTariff(UUID)

    var id: String {
        switch self {
        case .logReading: "logReading"
        case .logEvent: "logEvent"
        case .editEvent(let id): "editEvent-\(id)"
        case .regression(let id): "regression-\(id)"
        case .correctReading(let id): "correct-\(id)"
        case .settings: "settings"
        case .duplicateTariffs(let d): "dupTariffs-\(d.iso)"
        case .addTariff: "addTariff"
        case .editTariff(let id): "editTariff-\(id)"
        }
    }
}

struct Toast: Equatable, Identifiable {
    let id = UUID()
    var text: String
    var symbol: String?
    var isError = false
}

@MainActor
@Observable
final class AppModel {
    let store: EnergyStore
    let sync: SyncMonitor

    var section: AppSection = .today
    var sheet: ActiveSheet?
    var toast: Toast?
    /// Opens the Compare part of the Tariffs screen.
    var showCompare = false
    var waitingForICloud = false

    private var toastTask: Task<Void, Never>?

    init(store: EnergyStore, sync: SyncMonitor) {
        self.store = store
        self.sync = sync
        store.afterChange = { [weak self] kind, remote in
            self?.afterChange(kind, remote: remote)
        }
        sync.onRemoteImport = { [weak self] in self?.processRemoteImport() }
        sync.onAccountChange = { [weak self] in self?.processRemoteImport() }
    }

    func start() async {
        await seedForUITestsIfRequested()
        do { try store.runMaintenance(remote: false) } catch { log.error("Launch maintenance failed: \(error.localizedDescription)") }
        NotificationScheduler.reschedule(data: store.data)
        WidgetReloader.reloadAll()
        consumePendingAction()
        await sync.refreshAccountStatus()
        await waitForFirstImportIfNeeded()
    }

    /// UI tests pass a data set as base64 JSON in `ETUITestSeedJSON`; it is imported into the in-memory store.
    private func seedForUITestsIfRequested() async {
        guard AppConfig.isUITesting, let raw = ProcessInfo.processInfo.environment["ETUITestSeedJSON"],
              let data = Data(base64Encoded: raw), let records = try? ExportFormat.decode(data) else { return }
        _ = try? await store.replaceAll(with: records) { _ in }
    }

    /// First launch with iCloud: wait up to 15 s for existing data before offering onboarding (FR-3).
    private func waitForFirstImportIfNeeded() async {
        guard store.data.isEmpty, sync.cloudState == .available, !AppConfig.isUITesting else { return }
        waitingForICloud = true
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline, store.data.isEmpty, !sync.firstImportFinished {
            try? await Task.sleep(for: .milliseconds(250))
            store.reload()
        }
        store.reload()
        waitingForICloud = false
    }

    private func processRemoteImport() {
        do { try store.runMaintenance(remote: true) } catch { log.error("Sync maintenance failed: \(error.localizedDescription)") }
    }

    private func afterChange(_ kind: ChangeKind, remote: Bool) {
        WidgetReloader.reloadAll()
        if remote || kind.contains(.tariffs) || kind.contains(.settings) {
            NotificationScheduler.reschedule(data: store.data)
        }
    }

    // MARK: Navigation

    func open(_ link: DeepLink) {
        switch link {
        case .logReading: present(.logReading)
        case .logEvent: present(.logEvent)
        case .today: section = .today
        case .tariffs: sheet = nil; section = .tariffs
        case .compare: sheet = nil; section = .tariffs; showCompare = true
        }
    }

    /// Pushes Settings from Today in the tab layout.
    var showSettings = false
    /// Set by the root view: sidebar layout (regular width) or tab layout.
    var usesSidebar = false

    func openSettings() {
        sheet = nil
        if usesSidebar {
            section = .settings
        } else {
            section = .today
            showSettings = true
        }
    }

    func present(_ sheet: ActiveSheet) {
        // Never stack: a new sheet replaces the current one.
        self.sheet = sheet
    }

    /// Opens the oldest open regression decision, if any.
    func presentOpenPrompt() {
        if let prompt = Readings.activeOpenPrompt(readings: Readings.ordered(store.data.readingInputs), prompts: store.data.promptInputs) {
            present(.regression(prompt.id))
        }
    }

    /// Actions requested by a Control Center control or widget while the app was not running.
    static let pendingActionKey = "pendingDeepLink"

    func consumePendingAction() {
        let defaults = AppConfig.sharedDefaults
        guard let raw = defaults.string(forKey: Self.pendingActionKey) else { return }
        defaults.removeObject(forKey: Self.pendingActionKey)
        if let link = DeepLink(rawValue: raw) { open(link) }
    }

    func showToast(_ text: String, symbol: String? = nil, isError: Bool = false) {
        toast = Toast(text: text, symbol: symbol, isError: isError)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func showError(_ error: Error) {
        showToast((error as? LocalizedError)?.errorDescription ?? error.localizedDescription, symbol: "exclamationmark.triangle", isError: true)
    }
}

/// Opens notification taps as deep links.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    weak var model: AppModel?

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo["deepLink"] as? String,
              let url = URL(string: raw), let link = DeepLink(url: url) else { return }
        await MainActor.run { model?.open(link) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
