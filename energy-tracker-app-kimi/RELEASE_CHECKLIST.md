# Release checklist

## Every Personal or TestFlight build

- [ ] Increment the semantic marketing version when appropriate and always increment `CURRENT_PROJECT_VERSION` in `project.yml`.
- [ ] Run `python3 Scripts/build_string_catalog.py` and confirm no missing German strings.
- [ ] Run all EnergyCore, app unit, and UI tests.
- [ ] Confirm no new third-party SDK, analytics, telemetry, private API, or non-Apple network traffic was introduced.
- [ ] Confirm `PrivacyInfo.xcprivacy` still declares no collected data and no tracking.
- [ ] Confirm `ITSAppUsesNonExemptEncryption` remains `NO` and any new permission has a purpose string.
- [ ] Supply `SupportURL` and `PrivacyPolicyURL` in `EnergyTracker/Resources/Info.plist` for distribution; no code change is needed.
- [ ] Test offline launch, reading entry, correction, tariff comparison, import, and export on hardware.
- [ ] Test small/medium Home Screen widgets and circular/rectangular/inline Lock Screen widgets.
- [ ] Test Siri/Shortcuts phrases in English and German and assign the reading intent to the desired system control.
- [ ] Verify reminders are per device, permission is requested only after enabling them, and tapping one opens Tariffs.
- [ ] Test Dynamic Type at the largest accessibility sizes, VoiceOver, trend Audio Graph, Reduce Motion, and Reduce Transparency in Light and Dark appearances.

## CloudKit schema and environments

- [ ] Confirm all schema changes are additive: no renamed/deleted entities or attributes, no unique constraints, and every attribute is optional or defaulted.
- [ ] Build and run once against CloudKit **Development** and exercise every new/changed field.
- [ ] **Deploy the Development schema to Production in CloudKit Console before installing any Personal or TestFlight build that adds model fields.**
- [ ] Confirm Personal entitlements explicitly set `com.apple.developer.icloud-container-environment = Production`.
- [ ] Confirm Release/TestFlight entitlements also use Production; Debug remains Development.
- [ ] Verify the same bundle id, `group.com.ralfehlert.EnergyTracker`, and `iCloud.com.ralfehlert.EnergyTracker` are enabled for the selected team.
- [ ] Test first-launch import, offline catch-up, exact-duplicate merging, and two-device reading/snapshot counts.
- [ ] Test a replace-all restore while a second device is offline; when it reconnects, held-back records must require Keep or Discard.
- [ ] Test an Apple Account change: no records from the previous account may appear in or upload to the new account.
- [ ] Record measured cold launch, save-to-status, all-history chart, import, and export times on the oldest supported iPhone with the §11 data volume.

## TestFlight notes

- [ ] Use the Release configuration (Production CloudKit).
- [ ] Include export/import and privacy behavior in tester notes.
- [ ] Remember that builds expire after 90 days; local and iCloud data are unaffected.
