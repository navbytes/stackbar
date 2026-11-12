#!/usr/bin/env python3
"""Writes Tests/Fixtures/palette-corpus.json: every command the store's
plugins declare (id, title, subtitle, keywords), read from a stackbar-plugins
checkout. PaletteGoldenTests ranks against it, so the golden queries meet the
words real plugins use.

    scripts/palette-corpus.py ../stackbar-plugins > Tests/Fixtures/palette-corpus.json
"""
import json, os, re, subprocess, sys

root = sys.argv[1]
command = re.compile(r'Command\("([^"]+)",\s*title:\s*"([^"]+)"(.*)')
subtitle = re.compile(r'subtitle:\s*"([^"]*)"')
keywords = re.compile(r'keywords:\s*\[([^\]]*)\]')
plugin_id = re.compile(r'^\s*id:\s*"(io\.navbytes\.stackbar[^"]*)"', re.M)

commands = []
for folder, _, files in sorted(os.walk(root)):
    if "/." in folder or "/Tests" in folder or "/.build" in folder:
        continue
    for name in sorted(files):
        if not name.endswith(".swift") or name in ("Package.swift",):
            continue
        text = open(os.path.join(folder, name), encoding="utf-8").read()
        found = plugin_id.search(text)
        if not found:
            continue
        for line in text.splitlines():
            match = command.search(line)
            if not match or "\\(" in match.group(2):
                continue
            rest = match.group(3)
            sub = subtitle.search(rest)
            words = keywords.search(rest)
            commands.append({
                "plugin": found.group(1),
                "id": match.group(1),
                "title": match.group(2),
                "subtitle": sub.group(1) if sub else None,
                "keywords": re.findall(r'"([^"]*)"', words.group(1)) if words else [],
            })

# System Commands lists its rows as Item(action: .x, keywords: [...]); the
# titles come from SystemAction in this repository.
actions = open(os.path.join(os.path.dirname(__file__), "..", "Sources", "StackbarProtocol", "SystemActions.swift")).read()
titles = dict(re.findall(r'case \.(\w+): return "([^"]+)"', actions))
system = os.path.join(root, "System", "SystemCommands", "SystemCommands.swift")
for line in open(system, encoding="utf-8"):
    match = re.search(r'Item\(action: \.(\w+), id: "([^"]+)".*?subtitle: "([^"]*)"', line)
    if match and match.group(1) in titles:
        words = keywords.search(line)
        commands.append({"plugin": "io.navbytes.stackbar.plugins.system-commands", "id": match.group(2), "title": titles[match.group(1)],
                         "subtitle": match.group(3), "keywords": re.findall(r'"([^"]*)"', words.group(1)) if words else []})

# Windows lists its snaps as Snap(id:, title:, keywords:).
windows = os.path.join(root, "Productivity", "Windows", "Windows.swift")
for line in open(windows, encoding="utf-8"):
    match = re.search(r'Snap\(id: "([^"]+)", title: "([^"]+)"', line)
    if match:
        words = keywords.search(line)
        commands.append({"plugin": "io.navbytes.stackbar.plugins.windows", "id": match.group(1), "title": match.group(2),
                         "subtitle": None, "keywords": re.findall(r'"([^"]*)"', words.group(1)) if words else []})

revision = subprocess.run(["git", "-C", root, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
json.dump({"source": f"navbytes/stackbar-plugins@{revision}", "commands": commands}, sys.stdout, indent=1, ensure_ascii=False)
print()
