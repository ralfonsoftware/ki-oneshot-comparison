import SwiftUI
import SwiftData
import CloudKit
import WidgetKit

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var router = AppRouter()
    @State private var repository: DataRepository?
    @State private var isEmpty = true
    @State private var waitingForCloud = false
    @Query private var households: [Household]

    var body: some View {
        Group {
            if let repository {
                if waitingForCloud {
                    InitialSyncView()
                } else if isEmpty {
                    OnboardingView(repository: repository) {
                        isEmpty = false
                    }
                    .environmentObject(router)
                } else {
                    ContentView(repository: repository)
                        .environmentObject(router)
                }
            } else {
                ProgressView(String(localized: "Opening your data…"))
            }
        }
        .task { await openStore() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let repository else { return }
            Task { @MainActor in
                try? repository.performMaintenance()
                router.mergeNotice = repository.lastMergeNotice
                NotificationScheduler.rebuildIfEnabled(repository: repository)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        .onChange(of: households.count) { _, _ in
            guard let repository, !waitingForCloud else { return }
            if let empty = try? repository.isDataSetEmpty(), !empty { isEmpty = false }
        }
        .sheet(item: $router.sheet) { sheet in
            if let repository {
                sheetContent(sheet, repository: repository)
            }
        }
        .alert(String(localized: "Something needs attention"), isPresented: Binding(
            get: { router.errorMessage != nil }, set: { if !$0 { router.errorMessage = nil } }
        )) {
            Button(String(localized: "OK")) { router.errorMessage = nil }
        } message: {
            Text(router.errorMessage ?? "")
        }
        .alert(String(localized: "Classification updated"), isPresented: Binding(
            get: { router.mergeNotice != nil }, set: { if !$0 { router.mergeNotice = nil } }
        )) {
            Button(String(localized: "OK")) { router.mergeNotice = nil }
        } message: {
            Text(router.mergeNotice ?? "")
        }
        .overlay(alignment: .bottom) {
            if let confirmation = router.confirmation {
                Text(confirmation)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: confirmation) {
                        try? await Task.sleep(for: .seconds(3))
                        if router.confirmation == confirmation { router.confirmation = nil }
                    }
            }
        }
        .animation(reduceMotion ? nil : .default, value: router.confirmation)
        .onOpenURL { url in
            if let repository { router.handle(url: url, repository: repository) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openEnergyTariffs)) { _ in
            router.selectedTab = .tariffs
            router.sheet = nil
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: AppSheet, repository: DataRepository) -> some View {
        switch sheet {
        case .logReading:
            ReadingEntryView(repository: repository)
                .environmentObject(router)
        case .logEvent:
            EventEntryView(repository: repository)
                .environmentObject(router)
        case .regression(let id):
            if let prompt = try? repository.prompts().first(where: { $0.id == id }) {
                RegressionDecisionView(prompt: prompt, repository: repository)
                    .environmentObject(router)
            } else {
                Text(String(localized: "This decision is no longer available."))
                    .padding()
            }
        case .settings:
            NavigationStack { SettingsView(repository: repository) }
                .environmentObject(router)
        }
    }

    @MainActor
    private func openStore() async {
        guard repository == nil else { return }
        let repository = DataRepository(context: context)
        self.repository = repository
        try? repository.performMaintenance()
        router.mergeNotice = repository.lastMergeNotice
        isEmpty = (try? repository.isDataSetEmpty()) ?? true
        NotificationScheduler.rebuildIfEnabled(repository: repository)

        guard isEmpty, PersistenceController.shared.isCloudKitConfigured, !AppConfiguration.isUITesting else { return }
        let status = try? await CKContainer(identifier: AppConfiguration.cloudKitContainerIdentifier).accountStatus()
        guard status == .available else { return }
        waitingForCloud = true
        let deadline = ContinuousClock.now + .seconds(15)
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(500))
            try? repository.performMaintenance()
            if let empty = try? repository.isDataSetEmpty(), !empty {
                isEmpty = false
                waitingForCloud = false
                return
            }
        }
        waitingForCloud = false
    }
}

private struct InitialSyncView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "icloud")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            ProgressView()
            Text(String(localized: "Looking for your data in iCloud…"))
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

private struct ContentView: View {
    let repository: DataRepository
    @EnvironmentObject private var router: AppRouter
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    List {
                        ForEach(AppTab.allCases) { tab in
                            Button { router.selectedTab = tab } label: {
                                Label(tab.title, systemImage: tab.symbol)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(router.selectedTab == tab ? Color.accentColor : .primary)
                            .listRowBackground(router.selectedTab == tab ? Color.accentColor.opacity(0.12) : Color.clear)
                        }
                    }
                    .navigationTitle(String(localized: "Energy Tracker"))
                } detail: {
                    detail(for: router.selectedTab)
                }
            } else {
                TabView(selection: $router.selectedTab) {
                    ForEach([AppTab.today, .history, .tariffs]) { tab in
                        detail(for: tab)
                            .tabItem { Label(tab.title, systemImage: tab.symbol) }
                            .tag(tab)
                    }
                }
            }
        }
        .background {
            Button(String(localized: "Log reading")) { router.show(.logReading) }.keyboardShortcut("n", modifiers: .command)
                .accessibilityHidden(true)
            Button(String(localized: "Log event")) { router.show(.logEvent) }.keyboardShortcut("e", modifiers: .command)
                .accessibilityHidden(true)
            Button(String(localized: "Settings")) { router.show(.settings) }.keyboardShortcut(",", modifiers: .command)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func detail(for tab: AppTab) -> some View {
        switch tab {
        case .today: TodayView(repository: repository)
        case .history: HistoryView(repository: repository)
        case .tariffs: TariffsView(repository: repository)
        case .settings: NavigationStack { SettingsView(repository: repository) }
        }
    }
}
