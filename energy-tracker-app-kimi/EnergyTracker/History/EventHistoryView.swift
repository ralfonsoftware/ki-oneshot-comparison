import SwiftUI

struct EventHistoryView: View {
    let repository: DataRepository
    let search: String
    let embedded: Bool
    @EnvironmentObject private var router: AppRouter
    @State private var editing: EnergyEvent?
    @State private var deleting: EnergyEvent?

    var body: some View {
        List {
            Section(String(localized: "Events")) {
                if events.isEmpty { Text(String(localized: "No events found.")).foregroundStyle(.secondary) }
                ForEach(events, id: \.id) { event in
                    Button { editing = event } label: { row(event) }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(String(localized: "Delete"), role: .destructive) { deleting = event }
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(embedded ? .hidden : .automatic)
        .frame(minHeight: embedded ? 300 : nil)
        .sheet(item: $editing) { event in
            EventEntryView(repository: repository, event: event)
                .environmentObject(router)
        }
        .confirmationDialog(String(localized: "Delete this event?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(String(localized: "Delete event"), role: .destructive) {
                if let deleting { try? repository.deleteEvent(deleting) }
                deleting = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) { deleting = nil }
        }
    }

    private var events: [EnergyEvent] {
        let all = (try? repository.events()) ?? []
        guard !search.isEmpty else { return all }
        return all.filter { $0.eventDescription.localizedCaseInsensitiveContains(search) || ($0.taggedEntityName ?? "").localizedCaseInsensitiveContains(search) }
    }

    private func row(_ event: EnergyEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(event.eventDescription).font(.headline).foregroundStyle(.primary)
            Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
            if let tag = event.taggedEntityName { Label(tag, systemImage: "tag").font(.caption).foregroundStyle(.secondary) }
            if let deviation = try? EnergyEngine.deviation(repository: repository, event: event) {
                Text(deviation.sentence).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

extension EnergyEvent: Identifiable {}
