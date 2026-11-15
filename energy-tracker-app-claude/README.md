# Energy Tracker for iOS & iPadOS

A personal electricity tracker for manual meter readings, built as specified in [`prd.md`](prd.md). Decisions the PRD left open are listed in [`assumptions.md`](assumptions.md).

## Layout

| Path | Contents |
|---|---|
| `EnergyCore/` | Pure Swift package: every calculation of §5, the v2 export format (§8) with validation, the duplicate merge (§7.4) and the generation rules (§7.5). No UI, persistence or sync code. |
| `Shared/` | Code and resources used by the app and the widget extension: SwiftData models (versioned schema), store setup, data loading, formatting, colors, String Catalog. |
| `App/` | SwiftUI app: `EnergyStore` (all writes), sync monitor, notifications, App Intents, views. |
| `Widgets/` | Home Screen and Lock Screen widgets, Control Center control. |
| `UITests/` | UI tests: log reading, regression prompt, correction, tariff compare, import, export. |
| `Config/` | Build configurations, entitlements, signing template. |
| `scripts/` | App icon renderer and String Catalog builder. |

## Setup

1. Install XcodeGen: `brew install xcodegen`.
2. Copy `Config/Signing.xcconfig.example` to `Config/Signing.xcconfig` and set your team id.
3. If needed, change the bundle id in `Config/Shared.xcconfig`. The App Group and the CloudKit container follow it.
4. Run `xcodegen generate`, then open `EnergyTracker.xcodeproj`.
5. In the Apple Developer portal, enable iCloud (CloudKit) with the container `iCloud.<bundle id>` and the App Group `group.<bundle id>` for the app id.

## Build configurations (§10)

| Configuration | CloudKit environment | Use |
|---|---|---|
| Debug | Development | Simulator and test data |
| Personal | Production | Personal builds installed from Xcode (`EnergyTracker-Personal` scheme) |
| Release | Production | TestFlight and App Store |

**Release checklist.** Before you install any Personal or TestFlight build that adds model fields, deploy the Development schema to Production in the CloudKit Console. Production schema changes are additive only.

## Tests

```sh
# Calculations, export format, merge, generations (fast, runs on macOS)
cd EnergyCore && swift test

# Everything, including UI tests, on a simulator
xcodebuild test -project EnergyTracker.xcodeproj -scheme EnergyTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Localization

English and German live in `Shared/Localizable.xcstrings` and `App/AppShortcuts.xcstrings`. To refresh the catalogs after you change any copy:

```sh
xcodebuild -exportLocalizations -project EnergyTracker.xcodeproj -localizationPath build/loc -exportLanguage de
python3 scripts/build_strings.py build/loc/de.xcloc
```

The script lists any string that has no German translation in `scripts/de_translations.json`.
