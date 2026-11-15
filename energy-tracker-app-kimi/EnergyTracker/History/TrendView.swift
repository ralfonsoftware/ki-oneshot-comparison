import SwiftUI
import Charts
import Accessibility

private enum TrendRange: String, CaseIterable, Identifiable {
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
    var days: Double? {
        switch self {
        case .month: 30
        case .quarter: 90
        case .year: 365
        case .all: nil
        }
    }
}

fileprivate struct TrendPoint: Identifiable {
    let id: UUID
    let date: Date
    let difference: Double
    let status: DisplayStatus
}

fileprivate struct TrendSegment: Identifiable {
    let id = UUID()
    var points: [TrendPoint]
}

private struct TrendGap: Identifiable {
    let id = UUID()
    let start: Date
    let end: Date
}

struct TrendView: View {
    let repository: DataRepository
    @State private var range = TrendRange.quarter

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(String(localized: "Trend History")).font(.title2.bold())
                Spacer()
                Picker(String(localized: "Range"), selection: $range) {
                    ForEach(TrendRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            }
            if points.isEmpty {
                ContentUnavailableView(String(localized: "No status history yet"), systemImage: "chart.xyaxis.line", description: Text(String(localized: "Snapshots appear after you log or correct readings.")))
                    .frame(minHeight: 220)
            } else {
                Chart {
                    ForEach(segments) { segment in
                        ForEach(segment.points) { point in
                            LineMark(x: .value(String(localized: "Date"), point.date), y: .value(String(localized: "kWh"), point.difference), series: .value(String(localized: "Segment"), segment.id.uuidString))
                                .foregroundStyle(point.status.color)
                            PointMark(x: .value(String(localized: "Date"), point.date), y: .value(String(localized: "kWh"), point.difference))
                                .foregroundStyle(point.status.color)
                                .symbolSize(45)
                        }
                    }
                    ForEach(gaps) { gap in
                        RectangleMark(xStart: .value(String(localized: "Gap start"), gap.start), xEnd: .value("Gap end", gap.end))
                            .foregroundStyle(DisplayStatus.trending.color.opacity(0.10))
                            .annotation(position: .top, alignment: .center) {
                                Text(gapLabel(gap)).font(.caption2).foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(minHeight: 250)
                .chartYAxisLabel(String(localized: "kWh above or below baseline"))
                .accessibilityChartDescriptor(TrendAudioGraph(segments: segments))
                ForEach(gaps) { gap in
                    Label(gapLabel(gap), systemImage: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var points: [TrendPoint] {
        guard let snapshots = try? repository.snapshots() else { return [] }
        let cutoff = range.days.map { Date().addingTimeInterval(-$0 * 86_400) }
        return snapshots.filter { cutoff == nil || $0.computedAt >= cutoff! }.compactMap { snapshot in
            guard let status = DisplayStatus(rawValue: snapshot.status.lowercased()),
                  let pace = DecimalText.decode(snapshot.paceToDateKwh),
                  let baseline = DecimalText.decode(snapshot.baselineToDateKwh) else { return nil }
            return TrendPoint(id: snapshot.id, date: snapshot.computedAt, difference: NSDecimalNumber(decimal: pace - baseline).doubleValue, status: status)
        }
    }

    private var segments: [TrendSegment] {
        var result: [TrendSegment] = []
        for point in points {
            if result.isEmpty || isGap(before: point) { result.append(TrendSegment(points: [])) }
            result[result.count - 1].points.append(point)
        }
        return result
    }

    private var gaps: [TrendGap] {
        guard points.count > 1 else { return [] }
        return zip(points, points.dropFirst()).compactMap { previous, current in
            isGap(before: current) ? TrendGap(start: previous.date, end: current.date) : nil
        }
    }

    private func isGap(before point: TrendPoint) -> Bool {
        guard let index = points.firstIndex(where: { $0.id == point.id }), index > 0 else { return false }
        let gap = (try? repository.activeHouseholdRecord()?.lowConfidenceGapDays) ?? 45
        return point.date.timeIntervalSince(points[index - 1].date) > Double(gap) * 86_400
    }

    private func gapLabel(_ gap: TrendGap) -> String {
        String(format: String(localized: "No reading between %@ and %@"), gap.start.formatted(date: .abbreviated, time: .omitted), gap.end.formatted(date: .abbreviated, time: .omitted))
    }

}

fileprivate struct TrendAudioGraph: AXChartDescriptorRepresentable {
    let segments: [TrendSegment]
    private var points: [TrendPoint] { segments.flatMap(\.points) }

    func makeChartDescriptor() -> AXChartDescriptor {
        let dates = points.map(\.date)
        let values = points.map(\.difference)
        let xAxis = AXNumericDataAxisDescriptor(title: String(localized: "Date"), range: (dates.first?.timeIntervalSince1970 ?? 0)...(dates.last?.timeIntervalSince1970 ?? 1), gridlinePositions: []) {
            Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .omitted)
        }
        let lower = min(values.min() ?? 0, 0), upper = max(values.max() ?? 1, 1)
        let yAxis = AXNumericDataAxisDescriptor(title: String(localized: "Difference from baseline in kWh"), range: lower...upper, gridlinePositions: []) {
            String(format: String(localized: "%.1f kWh"), $0)
        }
        let series = segments.map { segment in
            AXDataSeriesDescriptor(name: String(localized: "Status difference"), isContinuous: true, dataPoints: segment.points.map {
                AXDataPoint(x: $0.date.timeIntervalSince1970, y: $0.difference, label: $0.status.label)
            })
        }
        return AXChartDescriptor(title: String(localized: "Energy status trend"), summary: String(localized: "Pace minus baseline over time. Breaks indicate periods without readings."), xAxis: xAxis, yAxis: yAxis, series: series)
    }
}
