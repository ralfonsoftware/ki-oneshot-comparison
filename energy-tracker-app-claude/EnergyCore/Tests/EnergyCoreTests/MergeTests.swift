import Foundation
import Testing
@testable import EnergyCore

/// Applies a plan to an input the way the app applies it to the store. Used to check idempotency.
func apply(_ plan: DuplicateMerge.Plan, to input: DuplicateMerge.Input) -> DuplicateMerge.Input {
    var out = input
    let deletedHouseholds = Set(plan.deleteHouseholdIds)
    if let keep = plan.keepHouseholdId, let index = out.households.firstIndex(where: { $0.id == keep }) {
        for (field, source) in plan.householdFieldSources {
            out.households[index].fieldStamps[field] = input.households.first { $0.id == source }?.fieldStamps[field]
        }
    }
    out.households.removeAll { deletedHouseholds.contains($0.id) }
    if let keep = plan.keepMeterId, let cap = plan.meterDigitCapacityKwh, let i = out.meters.firstIndex(where: { $0.id == keep }) {
        out.meters[i].digitCapacityKwh = cap
    }
    out.meters.removeAll { plan.deleteMeterIds.contains($0.id) }
    for i in out.readings.indices { if let m = plan.readingMeterUpdates[out.readings[i].id] { out.readings[i].mainMeterId = m } }
    out.readings.removeAll { plan.deleteReadingIds.contains($0.id) }
    for i in out.prompts.indices {
        if let m = plan.promptMeterUpdates[out.prompts[i].id] { out.prompts[i].mainMeterId = m }
        if let r = plan.promptReadingUpdates[out.prompts[i].id] { out.prompts[i].readingId = r }
        if let r = plan.promptPreviousReadingUpdates[out.prompts[i].id] { out.prompts[i].previousReadingId = r }
    }
    out.prompts.removeAll { plan.deletePromptIds.contains($0.id) }
    for i in out.snapshots.indices { if let c = plan.snapshotCauseUpdates[out.snapshots[i].id] { out.snapshots[i].causeId = c } }
    out.snapshots.removeAll { plan.deleteSnapshotIds.contains($0.id) }
    for i in out.corrections.indices { if let e = plan.correctionEntityUpdates[out.corrections[i].id] { out.corrections[i].entityId = e } }
    out.corrections.removeAll { plan.deleteCorrectionIds.contains($0.id) }
    return out
}

@Suite("Duplicate merge §7.4 — simulated two-device record sets")
struct MergeTests {
    /// Device A and device B both started fresh offline, then synced.
    func twoDeviceStartFresh() -> DuplicateMerge.Input {
        let gen = uid(900)
        let hA = DuplicateMerge.Household(id: uid(1), createdAt: utc(2026, 1, 1, 8), generation: gen, generationStartedAt: utc(2026, 1, 1, 8),
                                          fieldStamps: ["currency": utc(2026, 1, 1, 8), "yearlyBaselineKwh": utc(2026, 1, 3)])
        let hB = DuplicateMerge.Household(id: uid(2), createdAt: utc(2026, 1, 1, 9), generation: gen, generationStartedAt: utc(2026, 1, 1, 8),
                                          fieldStamps: ["currency": utc(2026, 1, 2), "yearlyBaselineKwh": utc(2026, 1, 1, 9)])
        let mA = DuplicateMerge.Meter(id: uid(10), createdAt: utc(2026, 1, 1, 8))
        let mB = DuplicateMerge.Meter(id: uid(11), createdAt: utc(2026, 1, 1, 9), digitCapacityKwh: 100_000)
        // Same physical reading entered on both Apple devices (same second, same value), plus distinct readings.
        let rA = DuplicateMerge.Reading(id: uid(100), createdAt: utc(2026, 1, 5, 7, 0, 3), mainMeterId: mA.id, timestamp: utc(2026, 1, 5, 7).addingTimeInterval(0.2), originalKwh: dec("1000.5"))
        let rB = DuplicateMerge.Reading(id: uid(101), createdAt: utc(2026, 1, 5, 7, 0, 9), mainMeterId: mB.id, timestamp: utc(2026, 1, 5, 7).addingTimeInterval(0.7), originalKwh: dec("1000.50"))
        let rSameTimeOtherValue = DuplicateMerge.Reading(id: uid(102), createdAt: utc(2026, 1, 5, 7, 1), mainMeterId: mB.id, timestamp: utc(2026, 1, 5, 7), originalKwh: dec("1001"))
        let rOther = DuplicateMerge.Reading(id: uid(103), createdAt: utc(2026, 1, 6), mainMeterId: mA.id, timestamp: utc(2026, 1, 6), originalKwh: dec("1010"))
        let corrB = DuplicateMerge.Correction(id: uid(200), entityType: "MeterReading", entityId: rB.id, fieldName: "KwhValue", oldValue: "1000.5", newValue: "1000.6", correctedAt: utc(2026, 1, 5, 8))
        let corrDupA = DuplicateMerge.Correction(id: uid(201), entityType: "MeterReading", entityId: rA.id, fieldName: "KwhValue", oldValue: "1000.5", newValue: "1000.6", correctedAt: utc(2026, 1, 5, 8))
        let snapA = DuplicateMerge.Snapshot(id: uid(300), createdAt: utc(2026, 1, 5, 7, 0, 3), causeId: rA.id)
        let snapB = DuplicateMerge.Snapshot(id: uid(301), createdAt: utc(2026, 1, 5, 7, 0, 9), causeId: rB.id)
        let pOpen = DuplicateMerge.Prompt(id: uid(400), createdAt: utc(2026, 1, 6), mainMeterId: mA.id, readingId: rOther.id, previousReadingId: rA.id)
        let pResolvedOld = DuplicateMerge.Prompt(id: uid(401), createdAt: utc(2026, 1, 6), mainMeterId: mB.id, readingId: rOther.id, previousReadingId: rB.id, resolvedAt: utc(2026, 1, 7), classification: .reset)
        let pResolvedNew = DuplicateMerge.Prompt(id: uid(402), createdAt: utc(2026, 1, 6), mainMeterId: mA.id, readingId: rOther.id, previousReadingId: rA.id, resolvedAt: utc(2026, 1, 8), classification: .rollover)
        return DuplicateMerge.Input(
            households: [hB, hA], meters: [mB, mA], readings: [rB, rOther, rA, rSameTimeOtherValue],
            prompts: [pOpen, pResolvedOld, pResolvedNew], snapshots: [snapB, snapA], corrections: [corrB, corrDupA]
        )
    }

    @Test("Household: keep the earliest, take each field from the record that changed it last")
    func household() {
        let plan = DuplicateMerge.plan(twoDeviceStartFresh())
        #expect(plan.keepHouseholdId == uid(1))
        #expect(plan.deleteHouseholdIds == [uid(2)])
        #expect(plan.householdFieldSources == ["currency": uid(2)])
    }

    @Test("Main Meter: keep the earliest, move readings and prompts, keep the known capacity")
    func meter() {
        let plan = DuplicateMerge.plan(twoDeviceStartFresh())
        #expect(plan.keepMeterId == uid(10))
        #expect(plan.deleteMeterIds == [uid(11)])
        #expect(plan.meterDigitCapacityKwh == 100_000)
        #expect(plan.readingMeterUpdates[uid(101)] == uid(10))
        #expect(plan.readingMeterUpdates[uid(102)] == uid(10))
        #expect(plan.promptMeterUpdates[uid(401)] == uid(10))
    }

    @Test("Exact duplicate readings merge; same timestamp with a different value does not")
    func readings() {
        let plan = DuplicateMerge.plan(twoDeviceStartFresh())
        #expect(plan.deleteReadingIds == [uid(101)])
        #expect(plan.readingRemap == [uid(101): uid(100)])
        #expect(plan.mergedReadingCount == 1)
        // Corrections and snapshot causes of the duplicate move to the keeper, then identical ones collapse.
        #expect(plan.correctionEntityUpdates[uid(200)] == uid(100))
        #expect(plan.deleteCorrectionIds == [uid(201)])
        #expect(plan.snapshotCauseUpdates[uid(301)] == uid(100))
        #expect(plan.deleteSnapshotIds == [uid(301)])
        #expect(plan.promptPreviousReadingUpdates[uid(401)] == uid(100))
    }

    @Test("Prompts: resolved beats open, latest resolvedAt wins, conflict is reported")
    func prompts() {
        let plan = DuplicateMerge.plan(twoDeviceStartFresh())
        #expect(Set(plan.deletePromptIds) == [uid(400), uid(401)])
        #expect(plan.classificationConflicts == [uid(103): .rollover])
    }

    @Test("Merge is idempotent")
    func idempotent() {
        let input = twoDeviceStartFresh()
        let first = DuplicateMerge.plan(input)
        let after = apply(first, to: input)
        let second = DuplicateMerge.plan(after)
        #expect(second.isEmpty)
        #expect(after.readings.count == 3)
        #expect(after.households.count == 1)
        #expect(after.meters.count == 1)
    }

    @Test("Merge is deterministic regardless of record order (both Apple devices reach the same result)")
    func deterministic() {
        let input = twoDeviceStartFresh()
        var reversed = input
        reversed.households.reverse()
        reversed.meters.reverse()
        reversed.readings.reverse()
        reversed.prompts.reverse()
        reversed.snapshots.reverse()
        reversed.corrections.reverse()
        let a = DuplicateMerge.plan(input), b = DuplicateMerge.plan(reversed)
        #expect(a.keepHouseholdId == b.keepHouseholdId)
        #expect(a.householdFieldSources == b.householdFieldSources)
        #expect(a.deleteReadingIds == b.deleteReadingIds)
        #expect(Set(a.deletePromptIds) == Set(b.deletePromptIds))
        #expect(a.deleteSnapshotIds == b.deleteSnapshotIds)
        #expect(a.deleteCorrectionIds == b.deleteCorrectionIds)
    }

    @Test("Snapshots with the same cause keep the earliest")
    func snapshots() {
        let s1 = DuplicateMerge.Snapshot(id: uid(2), createdAt: utc(2026, 1, 1), causeId: uid(99))
        let s2 = DuplicateMerge.Snapshot(id: uid(1), createdAt: utc(2026, 1, 1), causeId: uid(99))
        let s3 = DuplicateMerge.Snapshot(id: uid(3), createdAt: utc(2025, 1, 1), causeId: uid(98))
        let plan = DuplicateMerge.plan(DuplicateMerge.Input(snapshots: [s1, s2, s3]))
        #expect(plan.deleteSnapshotIds == [uid(2)])
    }

    @Test("Open prompts only: keep the earliest")
    func openPrompts() {
        let p1 = DuplicateMerge.Prompt(id: uid(5), createdAt: utc(2026, 1, 2), mainMeterId: uid(1), readingId: uid(9), previousReadingId: uid(8))
        let p2 = DuplicateMerge.Prompt(id: uid(6), createdAt: utc(2026, 1, 1), mainMeterId: uid(1), readingId: uid(9), previousReadingId: uid(8))
        #expect(DuplicateMerge.plan(DuplicateMerge.Input(prompts: [p1, p2])).deletePromptIds == [uid(5)])
    }
}

@Suite("Data set generation §7.5")
struct GenerationTests {
    @Test("A restore's generation supersedes an offline Apple device's older household")
    func newestGenerationWins() {
        let oldGen = uid(800), newGen = uid(801)
        // The offline device's household is older (earlier createdAt) but belongs to the replaced generation.
        let offline = DuplicateMerge.Household(id: uid(1), createdAt: utc(2025, 1, 1), generation: oldGen, generationStartedAt: utc(2025, 1, 1))
        let restored = DuplicateMerge.Household(id: uid(2), createdAt: utc(2026, 1, 1), generation: newGen, generationStartedAt: utc(2026, 11, 1))
        let plan = DuplicateMerge.plan(DuplicateMerge.Input(households: [offline, restored]))
        #expect(plan.keepHouseholdId == uid(2))
        #expect(plan.deleteHouseholdIds == [uid(1)])
    }

    @Test("Records from another generation are held back")
    func heldBack() {
        #expect(Generations.isHeldBack(recordGeneration: uid(1), current: uid(2)))
        #expect(!Generations.isHeldBack(recordGeneration: uid(2), current: uid(2)))
        #expect(!Generations.isHeldBack(recordGeneration: nil, current: uid(2)))
    }
}
