# Assumptions

These are the assumptions made while implementing `prd.md`, for every question the PRD leaves open. Section and requirement numbers refer to the PRD.

## Open questions from §15

1. **iOS mockups.** No mockups exist, so the UI follows §9.3 and §9.4 directly. It uses native SwiftUI controls, Liquid Glass (`glassEffect`, `.glass` button styles), SF Symbols and the color tokens from §9.3. It does not reuse the old web app's visual system.
2. **Old web deployment.** This has no effect on the app. The app never contacts the old server.

## Tooling and project setup

3. The project uses Xcode 27.2 with the iOS 27.2 SDK. The deployment target is iOS/iPadOS 26.0, as D2 requires.
4. XcodeGen (`project.yml`) generates the Xcode project. `project.yml` is the source of truth; run `xcodegen generate` after you change it.
5. The bundle id is `de.ralfonsoftware.EnergyTracker`, the App Group is `group.de.ralfonsoftware.EnergyTracker` and the CloudKit container is `iCloud.de.ralfonsoftware.EnergyTracker`. All three come from `Config/Shared.xcconfig` and can be changed in one place.
6. The development team id is not in the repository. Copy `Config/Signing.xcconfig.example` to `Config/Signing.xcconfig`, which git ignores, and set `DEVELOPMENT_TEAM`.
7. There are three build configurations:
   - `Debug` uses the CloudKit **Development** environment.
   - `Personal` and `Release` use the **Production** environment through the `com.apple.developer.icloud-container-environment` entitlement (§10).
   - The `EnergyTracker-Personal` scheme builds and archives `Personal`.
8. The app and widget targets use the Swift 5 language mode to keep concurrency friction low with SwiftData and WidgetKit. The pure `EnergyCore` package uses Swift 6.
9. The app icon is a generated placeholder: a meter needle on the brand teal, with dark and tinted variants. Run `swift scripts/make_icon.swift App/Assets.xcassets/AppIcon.appiconset` to render it again.
10. The support URL and privacy policy URL are build settings (`ET_SUPPORT_URL`, `ET_PRIVACY_POLICY_URL`). They are empty for now, and Settings → About shows them only when set (§10).

## Storage and sync

11. **Decimals** are stored in SwiftData as invariant-culture strings such as `"12345.6"`, not as `Decimal` attributes. A string round-trips through CloudKit without any loss, and §11 explicitly allows an alternative representation.
12. **No SwiftData relationships.** Records refer to each other by UUID fields. This removes the inverse and delete-rule pitfalls of CloudKit (§7.2).
13. **Calendar dates.** A tariff start date is stored as a `"YYYY-MM-DD"` string, so a time-zone change never moves it (§11, Time).
14. **Timestamps.** New reading and event timestamps are truncated to whole seconds. This matches the "to the second" duplicate rule, and exports then round-trip exactly.
15. **Per-field merge for the Household.** The Household stores a JSON map of the last change time of each settings field (`fieldStampsJSON`). The Household merge (§7.4) uses it to take "the value from the record that changed it last".
16. **Account separation (FR-2).** The app relies on SwiftData's CloudKit mirroring (`NSPersistentCloudKitContainer`) to keep data per Apple Account. When the account changes, the mirroring removes the previous account's local mirror. The app listens for `CKAccountChanged` and reloads.
17. **iCloud unavailable (FR-1).**
    - If the CloudKit-backed store cannot be created, for example in a build without iCloud entitlements, the app falls back to a local-only store.
    - The iCloud line in Settings is based on `CKContainer.accountStatus()`.
    - Turning iCloud off for this app only appears in Settings if CloudKit reports it through the account status.
18. **Detecting sync imports (§7.6).** The app observes `NSPersistentCloudKitContainer.eventChangedNotification` and `NSPersistentStoreRemoteChange`, with a 0.6 s debounce. After each sync import it runs the merge, re-checks regressions, refreshes the UI, reschedules notifications and reloads widgets. It never writes a snapshot for a remote change.
19. **First-launch wait (FR-3).** "Looking for your data in iCloud…" shows only when all of these hold:
    - The store is empty.
    - The iCloud account is available.
    - No CloudKit import has finished yet.

    The wait lasts at most 15 s.
20. **Widget store access.** The widget extension opens the same App Group store read-only and without CloudKit mirroring. Only the app process mirrors.
21. **Current generation (§7.5).**
    - The Household with the newest `generationStartedAt` defines the current generation.
    - The merge deletes Households of an older generation, for example one uploaded by an Apple device that was offline during a restore, without asking. They are a settings record, not user data. Their readings, events and other records are held back and offered with **Keep** / **Discard**.
    - Records without a generation count as current.
22. **Held-back card.** When only other record types are held back, such as tariffs or snapshots, the card says "N records from before the restore…".
23. **Classification conflict notice (§7.3).** The notice is an attention card on Today, placed directly after the regression card. Dismissing it is remembered on that Apple device only.
24. **Replace-all.** Replace-all deletes records one by one, not with a batch delete, so every deletion is mirrored to CloudKit. Importing into an empty data set also starts a new generation.

## Calculations and domain rules

25. **Undefined Status while a decision is open.** If an open regression prompt leaves fewer than two usable readings, Today shows "Decide about the lower reading to see your status" instead of "Log your first reading to get started". Both are undefined states, never shown as one of the three Status states.
26. **Rollover without a known capacity.** A rollover without any known digit capacity, on the prompt or on the Main Meter, cannot be measured. The pair is then treated like a reset and adds nothing. The UI always asks for the capacity, so this happens only with imported data.
27. **Resolved prompts after edits.** A resolved prompt applies to its reading only while that reading is lower than its current chronological predecessor.
    - After a correction or backfill, an **open** prompt whose reading is no longer a regression is deleted.
    - An open prompt whose predecessor changed gets the new predecessor id.
    - Resolved prompts are kept for history.
28. **Changing a classification (FR-11)** writes a new resolved prompt record and deletes the old one. The snapshot it writes then has its own `causeId`, so the snapshot merge (same `causeId`, keep the earliest) cannot drop it. The prompt merge still keeps the latest decision.
29. **Snapshot when a prompt opens.** A reading that opens a regression prompt still writes a snapshot if the Status, which then excludes that reading, is defined.
30. **Low confidence** uses fractional days: `daysSinceLastReading > lowConfidenceGapDays`. Exactly 45.0 days is not yet low confidence.
31. **Duplicate check on save (FR-4)** compares the original value, as the merge rule does, with timestamps compared to the second.
32. **Tariff comparison** needs a defined pace but no Yearly Baseline. The low-confidence note under the result uses the same gap rule.
33. **Tariff Check "Done"** stores the current instant. The due calculation uses its calendar date in the device's time zone.
34. **Tariff Check notification (FR-21)** is scheduled only when its 10:00 local fire time is still in the future. If the check is already due, the Today card covers it and no notification is sent.

## Import and export file

35. **Extra fields for round trips.** Three fields that are not part of the old format are written so that export → import is lossless (FR-19). Older readers ignore them as unknown properties (§8.1). The app reads them when present and does not require them:
    - `household.tariffCheckDoneAtUtc`
    - `events[].updatedAtUtc`
    - `statusSnapshots[].causeId`
36. **Missing properties.**
    - A nullable field may be missing; it is then read as `null`.
    - Non-nullable fields must be present.
    - All top-level arrays are required except `householdMembers`, which is ignored entirely.
    - `smartPlugReadings[]` have no `createdAtUtc` in the format.
37. **Extra domain checks on import (§8.4 rule 6),** in addition to the listed rules:
    - Event description 1–500 characters.
    - Household currency is a 3-letter upper-case code.
    - `lowConfidenceGapDays` 1–365 and `tariffCheckCadenceMonths` 1–24.
    - Threshold and baseline are not negative.
    - Digit capacity is greater than 0.
38. **Integers** in the file may be written with a fractional zero, such as `12.0`. They must be whole numbers.
39. **Large files.** Files over 250 MB are rejected before parsing. The whole file is parsed in memory. Very large Smart Plug files near the limit may need a lot of memory on older iPhones; a streaming parser would be a later optimization.
40. **Main Meter in the export.** `mainMeter` is exported as `null` when there are no readings and no known digit capacity.

## UI and copy

41. **Status sentences** round kWh to whole numbers, for example "42 kWh under baseline pace so far". *Within range* above zero says "N kWh above baseline pace so far, inside your margin". A difference that rounds to zero says "Right on baseline pace so far".
42. **Saved confirmation.** "Saved · Within range" is a short toast at the bottom of the screen. When the Status is undefined it says just "Saved".
43. **Settings placement.** On iPhone and in compact width, Settings is pushed from the Today toolbar. On iPad in regular width it is a sidebar item, and ⌘, opens it.
44. **Attention cards** on Today come in this order:
    1. Regression decision.
    2. Classification conflict notice.
    3. Held-back records.
    4. Duplicate tariff start date.
    5. Tariff Check due.
45. **Event tags.** An event's tag text changes only when the user picks a new tag while editing. Renaming, moving or archiving a structure item never changes it (FR-15).
46. **Trend chart** plots `pace − baseline` (difference to baseline pace), with point color by Status. The default range is 3 months and is remembered per Apple device. Gaps longer than the low-confidence setting break the line, show an amber band and add a sentence below the chart.
47. **List search** (⌘F on iPad) matches the formatted value or date of readings, and the description or tag of events.
48. **Number input** accepts the active locale's decimal separator, for example `12345,6` in German, and is parsed exactly, never through `Double`.
49. **The candidate tariff** is stored in this Apple device's `UserDefaults` and never synced (FR-13). The currency picker offers common European currencies plus the current one.
50. **Onboarding presets** are tap-to-fill buttons; none is pre-selected (FR-3). The suggested currency comes from the device region. **Skip** on the currency step keeps the region currency as the default.
51. **German copy.** The developer wrote the German translation. A native-speaker review before App Store release is recommended.

## System integration

52. **Log Meter Reading intent.** App Intents have no `Decimal` parameter type, so the `kWh` parameter is a `Double`. It is converted through its shortest decimal representation; for example `12345.6` stays `12345.6`. The usual validation still applies, including at most 2 decimal places.
53. **App Shortcut phrases** cannot contain a numeric parameter. Siri therefore asks for the kWh value after the phrase.
54. **Control Center control.** A control cannot take number input, so it opens the app directly on the Log Reading sheet. The **Log Meter Reading** intent itself can be assigned to the Action button through Shortcuts and runs without opening the app.
55. **Widget timeline.** The widget timeline has one entry now and one shortly after each local midnight for 7 days. It refreshes at least daily. The app also reloads it after every write and every sync import.
56. **Intent process.** Intents run in the app process and share its store and container. When the data set is empty, an intent creates a Household with default settings first.

## Testing

57. **UI tests** use an in-memory store, enabled by the `-ETUITesting` launch argument. They seed data through the import path (`ETUITestSeedJSON`), and pass import files as base64 (`ETUITestImportJSON`) because XCUITest cannot drive the system file picker. These hooks are active only with `-ETUITesting`.
58. **Two-device simulation.** The merge and generation rules are tested in `EnergyCore` on simulated two-device record sets (`MergeTests`). They are not tested against a live CloudKit container.
