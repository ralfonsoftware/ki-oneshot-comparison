# Assumptions

The PRD leaves a small number of implementation and delivery details open. This file records every assumption made while implementing the app.

## Product and platform

- **A-1 — Bundle identity:** the development bundle identifier is `com.ralfehlert.EnergyTracker`, derived from the PRD owner. The App Group is `group.com.ralfehlert.EnergyTracker` and the private CloudKit container is `iCloud.com.ralfehlert.EnergyTracker`. They can be changed together in `project.yml` and the entitlements before signing a release.
- **A-2 — Deployment target:** “iOS/iPadOS 26 or later” means deployment target 26.0. No compatibility implementation for earlier systems is included.
- **A-3 — Signing and provisioning:** source and entitlement configuration are supplied, but an Apple Developer team, provisioning profiles, CloudKit schema deployment, TestFlight upload, support URL, and privacy-policy hosting cannot be created locally. The project builds without code signing for verification; the owner must select a team and deploy the CloudKit schema before a signed Personal/TestFlight release.
- **A-4 — Visual design:** the native visual system starts fresh from §9.3 rather than attempting to reproduce the retired web app. No separate §9.5 mockups exist in the PRD.
- **A-5 — Existing data:** no old-server connection or migration service is needed; the specified JSON file is the only migration path.

## Technical interpretation

- **A-6 — Exact decimal persistence:** decimal values are persisted as invariant-culture strings and converted to `Decimal` at the calculation boundary. This avoids binary floating-point loss and CloudKit decimal round-trip limitations. Exported values remain JSON numbers.
- **A-7 — Calendar dates:** tariff start dates are persisted as `yyyy-MM-dd` strings, not instants, so time-zone changes cannot move them. File input/output still follows the PRD’s instant representation.
- **A-8 — Internal sync metadata:** optional `updatedAt`, per-setting modification timestamps, and a household `generationChangedAt` timestamp are internal additive fields. They make deterministic last-write and replace-all conflict handling possible; they are not added to the v2 export format.
- **A-9 — No SwiftData relationships:** references use UUID fields rather than object relationships. This is CloudKit-safe and still enforces every import reference explicitly.
- **A-10 — CloudKit availability:** SwiftData automatic private-database mirroring is the primary store. If container creation fails, the app opens a local-only store so all non-sync features remain usable. Settings reports the account/sync state.
- **A-11 — First-launch sync wait:** SwiftData does not expose a public “initial import finished” callback. On a genuinely empty iCloud-backed launch the app polls for arriving local data for up to 15 seconds, with a short settling delay for a known-empty account. Automatic mirroring continues after onboarding and duplicate merge preserves records created meanwhile.
- **A-12 — Sync-triggered maintenance:** maintenance runs at launch, when the app becomes active, after local writes, and when SwiftData save notifications are observed. This is the closest public-API equivalent to a distinct automatic-mirroring import callback. Remote changes never create snapshots.
- **A-13 — Correction timestamp ties:** “earliest correction” for reconstructing an imported original reading means `correctedAt`, then lowest UUID; “newest correction” for effective values means `correctedAt`, then highest UUID.
- **A-14 — Regression prompts after corrections:** an existing prompt is retained even if a later correction makes its pair non-regressing. The PRD does not define automatic deletion; retaining the decision avoids silently rewriting history. New prompts are created only for currently regressing adjacent pairs that do not already have one.
- **A-15 — Replace-all metadata:** the imported household keeps its file identity and creation timestamp, while `generationChangedAt` is set to the restore time. This lets every device deterministically select the newest restored generation without changing the export schema.
- **A-16 — Import duplicates:** duplicate counts reported by import are exact duplicate readings only. Other duplicate classes are merged by the normal deterministic merge after insertion.
- **A-17 — Candidate storage:** candidate tariff fields are remembered in the local App Group defaults as decimal strings. They never enter SwiftData or CloudKit.
- **A-18 — Notifications:** if a tariff check is already due when reminders are enabled, the next reminder is scheduled for the next 10:00 local time rather than firing immediately. Re-enabling or editing data rebuilds the schedule.
- **A-19 — Smart Plug records:** these are imported, retained, validated, and exported, but deliberately have no user-facing list, matching D8.
- **A-20 — Widget logging:** the medium widget’s Log reading control opens the app directly on the sheet. Background logging is supplied by the separate Log Meter Reading App Intent.
- **A-21 — App language:** English is the development language and German translations are supplied in one String Catalog. Locale/region formatting is left to the active iOS per-app language and region.
- **A-22 — Development preview data:** previews and UI tests may create local sample data only through the same repository rules; no sample data is seeded in a normal fresh install.

## Verification limits

- **A-23 — Device-only behavior:** actual multi-device CloudKit conflicts, Siri/Action button assignment, Lock Screen widget rendering, local-notification delivery, Files/share-sheet behavior on hardware, and performance on the oldest supported physical iPhone require signed device testing. Automated tests cover their shared domain/store logic and the UI paths available in Simulator.
- **A-24 — No external services:** no analytics, crash SDK, telemetry, account service, web server, or non-Apple network dependency is introduced.
- **A-25 — Tariff-check round trip:** §8 has no field for `tariffCheckDoneAt`, although §FR-19 requires an identical round trip. Exports therefore include one optional additive household property, `tariffCheckDoneAtUtc`. It follows the existing unknown-property rule, so older readers ignore it and older v2 files without it import normally.
- **A-26 — Background intent before onboarding:** if Log Meter Reading or Log Event is invoked before onboarding, the intent creates a local household with the region-suggested currency and no Yearly Baseline. This preserves the requested record instead of rejecting it; the next app launch shows Today and lets the user finish settings.
- **A-27 — Restore generation markers:** old-generation Household records are retained as generation markers when held-back records are kept or discarded. They are excluded from all lists and calculations. User records from the old generation are never dropped without the explicit Keep/Discard choice.
- **A-28 — Initially unassigned local store:** if the app has never seen an Apple Account, its local store is treated as belonging to the first account that becomes available and uploads there, as required by FR-1. Once an account is known, a different CloudKit user record selects a separate physical store; switching back restores the prior account’s store. Signing out keeps the current store available locally.
- **A-29 — German voice:** German copy uses the informal singular “du”, consistent with a personal, calm single-user app rather than a formal household account product.
