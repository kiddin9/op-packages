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
# A template that parses to fewer than MIN_TOTAL non-ignored entries is a hard
# failure regardless of flags: an empty or truncated .pot makes every
# percentage meaningless, and a coverage number must not be allowed to report
# 100% for a translation set that covers nothing.
#
# Two defects are hard failures whatever the flags say, because neither shows
# up in the percentage: a msgstr whose placeholders do not match its msgid, and
# a msgstr that repeats a 20+ character run of itself.
#
# Usage:
#   tests/i18n-coverage.py                       # warn below 95%
#   tests/i18n-coverage.py --warn-below 90
#   tests/i18n-coverage.py --fail-below 95
#   tests/i18n-coverage.py --list 20

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE = os.path.join(ROOT, "po/templates/homeproxy.pot")
TRANSLATION = os.path.join(ROOT, "po/zh_Hans/homeproxy.po")
IGNORE = os.path.join(ROOT, "tests/i18n-ignore.txt")

# The .pot is generated from the shipped sources and currently parses to 737
# non-empty msgid entries, of which tests/i18n-ignore.txt exempts enough to
# leave 729 checked.  400 is a deliberately low floor - a bit over half the
# current corpus - chosen to catch an empty or truncated template without
# failing on a legitimate future removal of some strings.  0 must never be
# accepted: `translated / total` used to fall back to 100% when total was 0,
# so a wiped .pot passed both --warn-below 100 and --fail-below 100.
MIN_TOTAL = 400

# A translation that says the same thing twice (the TUIC entry shipped with the
# whole sentence in two half-translations) is invisible to the coverage
# percentage - the msgstr is neither empty nor fuzzy - and to the placeholder
# check - the conversions still match.  Any run of DUPLICATE_MIN characters
# that occurs twice inside one msgstr fails the check, whatever --fail-below
# says.
#
# Exclusion rule (why the markup-heavy entries in this catalogue do not trip
# it): LuCI strings mix prose with HTML, so a *correct* translation can repeat
# a structural run many times, e.g. the default-rule entry carries
# "</code> &&<br/><code>(port || port_range)" three times over.  Those tags are
# template scaffolding, not translated wording, so every <...> tag is stripped
# before the scan.  A duplicated clause keeps far more than 20 characters of
# real text after stripping, while the longest structural run above collapses
# to ") &&(" - below the threshold.  Without the strip that entry would be a
# false positive.
DUPLICATE_MIN = 20
TAG_RE = re.compile(r"<[^>]*>")


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


def placeholder_counts(text):
    """How many %s/%d/%j conversions a string carries.

    LuCI's String.format() silently substitutes an empty string for a missing
    argument, so a translation with extra placeholders renders an empty
    <code></code> and one with too few drops whatever the source interpolated.
    Neither shows up in the coverage percentage - only the presence and the
    completeness of the msgstr are checked - which is how two zh_Hans entries
    shipped with four placeholders against a two-placeholder msgid."""
    return len(re.findall(r"%(?:[sdj])", text))


def find_repeats(text, minimum=DUPLICATE_MIN):
    """Repeated runs of >= minimum characters inside one translated string.

    Returns a list of (start, length, fragment) triplets, longest run first,
    with overlapping reports of the same run collapsed into one.  HTML tags are
    stripped first (see DUPLICATE_MIN above for why)."""
    text = TAG_RE.sub("", text)
    length = len(text)
    if length < minimum * 2:
        return []

    hits = []
    seen = {}
    for index in range(length - minimum + 1):
        gram = text[index:index + minimum]
        first = seen.setdefault(gram, index)
        if first == index:
            continue
        # Grow the match in both directions so the reported fragment is the
        # maximal repeated run rather than the first 20-character window.
        end = minimum
        while (index + end < length and first + end < length
               and text[first + end] == text[index + end]):
            end += 1
        back = 0
        while (index - back > 0 and first - back > 0
               and text[first - back - 1] == text[index - back - 1]):
            back += 1
        hits.append((first - back, index - back, end + back,
                     text[first - back:first - back + end + back]))

    hits.sort(key=lambda hit: (-hit[2], hit[0], hit[1]))
    kept = []
    for hit in hits:
        if any(hit[0] >= other[0] and hit[0] < other[0] + other[2] for other in kept):
            continue
        kept.append(hit)
    return kept


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

    # A translated string has to keep the msgid's placeholders: the count, not
    # the letters around them. Checked on its own so a bad translation cannot
    # hide behind a 100% coverage number.
    mismatched = []
    for msgid, entry in translation.items():
        if msgid not in template or entry["fuzzy"] or not entry["msgstr"].strip():
            continue
        want, got = placeholder_counts(msgid), placeholder_counts(entry["msgstr"])
        if want != got:
            mismatched.append((msgid, want, got))

    translated = total - len(untranslated)
    coverage = (translated / total * 100) if total else 100.0

    print(f"zh_Hans translation coverage: {translated}/{total} ({coverage:.1f}%)"
          f", {len(ignored)} msgid(s) ignored by tests/i18n-ignore.txt")

    if mismatched:
        print(f"::error title=Translation placeholders::{len(mismatched)} translated"
              f" string(s) do not carry the same number of %s/%d/%j conversions as"
              f" their msgid - LuCI's format() renders an empty fragment for a"
              f" missing argument and drops the extra ones")
        for msgid, want, got in mismatched[:args.list]:
            print(f"  - msgid has {want}, msgstr has {got}: {msgid}")
        return 1

    # Same idea as the placeholder check: a msgstr that repeats itself counts
    # as translated, so only this scan can catch it. Hard failure, not tied to
    # --fail-below.
    duplicated = []
    for msgid, entry in translation.items():
        if entry["fuzzy"] or not entry["msgstr"].strip():
            continue
        for _start, length, _second, fragment in find_repeats(entry["msgstr"]):
            duplicated.append((msgid, length, fragment))

    if duplicated:
        print(f"::error title=Duplicate translation::{len(duplicated)} msgstr(s)"
              f" repeat a run of {DUPLICATE_MIN}+ characters inside themselves -"
              f" the entry looks translated but ships the same wording twice")
        for msgid, length, fragment in duplicated[:args.list]:
            print(f"  - {length} chars repeated: {fragment!r} in: {msgid}")
        return 1

    # A denominator below the floor means the template is empty or truncated,
    # not that the translation is perfect. Fail hard whatever the flags say;
    # this is a template-integrity check, not a coverage threshold.
    if total < MIN_TOTAL:
        print(f"::error title=Translation coverage::the gettext template parsed"
              f" to only {total} non-ignored msgid(s), below the {MIN_TOTAL}"
              f" floor - the .pot is empty or truncated, so {coverage:.1f}%"
              f" coverage is meaningless")
        return 1

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
        # --warn-below is advisory on purpose (build.yml records the number
        # instead of gating a release on it), so the message must say out loud
        # that this did not fail anything; otherwise a red annotation reads
        # like a gate that the exit status contradicts.
        print(f"::warning title=Translation coverage::zh_Hans coverage {coverage:.1f}% "
              f"is below {args.warn_below}% ({len(untranslated)} untranslated entry/entries)"
              f" - advisory only, this did NOT fail the build; use --fail-below"
              f" {args.warn_below:g} to make it a gate")

    return 0


if __name__ == "__main__":
    sys.exit(main())
