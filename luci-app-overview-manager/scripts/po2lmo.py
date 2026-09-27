#!/usr/bin/env python3
"""Compile a gettext PO catalog into LuCI's LMO format.

This is a byte-for-byte reimplementation of po2lmo from luci-base. Both package
build paths use it so the SDK-less IPK and the SDK-built APK ship identical
catalogs and neither depends on the LuCI feed host tools being available.

The reference implementation is modules/luci-base/src/po2lmo.c; the reader that
consumes the output is modules/luci-base/src/lib/lmo.c. scripts/test-po2lmo.py
pins the behaviour with known-answer tests and can diff against the real
po2lmo binary when one is available.
"""

import os
import struct
import sys

MASK = 0xFFFFFFFF


def sfh_hash(data):
    """Paul Hsieh's SuperFastHash, seeded with the length as lmo.c does."""
    length = len(data)
    if length <= 0:
        return 0

    def u16(offset):
        return data[offset] | (data[offset + 1] << 8)

    def s8(offset):
        value = data[offset]
        return value - 256 if value > 127 else value

    hash_value = length
    rem = length & 3
    offset = 0

    for _ in range(length >> 2):
        hash_value = (hash_value + u16(offset)) & MASK
        tmp = ((u16(offset + 2) << 11) ^ hash_value) & MASK
        hash_value = ((hash_value << 16) ^ tmp) & MASK
        hash_value = (hash_value + (hash_value >> 11)) & MASK
        offset += 4

    if rem == 3:
        hash_value = (hash_value + u16(offset)) & MASK
        hash_value = (hash_value ^ (hash_value << 16)) & MASK
        hash_value = (hash_value ^ ((s8(offset + 2) << 18) & MASK)) & MASK
        hash_value = (hash_value + (hash_value >> 11)) & MASK
    elif rem == 2:
        hash_value = (hash_value + u16(offset)) & MASK
        hash_value = (hash_value ^ (hash_value << 11)) & MASK
        hash_value = (hash_value + (hash_value >> 17)) & MASK
    elif rem == 1:
        hash_value = (hash_value + s8(offset)) & MASK
        hash_value = (hash_value ^ (hash_value << 10)) & MASK
        hash_value = (hash_value + (hash_value >> 1)) & MASK

    hash_value = (hash_value ^ (hash_value << 3)) & MASK
    hash_value = (hash_value + (hash_value >> 5)) & MASK
    hash_value = (hash_value ^ (hash_value << 4)) & MASK
    hash_value = (hash_value + (hash_value >> 17)) & MASK
    hash_value = (hash_value ^ (hash_value << 25)) & MASK
    hash_value = (hash_value + (hash_value >> 6)) & MASK
    return hash_value


def extract_string(line):
    """Return the quoted payload of a PO line, or None when there is none.

    Like the C original this only unescapes \\" and \\\\. Every other escape,
    \\n included, is kept verbatim as backslash plus character, which is what
    makes the PO header parse below work on literal "\\n" separators.
    """
    if line.startswith("#"):
        return None

    out = []
    escaped = False
    started = False

    for char in line:
        if not started:
            if char == '"':
                started = True
            continue
        if escaped:
            if char not in ('"', "\\"):
                out.append("\\")
            out.append(char)
            escaped = False
        elif char == "\\":
            escaped = True
        elif char != '"':
            out.append(char)
        else:
            break

    return "".join(out) if started else None


class Message:
    """One PO record, mirroring struct msg in po2lmo.c."""

    def __init__(self):
        self.reset()

    def reset(self):
        self.plural_num = -1
        self.ctxt = None
        self.msgid = None
        self.id_plural = None
        self.values = [None] * 10
        self.current = None

    def append(self, text):
        if self.current is None:
            return
        field, index = self.current
        if field == "values":
            self.values[index] = (self.values[index] or "") + text
        else:
            setattr(self, field, (getattr(self, field) or "") + text)


class Catalog:
    """Accumulates the string blob and the index of an LMO archive."""

    def __init__(self):
        self.blob = bytearray()
        self.entries = []

    def _write(self, payload):
        offset = len(self.blob)
        self.blob += payload
        # Every blob is padded to a 4-byte boundary, as print() does in C.
        self.blob += b"\0" * ((4 - (len(payload) % 4)) % 4)
        return offset

    def add(self, key, value, plural_count):
        key_id = sfh_hash(key)
        # Identical hashes mean the string is its own translation; the C tool
        # drops those entries so the reader falls back to the source string.
        if key_id == sfh_hash(value):
            return
        offset = self._write(value)
        self.entries.append((key_id, plural_count, offset, len(value)))

    def add_plural_forms(self, formula):
        offset = self._write(formula)
        self.entries.append((0, 0, offset, len(formula)))

    def serialize(self):
        if not self.blob:
            return None
        out = bytearray(self.blob)
        # Stable sort by key_id keeps the output deterministic where the C
        # qsort would leave the order of equal keys unspecified.
        for entry in sorted(self.entries, key=lambda item: item[0]):
            out += struct.pack(">IIII", *entry)
        out += struct.pack(">I", len(self.blob))
        return bytes(out)


def add_message(catalog, msg):
    """Emit one PO record, mirroring print_msg() in po2lmo.c."""
    if msg.msgid is not None and msg.values[0] is not None:
        for index in range(msg.plural_num + 1):
            value = msg.values[index]
            if value is None:
                continue
            if msg.ctxt is not None and msg.id_plural is not None:
                key = f"{msg.ctxt}\1{msg.msgid}\2{index}"
            elif msg.ctxt is not None:
                key = f"{msg.ctxt}\1{msg.msgid}"
            elif msg.id_plural is not None:
                key = f"{msg.msgid}\2{index}"
            else:
                key = msg.msgid
            catalog.add(
                key.encode(), value.encode(), msg.plural_num + 1
            )
    elif msg.values[0] is not None:
        # The header record carries the plural formula. Fields are separated by
        # literal "\n" two-character sequences left in place by extract_string,
        # and a formula on an unterminated last line is ignored upstream too.
        header = msg.values[0]
        for field in header.split("\\n")[:-1]:
            if field[:14].lower() == "plural-forms: ":
                catalog.add_plural_forms(field[14:].encode())
                break
    msg.reset()


def compile_po(text):
    catalog = Catalog()
    msg = Message()

    for line in text.splitlines() + [None]:
        eof = line is None

        if not eof and line.startswith('msgctxt "'):
            if msg.msgid is not None or msg.values[0] is not None:
                add_message(catalog, msg)
            msg.ctxt = None
            msg.current = ("ctxt", 0)
        elif eof or line.startswith('msgid "'):
            if msg.msgid is not None or msg.values[0] is not None:
                add_message(catalog, msg)
            msg.msgid = None
            msg.current = ("msgid", 0)
        elif line.startswith('msgid_plural "'):
            msg.id_plural = None
            msg.current = ("id_plural", 0)
        elif line.startswith('msgstr "') or line.startswith("msgstr["):
            if line.startswith("msgstr["):
                msg.plural_num = int(line[7:].split("]")[0])
            else:
                msg.plural_num = 0
            if msg.plural_num >= 10:
                raise SystemExit("po2lmo: too many plural forms")
            msg.values[msg.plural_num] = None
            msg.current = ("values", msg.plural_num)

        if eof:
            break

        text_part = extract_string(line)
        if text_part:
            msg.append(text_part)

    return catalog.serialize()


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: po2lmo.py input.po output.lmo")

    source, target = sys.argv[1:]
    with open(source, encoding="utf-8") as handle:
        payload = compile_po(handle.read())

    # An empty catalog produces no file at all, matching the C tool.
    if payload is None:
        if os.path.exists(target):
            os.unlink(target)
        return

    with open(target, "wb") as handle:
        handle.write(payload)


if __name__ == "__main__":
    main()
