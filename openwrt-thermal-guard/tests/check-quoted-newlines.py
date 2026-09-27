#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Report quoted strings in shell files that contain a real line break.

A line end has to come from an escape (printf '%s\n'), not from the source
text: an editor or a CRLF checkout changes the latter without a trace, and
shellcheck does not look. Heredocs are skipped, and so are awk and sed
programs, whose text spans lines on purpose. In double quotes a break inside
$( ) does not count, that is a command spanning lines.

Usage: check-quoted-newlines.py FILE...   exit 1 when anything is found
       check-quoted-newlines.py --selftest
"""

import os
import re
import sys
import tempfile

HEREDOC = re.compile(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?")
PROGRAM = re.compile(r"\b(awk|sed)\b")
SUBST = re.compile(r"\$\((?:[^()]|\([^()]*\))*\)")


def closing_double(text, start):
    """Index of the double quote that ends the string opened before start."""
    i, depth = start, 0
    while i < len(text):
        c = text[i]
        if c == "\\":
            i += 2
            continue
        if text.startswith("$(", i):
            depth += 1
            i += 2
            continue
        if c == ")" and depth:
            depth -= 1
        elif c == '"' and not depth:
            return i
        i += 1
    return len(text)


def scan(path):
    """Yields (line, first characters) for every string with a line break."""
    text = open(path, encoding="utf-8").read()
    i, line, heredoc = 0, 1, None
    while i < len(text):
        c = text[i]
        if heredoc:
            end = text.find("\n", i)
            if end < 0:
                return
            if text[i:end].strip() == heredoc:
                heredoc = None
            i, line = end + 1, line + 1
            continue
        if c == "\n":
            i, line = i + 1, line + 1
            continue
        if c == "#" and (i == 0 or text[i - 1] in " \t\n;"):
            end = text.find("\n", i)
            i = len(text) if end < 0 else end
            continue
        match = HEREDOC.match(text, i)
        if match:
            heredoc = match.group(1)
            end = text.find("\n", i)
            i = len(text) if end < 0 else end
            continue
        if c == "\\":
            i += 2
            continue
        if c in "'\"":
            end = text.find("'", i + 1) if c == "'" else closing_double(text, i + 1)
            if end < 0:
                end = len(text)
            body = text[i + 1:end]
            before = text[text.rfind("\n", 0, i) + 1:i]
            flat = body if c == "'" else SUBST.sub("", body)
            if "\n" in flat and not (c == "'" and PROGRAM.search(before)):
                yield line, body[:40]
            i, line = end + 1, line + body.count("\n")
            continue
        i += 1


def check(paths):
    found = 0
    for path in paths:
        for line, head in scan(path):
            print(f"{path}:{line}: line break inside a quoted string: {head!r}")
            found += 1
    return found


def selftest():
    cases = {
        # These are Python strings: \\n puts the shell escape \n into the
        # planted file, a bare \n a real line break. Mixing them up tests the
        # opposite of what the name says.
        "printf with an escape": ("printf '%s=%s\\n' a b\n", 0),
        "printf with a real break": ("printf '%s=%s\n' a b\n", 1),
        "assignment": ('list="$list$t\n"\n', 1),
        "awk program": ("awk '\n{ print }\n' f\n", 0),
        "command spanning lines": ('x="$(grep -c \\\n\tfoo f)"\n', 0),
        "heredoc": ("cat <<'END'\nit's\nEND\n", 0),
        "comment": ("# don't\necho ok\n", 0),
    }
    fail = 0
    with tempfile.TemporaryDirectory() as tmp:
        for name, (text, want) in cases.items():
            path = os.path.join(tmp, "case.sh")
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
            got = len(list(scan(path)))
            ok = got == want
            fail |= not ok
            print(f"{'ok  ' if ok else 'FAIL'} {name}: {got} found, {want} expected")
    return fail


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        sys.exit(1 if selftest() else 0)
    if not sys.argv[1:]:
        print(__doc__.strip().splitlines()[-2], file=sys.stderr)
        sys.exit(2)
    sys.exit(1 if check(sys.argv[1:]) else 0)
