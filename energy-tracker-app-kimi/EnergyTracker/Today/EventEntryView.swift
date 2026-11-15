import SwiftUI

struct EventEntryView: View {
    let repository: DataRepository
    var event: EnergyEvent?
    var onSaved: (() -> Void)?
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var occurredAt = Date()
    @State private var selectedTag = "none"
    @State private var validationError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "What happened?"), text: $description, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("event-description")
                    DatePicker(String(localized: "Happened at"), selection: $occurredAt)
                    Picker(String(localized: "Tag"), selection: $selectedTag) {
                        Text(String(localized: "None")).tag("none")
                        if let tags = try? repository.availableTags() {
                            ForEach(tags, id: \.self) { tag in
                                Text(tagName(tag)).tag(tagKey(tag))
                            }
                        }
                    }
                    if description.count > 450 {
                        Text(String(format: String(localized: "%lld of 500 characters"), description.count))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if event == nil, let suggestions = try? repository.recentEventDescriptions(), !suggestions.isEmpty {
                    Section(String(localized: "Recent events")) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(suggestions, id: \.self) { suggestion in
                                    Button(suggestion) { description = suggestion }.buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
                if let validationError { Section { Text(validationError).foregroundStyle(.red) } }
            }
            .navigationTitle(event == nil ? String(localized: "Log event") : String(localized: "Edit event"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { close() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save"), action: save).accessibilityIdentifier("save-event")
                }
            }
            .onAppear {
                guard let event else { return }
                description = event.eventDescription
                occurredAt = event.occurredAt
                if let type = event.taggedEntityType, let id = event.taggedEntityId { selectedTag = "\(type)-\(id.uuidString)" }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        do {
            let tag = try repository.availableTags().first { tagKey($0) == selectedTag }
            if let event {
                try repository.updateEvent(event, description: description, occurredAt: occurredAt, tag: tag)
            } else {
                _ = try repository.addEvent(description: description, occurredAt: occurredAt, tag: tag)
            }
            router.confirmation = String(localized: "Event saved")
            close()
        } catch { validationError = error.localizedDescription }
    }

    private func close() {
        onSaved?()
        if event == nil { router.sheet = nil } else { dismiss() }
    }

    private func tagKey(_ tag: EventTag) -> String { "\(tag.type)-\(tag.id.uuidString)" }
    private func tagName(_ tag: EventTag) -> String {
        switch tag.type {
        case "Room": String(format: String(localized: "Room · %@"), tag.name)
        case "PowerPoint": String(format: String(localized: "Power Point · %@"), tag.name)
        default: String(format: String(localized: "Device · %@"), tag.name)
        }
    }
}
