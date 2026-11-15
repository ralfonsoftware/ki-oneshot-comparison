import SwiftUI

private enum StructureEdit: Identifiable {
    case addRoom
    case room(Room)
    case addPoint(Room)
    case point(PowerPoint)
    case addDevice(PowerPoint)
    case device(Device)

    var id: String {
        switch self {
        case .addRoom: "add-room"
        case .room(let room): "room-\(room.id)"
        case .addPoint(let room): "add-point-\(room.id)"
        case .point(let point): "point-\(point.id)"
        case .addDevice(let point): "add-device-\(point.id)"
        case .device(let device): "device-\(device.id)"
        }
    }
}

struct StructureView: View {
    let repository: DataRepository
    @EnvironmentObject private var router: AppRouter
    @State private var showArchived = false
    @State private var edit: StructureEdit?

    var body: some View {
        List {
            Section {
                Toggle(String(localized: "Show archived"), isOn: $showArchived)
            } footer: { Text(String(localized: "These labels organize events only. They never attribute consumption.")) }
            if rooms.isEmpty {
                ContentUnavailableView(String(localized: "No rooms"), systemImage: "house", description: Text(String(localized: "Add a room to start building your event labels.")))
            }
            ForEach(rooms, id: \.id) { room in
                DisclosureGroup {
                    Button(String(localized: "Add Power Point"), systemImage: "plus") { edit = .addPoint(room) }.disabled(room.archivedAt != nil)
                    ForEach(points(in: room), id: \.id) { point in
                        DisclosureGroup {
                            Button(String(localized: "Add Device"), systemImage: "plus") { edit = .addDevice(point) }.disabled(point.archivedAt != nil)
                            ForEach(devices(in: point), id: \.id) { device in
                                itemRow(name: device.name, archived: device.archivedAt != nil, symbol: "powerplug") {
                                    edit = .device(device)
                                } archive: {
                                    perform { try repository.setArchived(device, device.archivedAt == nil) }
                                }
                            }
                        } label: {
                            itemRow(name: point.name, archived: point.archivedAt != nil, symbol: "poweroutlet.type.b") {
                                edit = .point(point)
                            } archive: {
                                perform { try repository.setArchived(point, point.archivedAt == nil) }
                            }
                        }
                    }
                } label: {
                    itemRow(name: room.name, archived: room.archivedAt != nil, symbol: "house") {
                        edit = .room(room)
                    } archive: {
                        perform { try repository.setArchived(room, room.archivedAt == nil) }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "Rooms & Devices"))
        .toolbar { Button(String(localized: "Add room"), systemImage: "plus") { edit = .addRoom } }
        .sheet(item: $edit) { edit in
            StructureEditView(edit: edit, repository: repository)
        }
    }

    private var rooms: [Room] { ((try? repository.rooms()) ?? []).filter { showArchived || $0.archivedAt == nil } }
    private func points(in room: Room) -> [PowerPoint] { ((try? repository.powerPoints()) ?? []).filter { $0.roomId == room.id && (showArchived || $0.archivedAt == nil) } }
    private func devices(in point: PowerPoint) -> [Device] { ((try? repository.devices()) ?? []).filter { $0.powerPointId == point.id && (showArchived || $0.archivedAt == nil) } }

    private func itemRow(name: String, archived: Bool, symbol: String, edit: @escaping () -> Void, archive: @escaping () -> Void) -> some View {
        HStack {
            Label(name, systemImage: symbol).foregroundStyle(archived ? .secondary : .primary)
            if archived { Text(String(localized: "Archived")).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button(String(localized: "Edit"), systemImage: "pencil", action: edit).labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            Button(archived ? String(localized: "Restore") : String(localized: "Archive"), systemImage: archived ? "arrow.uturn.backward" : "archivebox", action: archive)
                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { router.report(error) }
    }
}

private struct StructureEditView: View {
    let edit: StructureEdit
    let repository: DataRepository
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var parentID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField(String(localized: "Name"), text: $name)
                if needsRoomPicker {
                    Picker(String(localized: "Room"), selection: $parentID) {
                        ForEach((try? repository.rooms(includeArchived: false)) ?? [], id: \.id) { room in
                            Text(room.name).tag(Optional(room.id))
                        }
                    }
                }
                if needsPointPicker {
                    Picker(String(localized: "Power Point"), selection: $parentID) {
                        ForEach((try? repository.powerPoints(includeArchived: false)) ?? [], id: \.id) { point in
                            Text(point.name).tag(Optional(point.id))
                        }
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Save"), action: save) }
            }
            .onAppear {
                switch edit {
                case .room(let room): name = room.name
                case .point(let point): name = point.name; parentID = point.roomId
                case .device(let device): name = device.name; parentID = device.powerPointId
                case .addPoint(let room): parentID = room.id
                case .addDevice(let point): parentID = point.id
                case .addRoom: break
                }
                if parentID == nil, needsRoomPicker { parentID = try? repository.rooms(includeArchived: false).first?.id }
                if parentID == nil, needsPointPicker { parentID = try? repository.powerPoints(includeArchived: false).first?.id }
            }
        }
    }

    private var needsRoomPicker: Bool { if case .point = edit { true } else { false } }
    private var needsPointPicker: Bool { if case .device = edit { true } else { false } }
    private var title: String {
        switch edit {
        case .addRoom: String(localized: "Add room")
        case .room: String(localized: "Edit room")
        case .addPoint: String(localized: "Add Power Point")
        case .point: String(localized: "Edit Power Point")
        case .addDevice: String(localized: "Add Device")
        case .device: String(localized: "Edit Device")
        }
    }

    private func save() {
        do {
            switch edit {
            case .addRoom: _ = try repository.addRoom(name: name)
            case .room(let room): try repository.rename(room, to: name)
            case .addPoint(let room): _ = try repository.addPowerPoint(name: name, room: room)
            case .point(let point):
                try repository.rename(point, to: name)
                if let parentID, let room = try repository.rooms(includeArchived: false).first(where: { $0.id == parentID }) { try repository.move(point, to: room) }
            case .addDevice(let point): _ = try repository.addDevice(name: name, powerPoint: point)
            case .device(let device):
                try repository.rename(device, to: name)
                if let parentID, let point = try repository.powerPoints(includeArchived: false).first(where: { $0.id == parentID }) { try repository.move(device, to: point) }
            }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
