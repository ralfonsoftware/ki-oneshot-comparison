import Foundation

struct EventTag: Hashable {
    let type: String
    let id: UUID
    let name: String
}

extension DataRepository {
    // MARK: - Events

    func events() throws -> [EnergyEvent] {
        guard let generation = try currentGeneration() else { return [] }
        return try fetch(EnergyEvent.self)
            .filter { $0.generation == generation }
            .sorted {
                if $0.occurredAt != $1.occurredAt { return $0.occurredAt > $1.occurredAt }
                return $0.id.uuidString > $1.id.uuidString
            }
    }

    @discardableResult
    func addEvent(description: String, occurredAt: Date = Date(), tag: EventTag? = nil) throws -> EnergyEvent {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...500).contains(text.count) else { throw RepositoryError.invalidEvent }
        let household = try ensureHousehold()
        let event = EnergyEvent(generation: household.generation, description: text, occurredAt: occurredAt, taggedEntityType: tag?.type, taggedEntityId: tag?.id, taggedEntityName: tag?.name)
        context.insert(event)
        try save()
        return event
    }

    func updateEvent(_ event: EnergyEvent, description: String, occurredAt: Date, tag: EventTag?) throws {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...500).contains(text.count) else { throw RepositoryError.invalidEvent }
        event.eventDescription = text
        event.occurredAt = occurredAt
        event.taggedEntityType = tag?.type
        event.taggedEntityId = tag?.id
        event.taggedEntityName = tag?.name
        event.updatedAt = Date()
        try save()
    }

    func deleteEvent(_ event: EnergyEvent) throws {
        context.delete(event)
        try save()
    }

    func recentEventDescriptions(limit: Int = 5) throws -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for event in try events() {
            if seen.insert(event.eventDescription).inserted {
                result.append(event.eventDescription)
                if result.count == limit { break }
            }
        }
        return result
    }

    func availableTags() throws -> [EventTag] {
        let rooms = try rooms(includeArchived: false).map { EventTag(type: "Room", id: $0.id, name: $0.name) }
        let points = try powerPoints(includeArchived: false).map { EventTag(type: "PowerPoint", id: $0.id, name: $0.name) }
        let devices = try devices(includeArchived: false).map { EventTag(type: "Device", id: $0.id, name: $0.name) }
        return rooms + points + devices
    }

    // MARK: - Structure

    func rooms(includeArchived: Bool = true) throws -> [Room] {
        guard let generation = try currentGeneration() else { return [] }
        return try fetch(Room.self)
            .filter { $0.generation == generation && (includeArchived || $0.archivedAt == nil) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func powerPoints(includeArchived: Bool = true) throws -> [PowerPoint] {
        guard let generation = try currentGeneration() else { return [] }
        return try fetch(PowerPoint.self)
            .filter { $0.generation == generation && (includeArchived || $0.archivedAt == nil) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func devices(includeArchived: Bool = true) throws -> [Device] {
        guard let generation = try currentGeneration() else { return [] }
        return try fetch(Device.self)
            .filter { $0.generation == generation && (includeArchived || $0.archivedAt == nil) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    func addRoom(name: String) throws -> Room {
        guard let name = InputValidation.name(name) else { throw RepositoryError.invalidName }
        let household = try ensureHousehold()
        let room = Room(generation: household.generation, name: name)
        context.insert(room); try save(); return room
    }

    @discardableResult
    func addPowerPoint(name: String, room: Room) throws -> PowerPoint {
        guard let name = InputValidation.name(name) else { throw RepositoryError.invalidName }
        guard room.archivedAt == nil else { throw RepositoryError.archivedParent }
        let point = PowerPoint(generation: room.generation, roomId: room.id, name: name)
        context.insert(point); try save(); return point
    }

    @discardableResult
    func addDevice(name: String, powerPoint: PowerPoint) throws -> Device {
        guard let name = InputValidation.name(name) else { throw RepositoryError.invalidName }
        guard powerPoint.archivedAt == nil else { throw RepositoryError.archivedParent }
        let device = Device(generation: powerPoint.generation, powerPointId: powerPoint.id, name: name)
        context.insert(device); try save(); return device
    }

    func rename(_ room: Room, to name: String) throws {
        guard let name = InputValidation.name(name) else { throw RepositoryError.invalidName }
        room.name = name; room.updatedAt = Date(); try save()
    }

    func rename(_ point: PowerPoint, to name: String) throws {
        guard let name = InputValidation.name(name) else { throw RepositoryError.invalidName }
        point.name = name; point.updatedAt = Date(); try save()
    }

    func rename(_ device: Device, to name: String) throws {
        guard let name = InputValidation.name(name) else { throw RepositoryError.invalidName }
        device.name = name; device.updatedAt = Date(); try save()
    }

    func move(_ point: PowerPoint, to room: Room) throws {
        guard room.archivedAt == nil else { throw RepositoryError.archivedParent }
        point.roomId = room.id; point.updatedAt = Date(); try save()
    }

    func move(_ device: Device, to point: PowerPoint) throws {
        guard point.archivedAt == nil else { throw RepositoryError.archivedParent }
        device.powerPointId = point.id; device.updatedAt = Date(); try save()
    }

    func setArchived(_ room: Room, _ archived: Bool) throws {
        room.archivedAt = archived ? Date() : nil; room.updatedAt = Date(); try save()
    }

    func setArchived(_ point: PowerPoint, _ archived: Bool) throws {
        point.archivedAt = archived ? Date() : nil; point.updatedAt = Date(); try save()
    }

    func setArchived(_ device: Device, _ archived: Bool) throws {
        device.archivedAt = archived ? Date() : nil; device.updatedAt = Date(); try save()
    }
}
