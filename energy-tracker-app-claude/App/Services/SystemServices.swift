import Foundation
import CloudKit
import CoreData
import UserNotifications
import WidgetKit
import Observation
import UIKit
import EnergyCore

// MARK: - iCloud status and sync events (FR-1, FR-2, FR-3, §7.6)

@MainActor
@Observable
final class SyncMonitor {
    enum CloudState: Equatable {
        case checking
        case available
        case unavailable(reason: String)
    }

    private(set) var cloudState: CloudState = .checking
    /// True once the first CloudKit import of this launch finished (or failed).
    private(set) var firstImportFinished = false
    /// Called after the mirroring imported remote changes.
    var onRemoteImport: (() -> Void)?
    /// Called when the iCloud account changed.
    var onAccountChange: (() -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var debounce: Task<Void, Never>?

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                  event.endDate != nil else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.type == .import {
                    self.firstImportFinished = true
                    self.scheduleRemoteImport()
                }
                if event.type == .setup, !event.succeeded { self.firstImportFinished = true }
            }
        })
        observers.append(center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRemoteImport() }
        })
        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refreshAccountStatus() }
                self.onAccountChange?()
            }
        })
    }

    private func scheduleRemoteImport() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.onRemoteImport?()
        }
    }

    func refreshAccountStatus() async {
        guard let id = AppConfig.cloudKitContainerIdentifier, Persistence.isCloudMirroringActive else {
            cloudState = .unavailable(reason: String(localized: "iCloud sync is not set up in this build."))
            firstImportFinished = true
            return
        }
        do {
            let status = try await CKContainer(identifier: id).accountStatus()
            switch status {
            case .available: cloudState = .available
            case .noAccount: cloudState = .unavailable(reason: String(localized: "not signed in to iCloud."))
            case .restricted: cloudState = .unavailable(reason: String(localized: "iCloud is restricted on this device."))
            case .temporarilyUnavailable: cloudState = .unavailable(reason: String(localized: "iCloud is temporarily unavailable."))
            case .couldNotDetermine: cloudState = .unavailable(reason: String(localized: "iCloud status could not be determined."))
            @unknown default: cloudState = .unavailable(reason: String(localized: "iCloud status could not be determined."))
            }
        } catch {
            cloudState = .unavailable(reason: error.localizedDescription)
        }
        if cloudState != .available { firstImportFinished = true }
    }

    /// Settings line: "iCloud sync off — data stays on this iPad. Reason: not signed in to iCloud."
    var settingsLine: String? {
        guard case .unavailable(let reason) = cloudState else { return nil }
        let device = UIDevice.current.userInterfaceIdiom == .pad ? String(localized: "this iPad") : String(localized: "this iPhone")
        return String(localized: "iCloud sync off — data stays on \(device). Reason: \(reason)")
    }
}

// MARK: - Widgets (FR-22)

enum WidgetReloader {
    static func reloadAll() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Local notifications (FR-21)

@MainActor
enum NotificationScheduler {
    static let tariffReminderKey = "tariffRemindersEnabled"
    static let tariffRequestId = "tariff-check"
    static let reminderHour = 10

    static var tariffRemindersEnabled: Bool {
        get { AppConfig.sharedDefaults.bool(forKey: tariffReminderKey) }
        set { AppConfig.sharedDefaults.set(newValue, forKey: tariffReminderKey) }
    }

    /// Asks for permission only when the user turns a reminder on.
    static func enableTariffReminders() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        tariffRemindersEnabled = granted
        return granted
    }

    /// Rebuilds the schedule: one notification at 10:00 local time on the next due date.
    static func reschedule(data: LoadedDataSet, now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [tariffRequestId])
        guard tariffRemindersEnabled, let household = data.household, let tariff = data.currentTariff else { return }
        let doneOn = household.tariffCheckDoneAt.map { CalendarDate(date: $0) }
        guard let state = TariffCheck.state(contractStartDate: tariff.contractStartDate, contractPeriodMonths: tariff.contractPeriodMonths,
                                            doneOn: doneOn, cadenceMonths: household.tariffCheckCadenceMonths, today: CalendarDate.today(now: now)) else { return }
        var components = DateComponents(year: state.dueDate.year, month: state.dueDate.month, day: state.dueDate.day, hour: reminderHour, minute: 0)
        components.calendar = Calendar.current
        guard let fireDate = components.date, fireDate > now else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Time to check your tariff")
        content.body = String(localized: "Your minimum term ends on \(Format.date(state.minimumTermEnd)).")
        content.userInfo = ["deepLink": DeepLink.tariffs.url.absoluteString]
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(UNNotificationRequest(identifier: tariffRequestId, content: content, trigger: trigger))
    }
}
