import SwiftUI
import EnergyCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(EnergyStore.self) private var store
    @AppStorage("appearance") private var appearance: Appearance = .system

    var body: some View {
        Form {
            PatternSettingsSection()

            Section("Money") {
                CurrencyPicker()
            }

            Section {
                NavigationLink {
                    StructureView()
                } label: {
                    Label("Rooms & Devices", systemImage: "square.split.bottomrightquarter")
                }
            } footer: {
                Text("Used only to tag events. Consumption is never split by room or device.")
            }

            TariffReminderSection()

            Section("iCloud") {
                switch model.sync.cloudState {
                case .checking:
                    Label("Checking iCloud…", systemImage: "icloud")
                case .available:
                    Label("Synced with iCloud", systemImage: "checkmark.icloud")
                case .unavailable:
                    Label(model.sync.settingsLine ?? "", systemImage: "icloud.slash")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Data") {
                ExportButton()
                NavigationLink {
                    ImportView(isOnboarding: false)
                } label: {
                    Label("Import from export file", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("importLink")
            }

            Section("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–")
                Text("Privacy: your data stays on your Apple devices and in your private iCloud database. Energy Tracker has no server, no account, no analytics and no tracking.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let support = Bundle.main.object(forInfoDictionaryKey: "ETSupportURL") as? String, let url = URL(string: support), !support.isEmpty {
                    Link("Support", destination: url)
                }
                if let privacy = Bundle.main.object(forInfoDictionaryKey: "ETPrivacyPolicyURL") as? String, let url = URL(string: privacy), !privacy.isEmpty {
                    Link("Privacy policy", destination: url)
                }
            }
        }
        .navigationTitle(AppSection.settings.title)
    }
}

/// FR-5: Yearly Baseline, trending threshold, low-confidence gap.
struct PatternSettingsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(EnergyStore.self) private var store
    @State private var baseline = ""
    @State private var threshold = ""
    @State private var gapDays = 45
    @State private var cadence = 3
    @State private var loadedVersion = -1
    @FocusState private var focus: Field?

    enum Field { case baseline, threshold }

    var body: some View {
        Section {
            UnitField(title: "Yearly target", text: $baseline, unit: String(localized: "kWh/year"), identifier: "baselineField")
                .focused($focus, equals: .baseline)
                .onSubmit(commitBaseline)
            UnitField(title: "Trending threshold", text: $threshold, unit: String(localized: "kWh/year"), identifier: "thresholdField")
                .focused($focus, equals: .threshold)
                .onSubmit(commitThreshold)
            Stepper(value: $gapDays, in: Validation.gapDaysRange) {
                LabeledContent("Less certain after", value: String(localized: "\(gapDays) days"))
            }
            .onChange(of: gapDays) { _, v in perform { try store.setLowConfidenceGapDays(v) } }
            Stepper(value: $cadence, in: Validation.cadenceRange) {
                LabeledContent("Tariff check every", value: String(localized: "\(cadence) months"))
            }
            .onChange(of: cadence) { _, v in perform { try store.setTariffCheckCadence(v) } }
        } header: {
            Text("Your pattern")
        } footer: {
            Text("Changes apply from now on. Stored history is never recalculated. Leave the yearly target empty to hide the status.")
        }
        .onChange(of: focus) { old, _ in
            if old == .baseline { commitBaseline() }
            if old == .threshold { commitThreshold() }
        }
        .onAppear(perform: load)
        .onDisappear {
            commitBaseline()
            commitThreshold()
        }
    }

    private func load() {
        guard loadedVersion != store.version, let h = store.data.household else { return }
        loadedVersion = store.version
        baseline = h.yearlyBaselineKwh.map { Format.editable($0) } ?? ""
        threshold = Format.editable(h.trendingThresholdKwh)
        gapDays = h.lowConfidenceGapDays
        cadence = h.tariffCheckCadenceMonths
    }

    private func commitBaseline() {
        let trimmed = baseline.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            perform { try store.setYearlyBaseline(nil) }
        } else if let v = Format.parseDecimal(trimmed), v > 0 {
            perform { try store.setYearlyBaseline(v) }
        } else {
            model.showToast(String(localized: "Enter the yearly target as a number greater than 0."), symbol: "exclamationmark.triangle", isError: true)
        }
    }

    private func commitThreshold() {
        if let v = Format.parseDecimal(threshold), v >= 0 {
            perform { try store.setTrendingThreshold(v) }
        } else {
            model.showToast(String(localized: "Enter the threshold as a number of 0 or more."), symbol: "exclamationmark.triangle", isError: true)
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { model.showError(error) }
    }
}

struct CurrencyPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(EnergyStore.self) private var store

    static let common = ["EUR", "CHF", "GBP", "USD", "DKK", "SEK", "NOK", "PLN", "CZK", "HUF", "CAD", "AUD", "JPY"]

    var body: some View {
        let current = store.data.currency
        Picker("Currency", selection: Binding(get: { current }, set: { value in
            do { try store.setCurrency(value) } catch { model.showError(error) }
        })) {
            ForEach(Self.common.contains(current) ? Self.common : [current] + Self.common, id: \.self) { code in
                Text("\(code) – \(Locale.current.localizedString(forCurrencyCode: code) ?? code)").tag(code)
            }
        }
    }
}

/// FR-21: per Apple device, default off, permission asked only when turned on.
struct TariffReminderSection: View {
    @Environment(EnergyStore.self) private var store
    @State private var enabled = NotificationScheduler.tariffRemindersEnabled
    @State private var denied = false

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { enabled }, set: { newValue in
                if newValue {
                    Task {
                        let granted = await NotificationScheduler.enableTariffReminders()
                        enabled = granted
                        denied = !granted
                        NotificationScheduler.reschedule(data: store.data)
                    }
                } else {
                    enabled = false
                    NotificationScheduler.tariffRemindersEnabled = false
                    NotificationScheduler.reschedule(data: store.data)
                }
            })) {
                Text(UIDevice.current.userInterfaceIdiom == .pad ? String(localized: "Tariff reminders on this iPad") : String(localized: "Tariff reminders on this iPhone"))
            }
        } header: {
            Text("Reminders")
        } footer: {
            if denied {
                Text("Notifications are turned off for Energy Tracker in the Settings app.")
            } else {
                Text("This setting is per device, so you can get the reminder on one device only instead of on all of them. You get one reminder at 10:00 on the day the tariff check is due.")
            }
        }
    }
}

// MARK: - Rooms, Power Points, Devices (FR-18)

struct StructureView: View {
    @Environment(AppModel.self) private var model
    @Environment(EnergyStore.self) private var store
    @State private var showArchived = false
    @State private var editing: StructureEdit?

    struct StructureEdit: Identifiable {
        enum Mode { case addRoom, addPowerPoint(roomId: UUID), addDevice(powerPointId: UUID), rename(EnergyStore.StructureKind, UUID, String) }
        let id = UUID()
        var mode: Mode
    }

    var body: some View {
        let data = store.data
        let rooms = data.rooms.filter { showArchived || $0.archivedAt == nil }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        List {
            Section {
                Toggle("Show archived", isOn: $showArchived)
            }
            ForEach(rooms) { room in
                Section {
                    itemRow(.room, id: room.id, name: room.name, archived: room.archivedAt != nil, symbol: "square.split.bottomrightquarter", indent: 0, addChild: room.archivedAt == nil ? .addPowerPoint(roomId: room.id) : nil, moveTargets: [])
                    let points = data.powerPoints.filter { $0.roomId == room.id && (showArchived || $0.archivedAt == nil) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    ForEach(points) { point in
                        itemRow(.powerPoint, id: point.id, name: point.name, archived: point.archivedAt != nil, symbol: "poweroutlet.type.f", indent: 1,
                                addChild: point.archivedAt == nil ? .addDevice(powerPointId: point.id) : nil,
                                moveTargets: data.rooms.filter { $0.archivedAt == nil && $0.id != room.id }.map { ($0.id, $0.name) })
                        let devices = data.devices.filter { $0.powerPointId == point.id && (showArchived || $0.archivedAt == nil) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                        ForEach(devices) { device in
                            itemRow(.device, id: device.id, name: device.name, archived: device.archivedAt != nil, symbol: "powerplug", indent: 2, addChild: nil,
                                    moveTargets: data.powerPoints.filter { $0.archivedAt == nil && $0.id != point.id }.map { ($0.id, "\(roomName($0.roomId)) › \($0.name)") })
                        }
                    }
                }
            }
            if rooms.isEmpty {
                Text("No rooms yet. Rooms, power points and devices are labels for events.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Rooms & Devices")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = StructureEdit(mode: .addRoom)
                } label: {
                    Label("Add room", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editing) { edit in
            NameEditor(edit: edit)
        }
    }

    private func roomName(_ id: UUID?) -> String {
        store.data.rooms.first { $0.id == id }?.name ?? ""
    }

    private func itemRow(_ kind: EnergyStore.StructureKind, id: UUID, name: String, archived: Bool, symbol: String, indent: Int, addChild: StructureEdit.Mode?, moveTargets: [(UUID, String)]) -> some View {
        HStack {
            Label(name, systemImage: symbol)
                .padding(.leading, CGFloat(indent) * 20)
                .foregroundStyle(archived ? .secondary : .primary)
            if archived {
                Text("Archived").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                if let addChild {
                    Button {
                        editing = StructureEdit(mode: addChild)
                    } label: {
                        Label(kind == .room ? String(localized: "Add power point") : String(localized: "Add device"), systemImage: "plus")
                    }
                }
                Button {
                    editing = StructureEdit(mode: .rename(kind, id, name))
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                if !moveTargets.isEmpty, !archived {
                    Menu {
                        ForEach(moveTargets, id: \.0) { target in
                            Button(target.1) {
                                perform {
                                    if kind == .powerPoint { try store.movePowerPoint(id: id, toRoom: target.0) }
                                    if kind == .device { try store.moveDevice(id: id, toPowerPoint: target.0) }
                                }
                            }
                        }
                    } label: {
                        Label("Move to", systemImage: "arrow.right.square")
                    }
                }
                Button {
                    perform { try store.setArchived(kind, id: id, archived: !archived) }
                } label: {
                    Label(archived ? String(localized: "Restore") : String(localized: "Archive"), systemImage: archived ? "arrow.uturn.backward" : "archivebox")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Actions for \(name)"))
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { model.showError(error) }
    }
}

struct NameEditor: View {
    var edit: StructureView.StructureEdit
    @Environment(EnergyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .focused($focused)
                    .onSubmit(save)
                if let error { Text(error).foregroundStyle(Theme.error) }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear {
                if case .rename(_, _, let current) = edit.mode { name = current }
                focused = true
            }
        }
        .presentationDetents([.height(220)])
    }

    private var title: String {
        switch edit.mode {
        case .addRoom: String(localized: "New room")
        case .addPowerPoint: String(localized: "New power point")
        case .addDevice: String(localized: "New device")
        case .rename: String(localized: "Rename")
        }
    }

    private func save() {
        do {
            switch edit.mode {
            case .addRoom: try store.addRoom(name: name)
            case .addPowerPoint(let roomId): try store.addPowerPoint(roomId: roomId, name: name)
            case .addDevice(let pointId): try store.addDevice(powerPointId: pointId, name: name)
            case .rename(let kind, let id, _): try store.rename(kind, id: id, to: name)
            }
            dismiss()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
