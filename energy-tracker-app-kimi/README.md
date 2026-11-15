# Energy Tracker

Native iPhone and iPad electricity tracker implemented from `prd.md`: manual Main Meter readings, exact pace/status calculations, regression decisions, append-only corrections, trend history, flat-rate tariffs, events and labels, local reminders, widgets, App Intents, English/German localization, and validated v2 JSON import/export.

## Requirements

- Xcode 27.2 or newer with the iOS 26 SDK
- iOS/iPadOS 26.0 or newer
- XcodeGen 2.x (`brew install xcodegen`) when regenerating the project
- An Apple Developer team for CloudKit, App Groups, widgets on hardware, and TestFlight

## Open and build

The generated `EnergyTracker.xcodeproj` is included. To regenerate after changing target configuration:

```sh
xcodegen generate --spec project.yml
```

To build without signing:

```sh
xcodebuild -project EnergyTracker.xcodeproj \
  -scheme EnergyTracker -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Before a signed build, select a development team in Xcode and keep the bundle id, App Group, and CloudKit container aligned. Debug uses CloudKit Development; Personal and Release use Production. See `RELEASE_CHECKLIST.md`.

## Tests

```sh
# Pure calculation and exact JSON package
cd Packages/EnergyCore && swift test

# App/unit/UI test targets
xcodebuild -project EnergyTracker.xcodeproj -scheme EnergyTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO test
```

The package includes all mandatory E1–E12, T1–T2, V1–V3, and R1–R2 examples, calculation edge cases, every §8.4 validation class, and deterministic export/import round trips. App tests cover repository invariants, duplicate merge, corrections, generations, and UI flows.

## Architecture

- `Packages/EnergyCore`: pure Foundation `Decimal` calculations and exact v2 JSON codec. No UI, SwiftData, CloudKit, or network dependencies.
- `EnergyTracker/Shared`: versioned CloudKit-safe SwiftData models, App Group store, repository invariants, deterministic merge/generation handling, import/export, notifications, and shared presentation models.
- `EnergyTracker/App`, `Today`, `History`, `Tariffs`, `Settings`: adaptive SwiftUI app.
- `EnergyTracker/Widgets`: small/medium Home Screen and circular/rectangular/inline Lock Screen widgets using the same store and calculation package.
- `EnergyTracker/Intents`: background reading/event logging and status intents plus English/German App Shortcuts.
- `Scripts`: reproducible English/German String Catalog generation; untranslated app copy fails the script.

All implementation assumptions and device-only verification limits are recorded in `assumptions.md`.

## Localization

After changing user-facing copy, add its German translation to `Scripts/translations.de.json` and run:

```sh
python3 Scripts/build_string_catalog.py
xcodegen generate --spec project.yml
```

The app follows the iOS per-app language setting. There is intentionally no in-app language selector.
