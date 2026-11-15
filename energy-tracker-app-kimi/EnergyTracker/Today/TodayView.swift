import SwiftUI
import SwiftData

struct TodayView: View {
    let repository: DataRepository
    @EnvironmentObject private var router: AppRouter
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query private var observedReadings: [MeterReading]
    @Query private var observedSnapshots: [StatusSnapshot]
    @Query private var observedTariffs: [Tariff]
    @Query private var observedHouseholds: [Household]
    @State private var showStatusDetail = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    attentionCards
                    actionButtons
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .frame(maxWidth: 760)
            }
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(String(localized: "Today"))
            .toolbar {
                if sizeClass == .compact {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(String(localized: "Settings"), systemImage: "gearshape") { router.show(.settings) }
                            .accessibilityIdentifier("today-settings")
                    }
                }
            }
            .navigationDestination(isPresented: $showStatusDetail) {
                if let status = try? EnergyEngine.status(repository: repository) {
                    StatusDetailView(status: status)
                }
            }
            .onAppear {
                _ = observedReadings.count + observedSnapshots.count + observedTariffs.count + observedHouseholds.count
            }
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        if let status = try? EnergyEngine.status(repository: repository) {
            Button {
                if status.isDefined { showStatusDetail = true }
            } label: {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        if let value = status.status {
                            StatusBadge(status: value)
                        } else {
                            Label(String(localized: "Getting started"), systemImage: "bolt.circle")
                                .font(.headline)
                                .foregroundStyle(Color.accentColor)
                        }
                        Spacer()
                        if status.isDefined {
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(status.sentence)
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.primary)
                    if status.isLowConfidence, let days = status.daysSinceLastReading {
                        Label(String(format: String(localized: "Last reading %lld days ago — status is less certain"), days), systemImage: "exclamationmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(DisplayStatus.trending.labelColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .glassCard()
            }
            .buttonStyle(.plain)
            .disabled(!status.isDefined)
            .accessibilityHint(status.isDefined ? String(localized: "Shows the calculation details") : "")
        }
    }

    @ViewBuilder
    private var attentionCards: some View {
        if let prompt = try? repository.openPrompt() {
            AttentionCard(title: String(localized: "1 reading needs a decision"), message: String(localized: "Classify the lower reading to include it in your status."), symbol: "arrow.triangle.branch") {
                Button(String(localized: "Decide")) { router.show(.regression(prompt.id)) }
            }
        }
        if let held = try? repository.heldBackSummary(), !held.isEmpty {
            AttentionCard(title: String(localized: "Records from before the restore"), message: heldMessage(held), symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
                HStack {
                    Button(String(localized: "Keep")) { perform { try repository.keepHeldBackRecords() } }
                    Button(String(localized: "Discard")) { perform { try repository.discardHeldBackRecords() } }
                }
            }
        }
        if let groups = try? repository.duplicateTariffGroups(), let group = groups.first, let day = group.first?.contractStartDate {
            AttentionCard(title: duplicateTariffTitle(day), message: String(localized: "Open Tariffs and choose which entry to keep."), symbol: "rectangle.stack.badge.exclamationmark") {
                Button(String(localized: "Choose")) { router.selectedTab = .tariffs }
            }
        }
        if let check = try? EnergyEngine.tariffCheck(repository: repository), check.isDue {
            AttentionCard(title: String(localized: "Time to check your tariff"), message: check.minimumTermEnd.map { String(format: String(localized: "Your minimum term ends on %@"), localizedDate($0)) } ?? "", symbol: "calendar.badge.clock") {
                HStack {
                    Button(String(localized: "Compare")) { router.selectedTab = .tariffs }
                    Button(String(localized: "Done")) { perform { try repository.markTariffCheckDone() } }
                }
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button { router.show(.logReading) } label: {
                Label(String(localized: "Log reading"), systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("today-log-reading")
            Button { router.show(.logEvent) } label: {
                Label(String(localized: "Log event"), systemImage: "text.bubble")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("today-log-event")
        }
        .padding(.top, 4)
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { router.report(error) }
    }

    private func heldMessage(_ held: HeldBackSummary) -> String {
        var parts: [String] = []
        if held.readings > 0 { parts.append(String(format: String(localized: "%lld readings"), held.readings)) }
        if held.events > 0 { parts.append(String(format: String(localized: "%lld events"), held.events)) }
        if held.other > 0 { parts.append(String(format: String(localized: "%lld other records"), held.other)) }
        return String(format: String(localized: "%@ arrived from another device after the restore."), parts.joined(separator: ", "))
    }

    private func duplicateTariffTitle(_ day: String) -> String {
        let date = CalendarDay.date(from: day) ?? Date()
        return String(format: String(localized: "Two tariffs start on %@ — keep one"), localizedDate(date))
    }

    private func localizedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

struct AttentionCard<Actions: View>: View {
    let title: String
    let message: String
    let symbol: String
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(DisplayStatus.trending.labelColor)
            if !message.isEmpty { Text(message).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            actions.buttonStyle(.bordered).controlSize(.small)
        }
        .glassCard()
    }
}

struct StatusDetailView: View {
    let status: LiveStatus

    var body: some View {
        List {
            Section(String(localized: "Pace")) {
                LabeledContent(String(localized: "Pace-to-date"), value: "\(EnergyFormat.kwh(status.paceToDate ?? 0)) kWh")
                LabeledContent(String(localized: "Baseline-to-date"), value: "\(EnergyFormat.kwh(status.baselineToDate ?? 0)) kWh")
                LabeledContent(String(localized: "Difference"), value: "\(EnergyFormat.kwh(status.difference ?? 0)) kWh")
            }
            Section(String(localized: "Analysis period")) {
                if let start = status.periodStart, let end = status.periodEnd {
                    LabeledContent(String(localized: "From"), value: start.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent(String(localized: "To"), value: end.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent(String(localized: "Elapsed days"), value: EnergyFormat.kwh(status.elapsedDays ?? 0, maximumFractionDigits: 2))
                LabeledContent(String(localized: "Threshold per year"), value: "\(EnergyFormat.kwh(status.annualThreshold ?? 0)) kWh")
                LabeledContent(String(localized: "Threshold this period"), value: "\(EnergyFormat.kwh(status.thresholdToDate ?? 0)) kWh")
            }
            if status.isLowConfidence {
                Section(String(localized: "Low confidence")) {
                    Text(String(format: String(localized: "The last reading was %lld days ago. Your low-confidence gap is %lld days."), status.daysSinceLastReading ?? 0, status.lowConfidenceGapDays))
                }
            }
        }
        .navigationTitle(String(localized: "Calculation"))
    }
}
