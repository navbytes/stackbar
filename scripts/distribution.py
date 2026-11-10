#!/usr/bin/env python3
"""Who publishes this build: the store, its key, the team, the update feed and
the links (Sources/StackbarHostCore/Distribution.swift).

Packaging/distribution.json holds navbytes' values. An organization that builds
its own copy adds Packaging/distribution.override.json with only the keys it
changes (objects merge key by key; anything else replaces) and edits nothing
else, so merging upstream never conflicts. See docs/self-hosting.md.

    scripts/distribution.py show                 the merged distribution
    scripts/distribution.py get <key.path>       one value ("" for null)
    scripts/distribution.py plist <Info.plist>…  write it into built Info.plists
    scripts/distribution.py entitlements <file>… point the app group at the team

`--override <file>` reads another override (tests). The values go into the app
at build time only; the app never reads them from its environment.
"""
import base64
import json
import pathlib
import plistlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASE = ROOT / "Packaging" / "distribution.json"
OVERRIDE = ROOT / "Packaging" / "distribution.override.json"
BUNDLE_ID = "io.navbytes.stackbar"
INFO_KEY = "StackbarDistribution"

# key: (type, required). "url" is an https URL string.
SCHEMA = {
    "teamID": ("team", True),
    "store": ({
        "name": ("str", True),
        "url": ("url", True),
        "publicKey": ("key", False),
        "publisher": ("str", True),
        "repository": ("url", False),
        "website": ("url", False),
        "authSecret": ("secret", False),
    }, True),
    "allowUserStores": ("bool", True),
    "updates": ({
        "feed": ("url", False),
        "betaFeed": ("url", False),
        "manualNote": ("str", True),
    }, True),
    "links": ({
        "website": ("url", False),
        "permissionsHelp": ("url", False),
        "repository": ("url", True),
    }, True),
}


def fail(message):
    sys.exit(f"distribution: {message}")


def merge(base, override, path=""):
    if not isinstance(override, dict):
        fail(f"{path or 'the override'} must be an object")
    result = dict(base)
    for key, value in override.items():
        if isinstance(result.get(key), dict) and isinstance(value, dict):
            result[key] = merge(result[key], value, f"{path}{key}.")
        else:
            result[key] = value
    return result


def check(value, schema, path=""):
    for key in value:
        if key not in schema:
            fail(f"unknown key {path}{key}")
    for key, (kind, required) in schema.items():
        name = f"{path}{key}"
        item = value.get(key)
        if item is None:
            if required:
                fail(f"{name} is required")
            continue
        if isinstance(kind, dict):
            if not isinstance(item, dict):
                fail(f"{name} must be an object")
            check(item, kind, name + ".")
        elif kind == "bool":
            if not isinstance(item, bool):
                fail(f"{name} must be true or false")
        elif not isinstance(item, str) or not item.strip():
            fail(f"{name} must be a non-empty string")
        elif kind == "url" and not re.match(r"^https://[^\s/]+", item):
            fail(f"{name} must be an https URL: {item}")
        elif kind == "team" and not re.fullmatch(r"[A-Z0-9]{10}", item):
            fail(f"{name} must be a 10-character Apple team id: {item}")
        elif kind == "secret" and not re.fullmatch(r"[A-Z][A-Z0-9_]*", item):
            fail(f"{name} must be a secret name like COMPANY_STORE_TOKEN: {item}")
        elif kind == "key":
            try:
                raw = base64.b64decode(item, validate=True)
            except ValueError:
                raw = b""
            if len(raw) != 32:
                fail(f"{name} must be a base64 Ed25519 public key (stackbarctl keygen prints one)")


def load(override=OVERRIDE):
    value = json.loads(BASE.read_text())
    if override.exists():
        try:
            value = merge(value, json.loads(override.read_text()))
        except json.JSONDecodeError as error:
            fail(f"{override.name}: {error}")
    check(value, SCHEMA)
    return value


def app_group(value):
    return f"{value['teamID']}.{BUNDLE_ID}"


def get(value, path):
    if path == "appGroup":
        return app_group(value)
    for part in path.split("."):
        if not isinstance(value, dict) or part not in value:
            fail(f"no key {path}")
        value = value[part]
    return value


def write_plist(value, path):
    with open(path, "rb") as file:
        info = plistlib.load(file)
    info[INFO_KEY] = json.dumps(value, separators=(",", ":"), sort_keys=True)
    # Sparkle's feed. Without one the release must not carry a key either, so
    # the app never checks (release.sh leaves SUPublicEDKey out).
    if "SUFeedURL" in info or info.get("CFBundlePackageType") == "APPL":
        feed = value["updates"].get("feed")
        if feed:
            info["SUFeedURL"] = feed
        else:
            info.pop("SUFeedURL", None)
            info.pop("SUPublicEDKey", None)
    with open(path, "wb") as file:
        plistlib.dump(info, file)


def write_entitlements(value, path):
    with open(path, "rb") as file:
        entitlements = plistlib.load(file)
    entitlements["com.apple.security.application-groups"] = [app_group(value)]
    with open(path, "wb") as file:
        plistlib.dump(entitlements, file)


def main(argv):
    override = OVERRIDE
    if len(argv) > 2 and argv[1] == "--override":
        override = pathlib.Path(argv[2])
        argv = argv[:1] + argv[3:]
    if len(argv) < 2:
        sys.exit(__doc__)
    value = load(override)
    command, rest = argv[1], argv[2:]
    if command == "show":
        print(json.dumps(value, indent=2))
    elif command == "get" and len(rest) == 1:
        item = get(value, rest[0])
        print("" if item is None else json.dumps(item) if isinstance(item, bool) else item)
    elif command == "plist" and rest:
        for path in rest:
            write_plist(value, path)
    elif command == "entitlements" and rest:
        for path in rest:
            write_entitlements(value, path)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
