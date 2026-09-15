#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2025 ImmortalWrt.org
#
# Report how much of the gettext template (po/templates/homeproxy.pot) is
# translated in po/zh_Hans/homeproxy.po. Missing, empty and fuzzy entries all
# count as untranslated. The check only warns by default so it does not block
# a build; pass --fail-below to turn the warning into a failure.
#
# Usage:
#   tests/i18n-coverage.py                       # warn below 95%
#   tests/i18n-coverage.py --warn-below 90
#   tests/i18n-coverage.py --fail-below 95
#   tests/i18n-coverage.py --list 20

import argparse
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE = os.path.join(ROOT, "po/templates/homeproxy.pot")
TRANSLATION = os.path.join(ROOT, "po/zh_Hans/homeproxy.po")
IGNORE = os.path.join(ROOT, "tests/i18n-ignore.txt")


def load_ignore(path):
    """msgids that are deliberately not translated (technical tokens)."""
    if not os.path.exists(path):
        return set()
    ignored = set()
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if line and not line.startswith("#"):
                ignored.add(line)
    return ignored


def unquote(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        return value[1:-1]
    return value


def parse_po(path):
    """Return {msgid: {'msgstr': str, 'fuzzy': bool}} for non-empty msgids."""
    entries = {}
    msgid = None
    msgstr = ""
    state = None
    pending_fuzzy = False
    entry_fuzzy = False

    def flush():
        if msgid:
            entries[msgid] = {"msgstr": msgstr, "fuzzy": entry_fuzzy}

    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.rstrip("\n")

            if line.startswith("#,"):
                if "fuzzy" in line:
                    pending_fuzzy = True
                continue

            if line.startswith("#"):
                continue

            if line.startswith("msgid "):
                flush()
                msgid = unquote(line[len("msgid "):])
                msgstr = ""
                entry_fuzzy = pending_fuzzy
                pending_fuzzy = False
                state = "msgid"
            elif line.startswith("msgstr "):
                msgstr = unquote(line[len("msgstr "):])
                state = "msgstr"
            elif line.startswith('"'):
                if state == "msgid":
                    msgid += unquote(line)
                elif state == "msgstr":
                    msgstr += unquote(line)

    flush()
    return entries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--warn-below", type=float, default=100.0,
                        help="warn when coverage is below this percentage (default: 100)")
    parser.add_argument("--fail-below", type=float, default=None,
                        help="exit non-zero when coverage is below this percentage")
    parser.add_argument("--list", type=int, default=10,
                        help="list at most this many untranslated entries (default: 10)")
    args = parser.parse_args()

    template = parse_po(TEMPLATE)
    translation = parse_po(TRANSLATION)
    ignored = load_ignore(IGNORE)

    total = 0
    untranslated = []
    for msgid in template:
        if msgid in ignored:
            continue
        total += 1
        entry = translation.get(msgid)
        if not entry or entry["fuzzy"] or not entry["msgstr"].strip():
            untranslated.append(msgid)

    translated = total - len(untranslated)
    coverage = (translated / total * 100) if total else 100.0

    print(f"zh_Hans translation coverage: {translated}/{total} ({coverage:.1f}%)"
          f", {len(ignored)} msgid(s) ignored by tests/i18n-ignore.txt")

    if untranslated and args.list:
        print(f"{len(untranslated)} untranslated entries, first {min(args.list, len(untranslated))}:")
        for msgid in untranslated[:args.list]:
            print(f"  - {msgid}")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write("## zh_Hans translation coverage\n\n")
            handle.write(f"**{translated}/{total} ({coverage:.1f}%)** — "
                         f"{len(untranslated)} untranslated entry/entries.\n\n")
            if untranslated:
                handle.write("<details><summary>Untranslated</summary>\n\n")
                for msgid in untranslated:
                    handle.write(f"- `{msgid}`\n")
                handle.write("\n</details>\n")

    if args.fail_below is not None and coverage < args.fail_below:
        print(f"::error title=Translation coverage::zh_Hans coverage {coverage:.1f}% "
              f"is below {args.fail_below}%")
        return 1

    if coverage < args.warn_below:
        print(f"::warning title=Translation coverage::zh_Hans coverage {coverage:.1f}% "
              f"is below {args.warn_below}% ({len(untranslated)} untranslated entry/entries)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
