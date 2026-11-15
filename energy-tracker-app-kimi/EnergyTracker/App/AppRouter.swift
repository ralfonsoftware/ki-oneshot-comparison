import Foundation
import Combine

enum AppTab: String, CaseIterable, Identifiable {
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
        case .today: "bolt.circle"
        case .history: "chart.xyaxis.line"
        case .tariffs: "eurosign.circle"
        case .settings: "gearshape"
        }
    }
}

enum AppSheet: Identifiable {
    case logReading
    case logEvent
    case regression(UUID)
    case settings

    var id: String {
        switch self {
        case .logReading: "reading"
        case .logEvent: "event"
        case .regression(let id): "regression-\(id)"
        case .settings: "settings"
        }
    }
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: AppTab = .today
    @Published var sheet: AppSheet?
    @Published var confirmation: String?
    @Published var errorMessage: String?
    @Published var mergeNotice: String?

    func show(_ sheet: AppSheet) {
        self.sheet = sheet
    }

    func handle(url: URL, repository: DataRepository) {
        guard url.scheme == "energytracker" else { return }
        switch url.host {
        case "log-reading": sheet = .logReading
        case "log-event": sheet = .logEvent
        case "tariffs": selectedTab = .tariffs
        default: break
        }
    }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}
