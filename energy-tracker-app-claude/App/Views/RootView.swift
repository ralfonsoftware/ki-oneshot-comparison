import SwiftUI
import EnergyCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(EnergyStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        @Bindable var model = model
        Group {
            if model.waitingForICloud {
                LookingForDataView()
            } else if store.data.isEmpty {
                OnboardingView()
            } else if sizeClass == .regular {
                SidebarLayout()
            } else {
                TabLayout()
            }
        }
        .onAppear { model.usesSidebar = sizeClass == .regular }
        .onChange(of: sizeClass) { _, newValue in model.usesSidebar = newValue == .regular }
        .sheet(item: $model.sheet) { sheet in
            SheetHost(sheet: sheet)
                .environment(model)
                .environment(store)
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.default, value: model.toast)
    }
}

/// iPhone and compact width: three tabs; Settings opens from Today's toolbar (§9.1).
struct TabLayout: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: Binding(get: { model.section == .settings ? .today : model.section }, set: { model.section = $0 })) {
            Tab(AppSection.today.title, systemImage: AppSection.today.symbol, value: AppSection.today) {
                NavigationStack {
                    TodayView()
                        .navigationDestination(isPresented: $model.showSettings) { SettingsView() }
                }
            }
            Tab(AppSection.history.title, systemImage: AppSection.history.symbol, value: AppSection.history) {
                NavigationStack { HistoryView() }
            }
            Tab(AppSection.tariffs.title, systemImage: AppSection.tariffs.symbol, value: AppSection.tariffs) {
                NavigationStack { TariffsView() }
            }
        }
    }
}

/// iPad and regular width: sidebar (§9.2).
struct SidebarLayout: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(AppSection.allCases, selection: Binding(get: { Optional(model.section) }, set: { if let s = $0 { model.section = s } })) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationTitle("Energy Tracker")
        } detail: {
            NavigationStack {
                switch model.section {
                case .today: TodayView()
                case .history: HistoryView()
                case .tariffs: TariffsView()
                case .settings: SettingsView()
                }
            }
            .id(model.section)
        }
    }
}

struct SheetHost: View {
    var sheet: ActiveSheet

    var body: some View {
        switch sheet {
        case .logReading: LogReadingSheet()
        case .logEvent: EventEditorSheet(eventId: nil)
        case .editEvent(let id): EventEditorSheet(eventId: id)
        case .regression(let id): RegressionPromptSheet(promptId: id)
        case .correctReading(let id): CorrectReadingSheet(readingId: id)
        case .settings: NavigationStack { SettingsView() }
        case .duplicateTariffs(let date): DuplicateTariffsSheet(date: date)
        case .addTariff: TariffEditorSheet(tariffId: nil)
        case .editTariff(let id): TariffEditorSheet(tariffId: id)
        }
    }
}

struct ToastView: View {
    var toast: Toast

    var body: some View {
        HStack(spacing: 8) {
            if let symbol = toast.symbol { Image(systemName: symbol) }
            Text(toast.text).font(.subheadline.weight(.medium))
        }
        .foregroundStyle(toast.isError ? Theme.error : .primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("toast")
    }
}

struct LookingForDataView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Looking for your data in iCloud…")
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
