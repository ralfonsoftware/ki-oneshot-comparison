import SwiftUI
import EnergyCore

extension LoadedDataSet {
    func tariffCheck(now: Date = Date()) -> TariffCheckState? {
        guard let household, let tariff = currentTariff else { return nil }
        return TariffCheck.state(contractStartDate: tariff.contractStartDate, contractPeriodMonths: tariff.contractPeriodMonths,
                                 doneOn: household.tariffCheckDoneAt.map { CalendarDate(date: $0) },
                                 cadenceMonths: household.tariffCheckCadenceMonths, today: CalendarDate.today(now: now))
    }

    var openPromptCount: Int { prompts.filter { !$0.isResolved }.count }

    var currency: String { household?.currency ?? "EUR" }
}

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(EnergyStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let status = store.data.status()
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let result = status.result {
                    NavigationLink {
                        CalculationDetailView(result: result)
                    } label: {
                        StatusCard(outcome: status)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Shows how the status is calculated"))
                } else {
                    StatusCard(outcome: status)
                }

                AttentionCards()

                VStack(spacing: 10) {
                    Button {
                        model.present(.logReading)
                    } label: {
                        Label("Log reading", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("logReadingButton")

                    Button {
                        model.present(.logEvent)
                    } label: {
                        Label("Log event", systemImage: "note.text.badge.plus")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .accessibilityIdentifier("logEventButton")
                }
                .padding(.top, 4)
            }
            .padding()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(AppSection.today.title)
        .toolbar {
            if sizeClass != .regular {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.openSettings()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("settingsButton")
                }
            }
        }
    }
}

/// The product (§1, principle 2): state label in its Status color, one plain sentence, low-confidence note.
struct StatusCard: View {
    var outcome: StatusOutcome

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch outcome {
            case .defined(let r):
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: r.status.symbol)
                        .font(.title)
                        .foregroundStyle(Theme.color(r.status))
                        .accessibilityHidden(true)
                    Text(r.status.label)
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(Theme.labelColor(r.status))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                Text(StatusCopy.sentence(r))
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                if r.isLowConfidence {
                    Label(StatusCopy.lowConfidence(r), systemImage: "questionmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Theme.uncertain.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .undefined(let reason):
                Label {
                    Text(StatusCopy.undefined(reason))
                        .font(.title3.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: reason == .noBaseline ? "target" : "gauge.with.dots.needle.0percent")
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(background, in: RoundedRectangle(cornerRadius: 24))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("statusCard")
    }

    private var background: Color {
        if let r = outcome.result { return Theme.color(r.status).opacity(Theme.tintOpacity) }
        return Color.secondary.opacity(0.08)
    }
}

/// Shown only when needed, in the order of FR-7.
struct AttentionCards: View {
    @Environment(AppModel.self) private var model
    @Environment(EnergyStore.self) private var store
    @State private var confirmDiscard = false

    var body: some View {
        let data = store.data
        VStack(spacing: 12) {
            if data.openPromptCount > 0 {
                AttentionCard(symbol: "exclamationmark.arrow.circlepath", text: data.openPromptCount == 1
                              ? String(localized: "1 reading needs a decision")
                              : String(localized: "\(data.openPromptCount) readings need a decision")) {
                    Button("Decide") { model.presentOpenPrompt() }
                        .buttonStyle(.borderedProminent)
                }
                .accessibilityIdentifier("regressionCard")
            }

            ForEach(store.classificationNotices) { notice in
                AttentionCard(symbol: "arrow.triangle.2.circlepath",
                              text: String(localized: "This reading was classified differently on another device. It is now: \(notice.classification.title).")) {
                    Button("OK") { store.dismissNotice(notice) }
                        .buttonStyle(.bordered)
                }
            }

            if !data.heldBack.readings.isEmpty || !data.heldBack.events.isEmpty || !data.heldBack.others.isEmpty {
                AttentionCard(symbol: "clock.arrow.circlepath", text: heldBackText(data.heldBack)) {
                    HStack {
                        Button("Keep") { perform { try store.keepHeldBack() } }
                            .buttonStyle(.borderedProminent)
                        Button("Discard", role: .destructive) { confirmDiscard = true }
                            .buttonStyle(.bordered)
                    }
                }
                .confirmationDialog("Discard these records?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("Discard", role: .destructive) { perform { try store.discardHeldBack() } }
                }
            }

            ForEach(store.duplicateTariffStarts, id: \.date) { duplicate in
                AttentionCard(symbol: "doc.on.doc", text: String(localized: "Two tariffs start on \(Format.date(duplicate.date)) — keep one")) {
                    Button("Choose") { model.present(.duplicateTariffs(duplicate.date)) }
                        .buttonStyle(.borderedProminent)
                }
            }

            if let check = data.tariffCheck(), check.isDue {
                AttentionCard(symbol: "calendar.badge.clock", text: String(localized: "Time to check your tariff — your minimum term ends on \(Format.date(check.minimumTermEnd))")) {
                    HStack {
                        Button("Compare") { model.open(.compare) }
                            .buttonStyle(.borderedProminent)
                        Button("Done") { perform { try store.markTariffCheckDone() } }
                            .buttonStyle(.bordered)
                    }
                }
                .accessibilityIdentifier("tariffCheckCard")
            }
        }
    }

    private func heldBackText(_ held: LoadedDataSet.HeldBack) -> String {
        var parts: [String] = []
        if !held.readings.isEmpty {
            parts.append(held.readings.count == 1 ? String(localized: "1 reading") : String(localized: "\(held.readings.count) readings"))
        }
        if !held.events.isEmpty {
            parts.append(held.events.count == 1 ? String(localized: "1 event") : String(localized: "\(held.events.count) events"))
        }
        if parts.isEmpty {
            parts.append(held.others.count == 1 ? String(localized: "1 record") : String(localized: "\(held.others.count) records"))
        }
        let list = parts.formatted(.list(type: .and))
        return String(localized: "\(list) from before the restore arrived from another device.")
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { model.showError(error) }
    }
}

struct AttentionCard<Actions: View>: View {
    var symbol: String
    var text: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(text).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: symbol).foregroundStyle(Theme.accent)
            }
            .font(.body)
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
    }
}

extension RegressionClassification {
    var title: String {
        switch self {
        case .reset: String(localized: "reset")
        case .rollover: String(localized: "rollover")
        }
    }
}

/// FR-8: text only, no chart.
struct CalculationDetailView: View {
    var result: StatusResult
    @Environment(EnergyStore.self) private var store

    var body: some View {
        let r = result
        let days = Format.number(r.pace.elapsedDays, places: 1)
        List {
            Section {
                StatusBadge(status: r.status)
                    .listRowBackground(Color.clear)
            }
            Section("Pace") {
                LabeledContent("Used so far", value: Format.kwhWithUnit(r.pace.paceKwh))
                LabeledContent("Baseline for the same period", value: Format.kwhWithUnit(r.baselineToDateKwh))
                LabeledContent("Period") {
                    Text("\(Format.date(r.pace.windowStart)) – \(Format.date(r.pace.windowEnd)) · \(days) days")
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Difference", value: signedKwh(r.differenceKwh))
            }
            Section("Threshold") {
                LabeledContent("Per year", value: Format.kwhWithUnit(r.annualThresholdKwh))
                LabeledContent("Scaled to the period", value: Format.kwhWithUnit(r.thresholdToDateKwh))
            }
            Section {
                Text(explanation(r))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if r.isLowConfidence {
                Section("Confidence") {
                    Label {
                        Text("Last reading \(Format.daysFloor(r.daysSinceLastReading)) days ago; you count a status as less certain after \(r.lowConfidenceGapDays) days.")
                    } icon: {
                        Image(systemName: "questionmark.circle").foregroundStyle(Theme.uncertain)
                    }
                }
            }
        }
        .navigationTitle("How this is calculated")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func signedKwh(_ value: Decimal) -> String {
        let text = Format.kwhWithUnit(value < 0 ? -value : value)
        return value < 0 ? "−\(text)" : "+\(text)"
    }

    private func explanation(_ r: StatusResult) -> String {
        switch r.status {
        case .trending: String(localized: "The difference is larger than the threshold for this period, so the status is trending.")
        case .belowBaseline: String(localized: "You used less than the baseline for this period, so the status is below baseline.")
        case .withinRange: String(localized: "The difference is not larger than the threshold for this period, so the status is within range.")
        }
    }
}
