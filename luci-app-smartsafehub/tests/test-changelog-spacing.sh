#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT_DIR/CHANGELOG.md" <<'PYTEST'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
releases = [index for index, line in enumerate(lines) if line.startswith("## [")]
if len(releases) < 2:
    raise SystemExit("FAIL: CHANGELOG must contain multiple releases")

for index in releases[1:]:
    previous = index - 1
    while previous >= 0 and not lines[previous].strip():
        if lines[previous]:
            raise SystemExit(f"FAIL: whitespace-only line before release at {index + 1}")
        previous -= 1
    blank_lines = index - previous - 1
    if blank_lines != 2:
        raise SystemExit(
            f"FAIL: release at line {index + 1} has {blank_lines} blank lines; expected 2"
        )

print(f"PASS: {len(releases)} CHANGELOG releases have two blank lines between entries")
PYTEST
