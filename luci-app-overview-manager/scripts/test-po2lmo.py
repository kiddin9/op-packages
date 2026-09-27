#!/usr/bin/env python3
"""Tests for the LMO compiler and the translation catalogs.

The hash vectors are pinned against the upstream po2lmo binary built from
luci-base. Set PO2LMO_REFERENCE to a real po2lmo executable to additionally
diff the compiled output byte for byte.
"""

import os
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from po2lmo import compile_po, sfh_hash  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
LANGUAGES = ["ru"]

# Verified against sfh_hash() from luci-base/src/lib/lmo.c. The browser side
# computes the same values in sfh() from luci-base/htdocs/.../cbi.js.
HASH_VECTORS = {
    "": 0x00000000,
    "a": 0x115EA782,
    "ab": 0x516B8B44,
    "abc": 0xD2BE198A,
    "abcd": 0xDAD8B8DB,
    "Show": 0x49D1A0A4,
    "Save layout": 0x18762B08,
    "Saving…": 0x7A938C83,
    "Переместить вверх": 0x669DABB0,
    "ctx\1key": 0x999A0ABE,
}


def fail(message):
    print(f"test-po2lmo: {message}", file=sys.stderr)
    sys.exit(1)


def check(condition, message):
    if not condition:
        fail(message)


def read_lmo(payload):
    """Decode an LMO archive the way lmo.c reads it: {key_id: value}."""
    (blob_size,) = struct.unpack(">I", payload[-4:])
    index = payload[blob_size:-4]
    check(len(index) % 16 == 0, "index size is not a multiple of the entry size")

    catalog = {}
    previous = None
    for offset in range(0, len(index), 16):
        key_id, val_id, value_offset, length = struct.unpack(
            ">IIII", index[offset:offset + 16]
        )
        check(
            previous is None or key_id >= previous,
            "index is not sorted by key_id",
        )
        previous = key_id
        check(
            value_offset + length <= blob_size,
            f"entry {key_id:08x} points outside the string blob",
        )
        catalog[key_id] = payload[value_offset:value_offset + length].decode()
    return catalog


def trimws(value):
    """The normalisation _() applies before hashing, from cbi.js."""
    return re.sub(r"[ \t\n]+", " ", value.strip())


def parse_po(path):
    """Return {msgid: msgstr} for the simple single-form records we ship."""
    entries = {}
    key = None
    field = None
    values = {"msgid": "", "msgstr": ""}

    def flush():
        if key:
            entries[key] = values["msgstr"]

    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("#") or not line:
            continue
        match = re.match(r'^(msgid|msgstr)\s+"(.*)"$', line)
        if match:
            if match.group(1) == "msgid":
                flush()
                values = {"msgid": match.group(2), "msgstr": ""}
                field = "msgid"
            else:
                field = "msgstr"
                values["msgstr"] = match.group(2)
            key = values["msgid"] or None
            continue
        match = re.match(r'^"(.*)"$', line)
        if match and field:
            values[field] += match.group(1)
            if field == "msgid":
                key = values["msgid"] or None
    flush()
    return entries


def source_strings():
    """Every literal passed to _() in the shipped JavaScript."""
    found = set()
    for path in sorted((ROOT / "luci").glob("*.js")):
        text = path.read_text(encoding="utf-8")
        for match in re.finditer(r"\b_\(\s*'((?:[^'\\]|\\.)*)'", text):
            found.add(match.group(1).replace("\\'", "'").replace("\\\\", "\\"))
    return found


def test_hash_vectors():
    for value, expected in HASH_VECTORS.items():
        actual = sfh_hash(value.encode())
        check(
            actual == expected,
            f"sfh_hash({value!r}) = {actual:08x}, expected {expected:08x}",
        )


def test_empty_catalog():
    header = 'msgid ""\nmsgstr "Content-Type: text/plain; charset=UTF-8\\n"\n'
    check(
        compile_po(header) is None,
        "a catalog without translations must not produce a file",
    )


def test_identical_translation_omitted():
    payload = compile_po('msgid "same"\nmsgstr "same"\n')
    check(
        payload is None,
        "a translation identical to its source must be omitted",
    )


def test_plural_forms_recorded():
    payload = compile_po(
        'msgid ""\nmsgstr ""\n'
        '"Plural-Forms: nplurals=2; plural=(n != 1);\\n"\n'
    )
    check(payload is not None, "the plural formula must be compiled")
    catalog = read_lmo(payload)
    check(
        catalog.get(0) == "nplurals=2; plural=(n != 1);",
        f"unexpected plural formula entry: {catalog.get(0)!r}",
    )


def test_catalogs_round_trip():
    """Every translation must be reachable through the hash _() computes."""
    for language in LANGUAGES:
        path = ROOT / "po" / language / "overview-manager.po"
        entries = parse_po(path)
        check(bool(entries), f"{path} has no translations")

        payload = compile_po(path.read_text(encoding="utf-8"))
        check(payload is not None, f"{path} compiled to an empty catalog")
        catalog = read_lmo(payload)

        for msgid, msgstr in entries.items():
            check(
                msgid == trimws(msgid),
                f"{path}: msgid is not whitespace-normalised: {msgid!r}",
            )
            if msgid == msgstr:
                continue
            key = sfh_hash(trimws(msgid).encode())
            check(
                catalog.get(key) == msgstr,
                f"{path}: {msgid!r} resolves to {catalog.get(key)!r}, "
                f"expected {msgstr!r}",
            )


def test_catalogs_cover_sources():
    used = source_strings()
    check(bool(used), "no _() strings were found in the sources")

    template = parse_po(ROOT / "po" / "templates" / "overview-manager.pot")
    check(
        set(template) == used,
        "po/templates/overview-manager.pot is out of sync with the sources; "
        f"only in template: {sorted(set(template) - used)}; "
        f"only in sources: {sorted(used - set(template))}",
    )
    check(
        not any(template.values()),
        "the template must not carry translations",
    )

    for language in LANGUAGES:
        path = ROOT / "po" / language / "overview-manager.po"
        entries = parse_po(path)
        check(
            set(entries) == used,
            f"{path} is out of sync with the sources; "
            f"only in catalog: {sorted(set(entries) - used)}; "
            f"only in sources: {sorted(used - set(entries))}",
        )
        for msgid, msgstr in entries.items():
            check(msgstr != "", f"{path}: {msgid!r} is untranslated")


def test_languages_registered():
    """Every shipped catalog needs a display name in the uci-defaults script.

    LuCI only offers languages listed in luci.languages, so a catalog with no
    entry there can never be selected.
    """
    script = (
        ROOT / "openwrt" / "files" / "etc" / "uci-defaults"
        / "luci-app-overview-manager"
    ).read_text(encoding="utf-8")

    for language in LANGUAGES:
        check(
            re.search(rf"^\s*{re.escape(language)}\)\s", script, re.MULTILINE),
            f"{language} has no display name in the uci-defaults script",
        )


def test_reference_binary():
    reference = os.environ.get("PO2LMO_REFERENCE")
    if not reference:
        print("test-po2lmo: PO2LMO_REFERENCE not set, skipping oracle diff")
        return

    for language in LANGUAGES:
        source = ROOT / "po" / language / "overview-manager.po"
        with tempfile.TemporaryDirectory() as directory:
            expected = Path(directory) / "reference.lmo"
            subprocess.run(
                [reference, str(source), str(expected)], check=True
            )
            check(
                expected.read_bytes()
                == compile_po(source.read_text(encoding="utf-8")),
                f"{source}: output differs from {reference}",
            )
    print("test-po2lmo: output matches the reference po2lmo binary")


def main():
    test_hash_vectors()
    test_empty_catalog()
    test_identical_translation_omitted()
    test_plural_forms_recorded()
    test_catalogs_round_trip()
    test_catalogs_cover_sources()
    test_languages_registered()
    test_reference_binary()
    print("po2lmo tests OK")


if __name__ == "__main__":
    main()
