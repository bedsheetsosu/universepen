#!/usr/bin/env python3
"""Lists L("…") keys used in the apps that have no English entry in Translations.swift,
and English entries that are no longer used. Exit code 1 if something is missing."""
import pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent
lit = r'"((?:[^"\\]|\\.)*)"'
used = set()
for d in ["Host", "Client", "Packages/TafelKit/Sources"]:
    for f in (root / d).rglob("*.swift"):
        if f.name in ("Translations.swift",):
            continue
        for m in re.finditer(r'\bL\(\s*' + lit, f.read_text()):
            used.add(m.group(1))
table = (root / "Packages/TafelKit/Sources/TafelKit/Translations.swift").read_text()
known = set(m.group(1) for m in re.finditer(r'^\s*' + lit + r'\s*:\s*"', table, re.M))
missing = sorted(used - known)
unused = sorted(known - used - {"Sprache"})
for k in missing:
    print("MISSING:", k)
for k in unused:
    print("unused: ", k)
print(f"{len(used)} keys used, {len(missing)} missing, {len(unused)} unused")
sys.exit(1 if missing else 0)
