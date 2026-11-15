import WidgetKit
import SwiftUI
import SwiftData

struct EnergyStatusEntry: TimelineEntry, Sendable {
    let date: Date
    let status: LiveStatus
}

struct EnergyStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> EnergyStatusEntry { EnergyStatusEntry(date: Date(), status: sampleStatus) }

    func getSnapshot(in context: Context, completion: @Sendable @escaping (EnergyStatusEntry) -> Void) {
        Task { @MainActor in completion(makeEntry()) }
    }

    func getTimeline(in context: Context, completion: @Sendable @escaping (Timeline<EnergyStatusEntry>) -> Void) {
        Task { @MainActor in
            let entry = makeEntry()
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date().addingTimeInterval(86_400)
            completion(Timeline(entries: [entry], policy: .after(tomorrow)))
        }
    }

    @MainActor
    private func makeEntry() -> EnergyStatusEntry {
        let repository = DataRepository(context: PersistenceController.shared.container.mainContext)
        try? repository.mergeDuplicates()
        let status = (try? EnergyEngine.status(repository: repository)) ?? LiveStatus(status: nil, undefinedReason: .needsReadings)
        return EnergyStatusEntry(date: Date(), status: status)
    }

    private var sampleStatus: LiveStatus {
        LiveStatus(status: .belowbaseline, paceToDate: 240, baselineToDate: 282, difference: -42, elapsedDays: 30)
    }
}

struct EnergyStatusWidgetView: View {
    let entry: EnergyStatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            Image(systemName: entry.status.status?.symbol ?? "bolt.circle")
                .font(.title)
                .widgetAccentable()
        case .accessoryRectangular:
            HStack {
                Image(systemName: entry.status.status?.symbol ?? "bolt.circle")
                VStack(alignment: .leading) {
                    Text(entry.status.status?.label ?? String(localized: "Log a reading")).font(.headline)
                    Text(daysText).font(.caption)
                }
            }
        case .accessoryInline:
            Label(entry.status.status?.label ?? String(localized: "Log a reading"), systemImage: entry.status.status?.symbol ?? "bolt.circle")
        case .systemMedium:
            HStack(spacing: 16) {
                statusContent
                Link(destination: AppConfiguration.logReadingURL) {
                    Label(String(localized: "Log reading"), systemImage: "plus.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title)
                        .frame(width: 44, height: 44)
                }
            }
            .padding()
        default:
            statusContent.padding()
        }
    }

    private var statusContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                if let status = entry.status.status {
                    Label(status.label, systemImage: status.symbol)
                        .foregroundStyle(status.color)
                        .font(.headline)
                } else {
                    Label(String(localized: "Log a reading"), systemImage: "bolt.circle").font(.headline)
                }
                if entry.status.isLowConfidence { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(DisplayStatus.trending.color) }
            }
            Text(entry.status.shortSentence).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Text(daysText).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }

    private var daysText: String {
        guard let days = entry.status.daysSinceLastReading else { return String(localized: "No readings yet") }
        return days == 0 ? String(localized: "Read today") : String(format: String(localized: "Last reading %lld days ago"), days)
    }
}

struct EnergyStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EnergyStatusWidget", provider: EnergyStatusProvider()) { entry in
            EnergyStatusWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Energy Status"))
        .description(String(localized: "Your current pace and the age of your last reading."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct EnergyTrackerWidgetBundle: WidgetBundle {
    var body: some Widget { EnergyStatusWidget() }
}
