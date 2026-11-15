import Foundation
import UserNotifications

extension Notification.Name {
    static let openEnergyTariffs = Notification.Name("openEnergyTariffs")
}

@MainActor
enum NotificationScheduler {
    private static let identifier = "tariff-check"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: AppConfiguration.appGroupIdentifier) }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func rebuildIfEnabled(repository: DataRepository) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard defaults?.bool(forKey: "tariffRemindersEnabled") == true,
              let check = try? EnergyEngine.tariffCheck(repository: repository) else { return }
        var target = check.isDue ? Date() : check.nextDue
        if target == nil && check.isDue { target = Date() }
        guard let target else { return }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: target)
        components.hour = 10; components.minute = 0
        var date = Calendar.current.date(from: components) ?? target
        if date <= Date() {
            date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        }
        components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Time to check your tariff")
        if let end = check.minimumTermEnd {
            content.body = String(format: String(localized: "Your minimum term ends on %@. Compare your current tariff when you have a moment."), end.formatted(date: .abbreviated, time: .omitted))
        } else {
            content.body = String(localized: "Compare your current tariff when you have a moment.")
        }
        content.sound = .default
        content.userInfo = ["destination": "tariffs"]
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
    }
}

final class EnergyNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if response.notification.request.content.userInfo["destination"] as? String == "tariffs" {
            NotificationCenter.default.post(name: .openEnergyTariffs, object: nil)
        }
    }
}
