import SwiftUI
import EnergyCore

// MARK: - Log or edit an event (FR-15)

struct EventEditorSheet: View {
    var eventId: UUID?
    @Environment(AppModel.self) private var model
    @Environment(EnergyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var date = Date()
    @State private var tag: EnergyStore.EventTag?
    @State private var existingTagName: String?
    @State private var tagChanged = false
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var loaded = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What happened?", text: $text, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($focused)
                        .accessibilityIdentifier("eventText")
                    if eventId == nil, !store.recentEventDescriptions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(store.recentEventDescriptions, id: \.self) { suggestion in
                                    Button(suggestion) { text = suggestion }
                                        .buttonStyle(.bordered)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .accessibilityLabel(Text("Recent events"))
                    }
                } footer: {
                    if let error { Text(error).foregroundStyle(Theme.error) }
                }
                Section {
                    DatePicker("When", selection: $date)
                    NavigationLink {
                        TagPicker(selection: Binding(get: { tag }, set: { tag = $0; tagChanged = true; existingTagName = nil }))
                    } label: {
                        LabeledContent("Tag", value: tag?.name ?? existingTagName ?? String(localized: "None"))
                    }
                }
                if eventId != nil {
                    Section {
                        Button("Delete event", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(eventId == nil ? String(localized: "Log event") : String(localized: "Edit event"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("saveEvent")
                }
            }
            .confirmationDialog("Delete this event?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    do {
                        try store.deleteEvent(id: eventId!)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.medium, .large])
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let eventId, let event = store.data.events.first(where: { $0.id == eventId }) {
            text = event.text
            date = event.occurredAt
            existingTagName = event.taggedEntityName
            if let type = event.taggedEntityType, let id = event.taggedEntityId {
                tag = EnergyStore.EventTag(type: type, id: id, name: event.taggedEntityName ?? "")
            }
        } else {
            focused = true
        }
    }

    private func save() {
        do {
            if let eventId {
                try store.updateEvent(id: eventId, text: text, occurredAt: date, tag: tag, tagChanged: tagChanged)
            } else {
                try store.addEvent(text: text, occurredAt: date, tag: tag)
            }
            model.showToast(String(localized: "Event saved"), symbol: "checkmark")
            dismiss()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Room → Power Point → Device. Archived items are hidden (FR-18).
struct TagPicker: View {
    @Binding var selection: EnergyStore.EventTag?
    @Environment(EnergyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let data = store.data
        List {
            Section {
                row(nil, title: String(localized: "None"), symbol: "tag.slash", indent: 0)
            }
            ForEach(data.rooms.filter { $0.archivedAt == nil }.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })) { room in
                Section {
                    row(.init(type: .room, id: room.id, name: room.name), title: room.name, symbol: "square.split.bottomrightquarter", indent: 0)
                    ForEach(data.powerPoints.filter { $0.roomId == room.id && $0.archivedAt == nil }.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })) { point in
                        row(.init(type: .powerPoint, id: point.id, name: point.name), title: point.name, symbol: "poweroutlet.type.f", indent: 1)
                        ForEach(data.devices.filter { $0.powerPointId == point.id && $0.archivedAt == nil }.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })) { device in
                            row(.init(type: .device, id: device.id, name: device.name), title: device.name, symbol: "powerplug", indent: 2)
                        }
                    }
                }
            }
            if data.rooms.isEmpty {
                Text("Add rooms, power points and devices in Settings → Rooms & Devices.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Tag")
    }

    private func row(_ tag: EnergyStore.EventTag?, title: String, symbol: String, indent: Int) -> some View {
        Button {
            selection = tag
            dismiss()
        } label: {
            HStack {
                Label(title, systemImage: symbol)
                    .padding(.leading, CGFloat(indent) * 20)
                Spacer()
                if selection?.id == tag?.id {
                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - Observed deviation (FR-16)

extension Deviation {
    /// Wording never claims cause. `none` shows no line at all.
    var sentence: String? {
        switch self {
        case .bump: String(localized: "Usage was above baseline pace in the two weeks around this event.")
        case .dip: String(localized: "Usage was below baseline pace in the two weeks around this event.")
        case .none: nil
        }
    }

    var symbol: String {
        switch self {
        case .bump: "arrow.up.right"
        case .dip: "arrow.down.right"
        case .none: ""
        }
    }
}

extension LoadedDataSet {
    func deviation(for event: EnergyEvent) -> Deviation {
        DeviationCalculator.compute(occurredAt: event.occurredAt, readings: readingInputs, prompts: promptInputs,
                                    meterDigitCapacityKwh: meter?.digitCapacityKwh, yearlyBaselineKwh: household?.yearlyBaselineKwh,
                                    trendingThresholdKwh: household?.trendingThresholdKwh ?? 100)
    }
}

struct EventRow: View {
    var event: EnergyEvent
    var deviation: Deviation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.text)
                .font(.body)
            HStack(spacing: 6) {
                Text(Format.dateTime(event.occurredAt))
                if let tag = event.taggedEntityName {
                    Text("·")
                    Label(tag, systemImage: "tag").labelStyle(.titleAndIcon)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            if let sentence = deviation.sentence {
                Label(sentence, systemImage: deviation.symbol)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
