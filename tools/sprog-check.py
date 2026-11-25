#!/usr/bin/env python3
"""Checks the menu's language files in assets/sprog (see the README there). Run from the repository root:

    python3 tools/sprog-check.py

It reports, and exits with 1 if there is anything:
  - a text that en.ini has and another language lacks (it would be shown in English); a regional variant
    (xx-YY.ini, e.g. es-MX.ini) holds only what differs from its language, so it may lack texts, but its
    language's file must be there
  - a text a language has that en.ini does not (a key that was changed or removed)
  - a key in en.ini that is no longer a text in any of the three versions' code (the Danish text was changed
    in the code, so its translations no longer match)
  - a language file that the Linux version does not compile in (linux/src/lang.rs lists them)
  - {0}/{1} that differ between a key and its translation
"""
import glob, os, re, sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(root)

def parse(path):
    name, texts = None, {}
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if line.startswith("#") or " = " not in line:
            continue
        key, value = (part.strip() for part in line.split(" = ", 1))
        if key == "@name":
            name = value
        elif value:
            if key in texts:
                problems.append(f"{path}: the text is there twice: {key}")
            texts[key] = value
    return name, texts

problems = []
files = sorted(glob.glob("assets/sprog/*.ini"))
langs = {os.path.basename(f)[:-4]: parse(f) for f in files}
if "en" not in langs:
    sys.exit("assets/sprog/en.ini is missing")
english = langs["en"][1]

for code, (name, texts) in langs.items():
    if not name:
        problems.append(f"{code}.ini: no @name line")
    if code in ("da", "en"):
        continue
    if "-" in code:
        # a regional variant: what it lacks comes from its language's file (es-MX → es → en)
        if code.split("-")[0] not in langs:
            problems.append(f"{code}.ini is a variant of {code.split('-')[0]}, but {code.split('-')[0]}.ini is missing")
        for key in texts:
            if key not in english:
                problems.append(f"{code}.ini has a text that en.ini does not: {key}")
        continue
    for key in english:
        if key not in texts:
            problems.append(f"{code}.ini lacks: {key}")
    for key in texts:
        if key not in english:
            problems.append(f"{code}.ini has a text that en.ini does not: {key}")
for code, (name, texts) in langs.items():
    for key, value in texts.items():
        if sorted(re.findall(r"\{\d\}", key)) != sorted(re.findall(r"\{\d\}", value)):
            problems.append(f"{code}.ini: the {{0}}/{{1}} differ in: {key}")

code_text = ""
for pattern in ("macos/Sources/JuleHygge/*.swift", "src/*.cs", "linux/src/*.rs"):
    for f in glob.glob(pattern):
        code_text += open(f, encoding="utf-8").read()
for key in english:
    if '"' + key + '"' not in code_text:
        problems.append(f"en.ini has a key that is not a text in the code any more: {key}")

linux = open("linux/src/lang.rs", encoding="utf-8").read()
for code in langs:
    if f'assets/sprog/{code}.ini' not in linux:
        problems.append(f"linux/src/lang.rs does not compile in {code}.ini (add it to BUILT_IN and raise the count)")

print(f"{len(langs)} languages ({', '.join(langs)}), {len(english)} texts in en.ini")
for p in problems:
    print("  " + p)
sys.exit(1 if problems else 0)
