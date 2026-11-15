import SwiftUI
import SwiftData

private enum HistorySegment: String, CaseIterable, Identifiable {
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

struct HistoryView: View {
    let repository: DataRepository
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var segment = HistorySegment.trend
    @State private var search = ""
    @State private var searchPresented = false
    @Query private var observedReadings: [MeterReading]
    @Query private var observedEvents: [EnergyEvent]
    @Query private var observedSnapshots: [StatusSnapshot]

    var body: some View {
        NavigationStack {
            Group {
                if sizeClass == .regular {
                    ScrollView {
                        VStack(spacing: 20) {
                            TrendView(repository: repository)
                            HStack(alignment: .top, spacing: 16) {
                                ReadingHistoryView(repository: repository, search: search, embedded: true)
                                EventHistoryView(repository: repository, search: search, embedded: true)
                            }
                        }
                        .padding()
                    }
                } else {
                    VStack {
                        Picker(String(localized: "History"), selection: $segment) {
                            ForEach(HistorySegment.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding([.horizontal, .top])
                        switch segment {
                        case .trend: ScrollView { TrendView(repository: repository).padding() }
                        case .readings: ReadingHistoryView(repository: repository, search: search, embedded: false)
                        case .events: EventHistoryView(repository: repository, search: search, embedded: false)
                        }
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(String(localized: "History"))
            .searchable(text: $search, isPresented: $searchPresented, prompt: String(localized: "Search readings and events"))
            .background {
                Button(String(localized: "Search")) { searchPresented = true }.keyboardShortcut("f", modifiers: .command)
                    .accessibilityHidden(true)
            }
            .onAppear { _ = observedReadings.count + observedEvents.count + observedSnapshots.count }
        }
    }
}
