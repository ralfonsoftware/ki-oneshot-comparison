import WidgetKit
import SwiftUI
import SwiftData
import AppIntents
import EnergyCore

// FR-22. Widgets compute the Status with the same calculation package from the shared store.

struct StatusEntry: TimelineEntry {
    var date: Date
    var outcome: StatusOutcome
    var daysSinceLastReading: Int?

    static let placeholder = StatusEntry(date: Date(), outcome: .undefined(.notEnoughReadings), daysSinceLastReading: nil)
}

@MainActor
enum WidgetData {
    static let container = Persistence.makeContainer(role: .widget)

    static func entry(at date: Date = Date()) -> StatusEntry {
        let context = ModelContext(container)
        let data = DataSetLoader.load(context, includeHistory: false)
        let days = data.latestReading.map { Format.daysFloor(Pace.daysSince($0.readingTimestamp, now: date)) }
        return StatusEntry(date: date, outcome: data.status(now: date), daysSinceLastReading: days)
    }
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        Task { @MainActor in completion(WidgetData.entry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        Task { @MainActor in
            // One entry now, then one per local midnight for a week so "days since last reading" stays true.
            let now = Date()
            var entries = [WidgetData.entry(at: now)]
            var day = Calendar.current.startOfDay(for: now)
            for _ in 0..<7 {
                day = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
                entries.append(WidgetData.entry(at: day.addingTimeInterval(60)))
            }
            completion(Timeline(entries: entries, policy: .after(Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400))))
        }
    }
}

// MARK: - Home Screen widget

struct StatusWidgetView: View {
    var entry: StatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: home
        }
    }

    @ViewBuilder
    private var home: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch entry.outcome {
            case .defined(let r):
                HStack(spacing: 6) {
                    Image(systemName: r.status.symbol)
                        .foregroundStyle(Theme.color(r.status))
                    Text(r.status.label)
                        .font(.headline)
                        .foregroundStyle(Theme.labelColor(r.status))
                        .minimumScaleFactor(0.8)
                    if r.isLowConfidence {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(Theme.uncertain)
                            .accessibilityLabel(Text("Less certain"))
                    }
                }
                Text(StatusCopy.sentence(r))
                    .font(.subheadline)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
            case .undefined:
                Label("Log a reading", systemImage: "gauge.with.dots.needle.0percent")
                    .font(.headline)
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                if let days = entry.daysSinceLastReading {
                    Text(StatusCopy.daysSinceLastReading(days))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if family == .systemMedium {
                    Link(destination: DeepLink.logReading.url) {
                        Label("Log reading", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.accent.opacity(0.18), in: Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(DeepLink.today.url)
    }

    @ViewBuilder
    private var circular: some View {
        if let r = entry.outcome.result {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: r.status.symbol).font(.title2)
            }
            .accessibilityLabel(Text(r.status.label))
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "gauge.with.dots.needle.0percent").font(.title2)
            }
            .accessibilityLabel(Text("Log a reading"))
        }
    }

    @ViewBuilder
    private var rectangular: some View {
        if let r = entry.outcome.result {
            VStack(alignment: .leading) {
                Label(r.status.label, systemImage: r.status.symbol).font(.headline)
                Text(StatusCopy.sentence(r)).font(.caption).lineLimit(2)
            }
        } else {
            Label("Log a reading", systemImage: "gauge.with.dots.needle.0percent")
        }
    }

    @ViewBuilder
    private var inline: some View {
        if let r = entry.outcome.result {
            Label(r.status.label, systemImage: r.status.symbol)
        } else {
            Label("Log a reading", systemImage: "gauge.with.dots.needle.0percent")
        }
    }
}

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EnergyStatus", provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    if let r = entry.outcome.result {
                        Theme.color(r.status).opacity(Theme.tintOpacity)
                    } else {
                        Color.clear
                    }
                }
        }
        .configurationDisplayName("Energy Status")
        .description("Whether this year's electricity use is on track.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Control Center (FR-23)

struct LogReadingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "de.ralfonsoftware.EnergyTracker.LogReadingControl") {
            ControlWidgetButton(action: OpenLogReadingIntent()) {
                Label("Log Reading", systemImage: "bolt.badge.clock")
            }
        }
        .displayName("Log Meter Reading")
        .description("Opens Energy Tracker ready to log a reading.")
    }
}

@main
struct EnergyWidgetBundle: WidgetBundle {
    var body: some Widget {
        StatusWidget()
        LogReadingControl()
    }
}
