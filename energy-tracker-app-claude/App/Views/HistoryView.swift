import SwiftUI
import Charts
import EnergyCore

struct HistoryView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case trend, readings, events
        var id: String { rawValue }
        var title: String {
            switch self {
            case .trend: String(localized: "Trend")
            case .readings: String(localized: "Readings")
            case .events: String(localized: "Events")
            }
        }
    }

    @State private var segment: Segment = .trend
    @State private var search = ""
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        GeometryReader { proxy in
            // iPad landscape: chart on top, Readings and Events side by side below (§9.2).
            if sizeClass == .regular, proxy.size.width > proxy.size.height, proxy.size.width >= 700 {
                VStack(spacing: 0) {
                    TrendChartSection()
                        .frame(height: max(260, proxy.size.height * 0.42))
                        .padding()
                    Divider()
                    HStack(spacing: 0) {
                        ReadingsList(search: search)
                        Divider()
                        EventsList(search: search)
                    }
                }
                .searchable(text: $search)
            } else {
                VStack(spacing: 0) {
                    Picker("View", selection: $segment) {
                        ForEach(Segment.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    switch segment {
                    case .trend:
                        ScrollView { TrendChartSection().padding() }
                    case .readings:
                        ReadingsList(search: search).searchable(text: $search)
                    case .events:
                        EventsList(search: search).searchable(text: $search)
                    }
                }
            }
        }
        .navigationTitle(AppSection.history.title)
    }
}

// MARK: - Trend (FR-9)

struct TrendPoint: Identifiable {
    var id: UUID
    var date: Date
    var difference: Double
    var pace: Double
    var baseline: Double
    var status: EnergyStatus
    var segment: Int
}

struct TrendGap: Identifiable {
    var id: Date { start }
    var start: Date
    var end: Date
}

struct TrendChartSection: View {
    enum Range: String, CaseIterable, Identifiable {
        case month, quarter, year, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .month: String(localized: "1 month")
            case .quarter: String(localized: "3 months")
            case .year: String(localized: "1 year")
            case .all: String(localized: "All")
            }
        }
        var start: Date? {
            let cal = Calendar.current
            switch self {
            case .month: return cal.date(byAdding: .month, value: -1, to: Date())
            case .quarter: return cal.date(byAdding: .month, value: -3, to: Date())
            case .year: return cal.date(byAdding: .year, value: -1, to: Date())
            case .all: return nil
            }
        }
    }

    @Environment(EnergyStore.self) private var store
    @AppStorage("trendRange") private var range: Range = .quarter

    var body: some View {
        let (points, gaps) = series()
        VStack(alignment: .leading, spacing: 12) {
            Picker("Range", selection: $range) {
                ForEach(Range.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            if points.isEmpty {
                ContentUnavailableView {
                    Label("No history yet", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("Each reading you log adds a point here.")
                }
                .frame(minHeight: 220)
            } else {
                Text("Difference to baseline pace, in kWh")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TrendChart(points: points, gaps: gaps)
                    .frame(minHeight: 220)
                ForEach(gaps) { gap in
                    Label(String(localized: "No reading between \(Format.dayMonth(gap.start)) and \(Format.dayMonth(gap.end)), so this stretch is shown as a gap."), systemImage: "pause.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Snapshots in range, split into segments wherever two consecutive snapshots are more than the gap setting apart.
    private func series() -> ([TrendPoint], [TrendGap]) {
        let gapSeconds = TimeInterval(store.data.household?.lowConfidenceGapDays ?? 45) * 86_400
        var snapshots = store.data.snapshots.sorted { $0.computedAt < $1.computedAt }
        if let start = range.start { snapshots = snapshots.filter { $0.computedAt >= start } }
        var points: [TrendPoint] = []
        var gaps: [TrendGap] = []
        var segment = 0
        var previous: StatusSnapshot?
        for s in snapshots {
            if let p = previous, s.computedAt.timeIntervalSince(p.computedAt) > gapSeconds {
                segment += 1
                gaps.append(TrendGap(start: p.computedAt, end: s.computedAt))
            }
            let pace = NSDecimalNumber(decimal: s.paceToDateKwh).doubleValue
            let baseline = NSDecimalNumber(decimal: s.baselineToDateKwh).doubleValue
            points.append(TrendPoint(id: s.id, date: s.computedAt, difference: pace - baseline, pace: pace, baseline: baseline, status: s.status, segment: segment))
            previous = s
        }
        return (points, gaps)
    }
}

struct TrendChart: View {
    var points: [TrendPoint]
    var gaps: [TrendGap]

    var body: some View {
        Chart {
            ForEach(gaps) { gap in
                RectangleMark(xStart: .value("Gap start", gap.start), xEnd: .value("Gap end", gap.end))
                    .foregroundStyle(Theme.uncertain.opacity(0.14))
                    .annotation(position: .top, alignment: .center) {
                        Text("Gap").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            RuleMark(y: .value("Baseline pace", 0))
                .foregroundStyle(.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            ForEach(points) { p in
                LineMark(x: .value("Date", p.date), y: .value("Difference", p.difference), series: .value("Segment", p.segment))
                    .foregroundStyle(.secondary)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", p.date), y: .value("Difference", p.difference))
                    .foregroundStyle(Theme.color(p.status))
                    .symbolSize(30)
                    .accessibilityLabel(Format.date(p.date))
                    .accessibilityValue(Text("\(p.status.label), \(Format.kwhWhole(Decimal(p.difference))) kWh"))
            }
        }
        .chartYAxisLabel("kWh")
        .accessibilityChartDescriptor(TrendChartDescriptor(points: points))
    }
}

/// VoiceOver description and Audio Graph (§11, Accessibility).
struct TrendChartDescriptor: AXChartDescriptorRepresentable {
    var points: [TrendPoint]

    func makeChartDescriptor() -> AXChartDescriptor {
        let dates = points.map(\.date)
        let values = points.map(\.difference)
        let minDate = dates.min() ?? Date(), maxDate = dates.max() ?? Date()
        let xAxis = AXNumericDataAxisDescriptor(title: String(localized: "Date"), range: minDate.timeIntervalSince1970...max(minDate.timeIntervalSince1970 + 1, maxDate.timeIntervalSince1970), gridlinePositions: []) { value in
            Format.date(Date(timeIntervalSince1970: value))
        }
        let low = min(values.min() ?? 0, 0), high = max(values.max() ?? 0, 1)
        let yAxis = AXNumericDataAxisDescriptor(title: String(localized: "Difference to baseline pace in kWh"), range: low...high, gridlinePositions: [0]) { value in
            String(localized: "\(Format.kwhWhole(Decimal(value))) kWh")
        }
        let series = AXDataSeriesDescriptor(name: String(localized: "Difference to baseline pace"), isContinuous: true, dataPoints: points.map {
            AXDataPoint(x: $0.date.timeIntervalSince1970, y: $0.difference, additionalValues: [], label: $0.status.label)
        })
        return AXChartDescriptor(title: String(localized: "Trend history"), summary: String(localized: "Difference between your consumption and the baseline pace over time. Points above zero use more than the baseline."), xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }
}

// MARK: - Readings (FR-10)

struct ReadingsList: View {
    var search: String
    @Environment(EnergyStore.self) private var store

    var body: some View {
        let data = store.data
        let openReadingIds = Set(data.prompts.filter { !$0.isResolved }.compactMap(\.meterReadingId))
        let rows = data.readings
            .sorted { ($0.readingTimestamp, $0.id.uuidString.lowercased()) > ($1.readingTimestamp, $1.id.uuidString.lowercased()) }
            .filter { reading in
                guard !search.isEmpty else { return true }
                let value = Format.kwh(data.effectiveValues[reading.id] ?? reading.originalKwhValue)
                return value.localizedCaseInsensitiveContains(search) || Format.dateTime(reading.readingTimestamp).localizedCaseInsensitiveContains(search)
            }
        List {
            if rows.isEmpty {
                Text(search.isEmpty ? String(localized: "No readings yet.") : String(localized: "No matching readings."))
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { reading in
                NavigationLink {
                    ReadingDetailView(readingId: reading.id)
                } label: {
                    ReadingRow(reading: reading, effective: data.effectiveValues[reading.id] ?? reading.originalKwhValue,
                               corrections: (data.correctionsByEntity[reading.id] ?? []).filter { $0.entityType == AuditEntityType.meterReading },
                               needsDecision: openReadingIds.contains(reading.id))
                }
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("readingsList")
    }
}

struct ReadingRow: View {
    var reading: MeterReading
    var effective: Decimal
    var corrections: [AuditCorrection]
    var needsDecision: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(Format.kwhWithUnit(effective))
                    .font(.body.monospacedDigit().weight(.medium))
                Spacer()
                Text(Format.dateTime(reading.readingTimestamp))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let latest = corrections.max(by: { $0.correctedAt < $1.correctedAt }) {
                Text("Corrected from \(Format.kwhWithUnit(reading.originalKwhValue)) on \(Format.date(latest.correctedAt))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if needsDecision {
                Label("Needs a decision", systemImage: "exclamationmark.arrow.circlepath")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.labelColor(.trending))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ReadingDetailView: View {
    var readingId: UUID
    @Environment(AppModel.self) private var model
    @Environment(EnergyStore.self) private var store

    var body: some View {
        let data = store.data
        if let reading = data.readings.first(where: { $0.id == readingId }) {
            let corrections = (data.correctionsByEntity[reading.id] ?? []).filter { $0.entityType == AuditEntityType.meterReading }.sorted { $0.correctedAt > $1.correctedAt }
            let prompt = data.prompts.first { $0.meterReadingId == reading.id }
            List {
                Section {
                    LabeledContent("Value", value: Format.kwhWithUnit(data.effectiveValues[reading.id] ?? reading.originalKwhValue))
                    LabeledContent("Read at", value: Format.dateTime(reading.readingTimestamp))
                    if !corrections.isEmpty {
                        LabeledContent("Original value", value: Format.kwhWithUnit(reading.originalKwhValue))
                    }
                    Button("Correct value") { model.present(.correctReading(reading.id)) }
                        .accessibilityIdentifier("correctButton")
                }
                if let prompt {
                    Section("Lower than the reading before") {
                        if prompt.isResolved, let c = prompt.classification {
                            LabeledContent("Classified as", value: c == .reset ? String(localized: "Meter replaced or reset") : String(localized: "Meter rolled over"))
                            if c == .rollover, let cap = prompt.digitCapacityKwh ?? data.meter?.digitCapacityKwh {
                                LabeledContent("Digit capacity", value: Format.kwhWithUnit(cap))
                            }
                            Button("Change classification") { model.present(.regression(prompt.id)) }
                        } else {
                            Label("Needs a decision", systemImage: "exclamationmark.arrow.circlepath")
                                .foregroundStyle(Theme.labelColor(.trending))
                            Button("Decide now") { model.presentOpenPrompt() }
                        }
                    }
                }
                if !corrections.isEmpty {
                    Section("Corrections") {
                        ForEach(corrections) { c in
                            VStack(alignment: .leading) {
                                Text("\(Format.kwh(DecimalMath.parse(c.oldValue) ?? 0)) → \(Format.kwh(DecimalMath.parse(c.newValue) ?? 0)) kWh")
                                Text(Format.dateTime(c.correctedAt)).font(.footnote).foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                Section {
                    Text("Readings cannot be deleted. Correct the value instead.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Reading")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Reading not found", systemImage: "questionmark")
        }
    }
}

// MARK: - Events (FR-17)

struct EventsList: View {
    var search: String
    @Environment(AppModel.self) private var model
    @Environment(EnergyStore.self) private var store

    var body: some View {
        let data = store.data
        let events = data.events
            .sorted { $0.occurredAt > $1.occurredAt }
            .filter { search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) || ($0.taggedEntityName ?? "").localizedCaseInsensitiveContains(search) }
        List {
            if events.isEmpty {
                Text(search.isEmpty ? String(localized: "No events yet. Log one when something unusual happens, like being away or a guest staying over.") : String(localized: "No matching events."))
                    .foregroundStyle(.secondary)
            }
            ForEach(events) { event in
                Button {
                    model.present(.editEvent(event.id))
                } label: {
                    EventRow(event: event, deviation: data.deviation(for: event))
                }
                .foregroundStyle(.primary)
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("eventsList")
    }
}
