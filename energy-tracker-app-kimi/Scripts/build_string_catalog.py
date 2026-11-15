#!/usr/bin/env python3
"""Build the English/German String Catalog and fail on untranslated app copy."""
import json
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parents[1]
source = root / "EnergyTracker"
translations_path = root / "Scripts" / "translations.de.json"
output = root / "EnergyTracker" / "Resources" / "Localizable.xcstrings"

patterns = [
    r'String\(localized:\s*"((?:[^"\\]|\\.)*)"',
    r'LocalizedStringResource\s*=\s*"((?:[^"\\]|\\.)*)"',
    r'IntentDescription\("((?:[^"\\]|\\.)*)"\)',
    r'requestValueDialog:\s*"((?:[^"\\]|\\.)*)"',
    r'@Parameter\(title:\s*"((?:[^"\\]|\\.)*)"',
    r'shortTitle:\s*"((?:[^"\\]|\\.)*)"',
]
keys = set()
for path in source.rglob("*.swift"):
    text = path.read_text()
    for pattern in patterns:
        keys.update(match.group(1) for match in re.finditer(pattern, text))
keys.update(["1 person", "2 people", "3 people", "4 people"])
translations = json.loads(translations_path.read_text())
missing = sorted(keys - translations.keys())
unused = sorted(translations.keys() - keys)
if missing:
    print("Missing German translations:", file=sys.stderr)
    for key in missing:
        print(f"  {json.dumps(key, ensure_ascii=False)}", file=sys.stderr)
    sys.exit(1)
if unused:
    print("Warning: unused translations:", ", ".join(unused), file=sys.stderr)

strings = {}
for key in sorted(keys):
    strings[key] = {
        "localizations": {
            "en": {"stringUnit": {"state": "translated", "value": key}},
            "de": {"stringUnit": {"state": "translated", "value": translations[key]}},
        }
    }
catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
output.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
print(f"Wrote {len(keys)} English and German strings to {output}")
