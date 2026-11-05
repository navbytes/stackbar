#!/usr/bin/env python3
"""Sparkle's appcast for one release, and the key it is checked with.

    appcast.py write --zip Stackbar-0.23.0.zip --version 0.23.0 --signature <base64> --out appcast.xml
    appcast.py notes --version 0.23.0     prints that version's CHANGELOG section

The signature is Sparkle's EdDSA (Ed25519) signature of the zip, from
`swift scripts/ed25519.swift sign` (CryptoKit). This script only writes XML,
with the standard library. The Release workflow publishes appcast.xml next to
the zip; SUFeedURL points at releases/latest/download/appcast.xml, so
pre-releases never reach it.
"""

import argparse
import base64
import email.utils
import html
import re
import sys
from pathlib import Path

REPO = "navbytes/stackbar"
MINIMUM_MACOS = "26.0"
ROOT = Path(__file__).resolve().parent.parent




def changelog_section(version):
    """The lines under `## <version>` in CHANGELOG.md, up to the next `## `."""
    text = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    match = re.search(rf"^## {re.escape(version)}\b[^\n]*\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    return match.group(1).strip() if match else ""


def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    return re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)", r'<a href="\2">\1</a>', text)


def to_html(markdown):
    """Enough Markdown for a changelog: ### headings, - bullets, paragraphs."""
    out, in_list = [], False
    for line in markdown.splitlines():
        stripped = line.strip()
        bullet = re.match(r"^[-*] (.*)", stripped)
        if bullet:
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{inline(bullet.group(1))}</li>")
            continue
        if in_list:
            out.append("</ul>")
            in_list = False
        if stripped.startswith("### "):
            out.append(f"<h3>{inline(stripped[4:])}</h3>")
        elif stripped:
            out.append(f"<p>{inline(stripped)}</p>")
    if in_list:
        out.append("</ul>")
    return "\n".join(out)


def write(args):
    archive = Path(args.zip).read_bytes()
    signature = args.signature.strip()
    if len(base64.b64decode(signature, validate=True)) != 64:
        sys.exit("appcast: --signature is not an Ed25519 signature")
    version = args.version
    url = f"https://github.com/{REPO}/releases/download/v{version}/{Path(args.zip).name}"
    notes = to_html(changelog_section(version)) or f'<p><a href="https://github.com/{REPO}/releases/tag/v{version}">Release notes</a></p>'
    xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Stackbar</title>
    <link>https://github.com/{REPO}/releases/latest/download/appcast.xml</link>
    <item>
      <title>Stackbar {version}</title>
      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{version}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{MINIMUM_MACOS}</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/{REPO}/releases/tag/v{version}</sparkle:fullReleaseNotesLink>
      <description><![CDATA[{notes}]]></description>
      <enclosure url="{url}" length="{len(archive)}" type="application/octet-stream" sparkle:edSignature="{signature}"/>
    </item>
  </channel>
</rss>
"""
    Path(args.out).write_text(xml, encoding="utf-8")
    print(args.out)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    writer = commands.add_parser("write")
    writer.add_argument("--zip", required=True)
    writer.add_argument("--version", required=True)
    writer.add_argument("--signature", required=True)
    writer.add_argument("--out", required=True)
    notes = commands.add_parser("notes")
    notes.add_argument("--version", required=True)
    args = parser.parse_args()
    if args.command == "notes":
        print(changelog_section(args.version))
    else:
        write(args)


if __name__ == "__main__":
    main()
