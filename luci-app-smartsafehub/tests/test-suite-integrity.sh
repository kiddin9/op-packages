#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
# Run the checker and its mutation regressions even before ShellSpec is installed.
exec python3 "$ROOT_DIR/tools/check_test_coverage.py" --self-test
