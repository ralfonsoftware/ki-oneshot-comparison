#!/usr/bin/env python3
"""Builds the String Catalogs from the source strings Xcode extracts and the German table.

Usage:
  xcodebuild -exportLocalizations -project EnergyTracker.xcodeproj -localizationPath build/loc -exportLanguage de
  python3 scripts/build_strings.py build/loc/de.xcloc

A new language is a new table plus a catalog addition, not a code change (FR-25).
"""
import json, sys, xml.etree.ElementTree as ET
from pathlib import Path

root = Path(__file__).resolve().parent.parent
xcloc = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "build/loc/de.xcloc"
de = json.loads((root / "scripts/de_translations.json").read_text())
ns = {"x": "urn:oasis:names:tc:xliff:document:1.2"}
tree = ET.parse(xcloc / "Localized Contents/de.xliff")

keys = {}
for f in tree.getroot().findall("x:file", ns):
    keys[f.get("original")] = [u.get("id") for u in f.findall(".//x:trans-unit", ns)]

def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}

PLURALS = {
    "%lld days": ({"one": "%lld day", "other": "%lld days"}, {"one": "%lld Tag", "other": "%lld Tage"}),
    "%lld months": ({"one": "%lld month", "other": "%lld months"}, {"one": "%lld Monat", "other": "%lld Monate"}),
}

missing = []
strings = {}
for key in sorted(set(keys.get("Shared/Localizable.xcstrings", []))):
    entry = {}
    if key in PLURALS:
        en, d = PLURALS[key]
        entry["localizations"] = {
            "en": {"variations": {"plural": {k: unit(v) for k, v in en.items()}}},
            "de": {"variations": {"plural": {k: unit(v) for k, v in d.items()}}},
        }
    elif key in de:
        entry["localizations"] = {"de": unit(de[key])}
    else:
        missing.append(key)
    strings[key] = entry
catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
(root / "Shared/Localizable.xcstrings").write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n")

# App Shortcut phrases: every phrase of EnergyShortcuts, in both languages.
phrases = {
    "Log a meter reading in ${applicationName}": "Zählerstand in ${applicationName} erfassen",
    "Log meter reading with ${applicationName}": "Zählerstand mit ${applicationName} erfassen",
    "New ${applicationName} reading": "Neuer ${applicationName}-Zählerstand",
    "Get my ${applicationName} status": "Meinen ${applicationName}-Status abfragen",
    "Is my electricity on track in ${applicationName}": "Liegt mein Strom in ${applicationName} im Plan",
    "${applicationName} status": "${applicationName}-Status",
    "Log an event in ${applicationName}": "Ereignis in ${applicationName} erfassen",
    "Add a note to ${applicationName}": "Notiz zu ${applicationName} hinzufügen",
}
shortcuts = {"sourceLanguage": "en", "version": "1.0",
             "strings": {k: {"localizations": {"de": unit(v)}} for k, v in phrases.items()}}
(root / "App/AppShortcuts.xcstrings").write_text(json.dumps(shortcuts, ensure_ascii=False, indent=2, sort_keys=True) + "\n")

if missing:
    print("Missing German translations:")
    for m in missing:
        print("  ", repr(m))
    sys.exit(1)
print(f"{len(strings)} strings, all translated.")
