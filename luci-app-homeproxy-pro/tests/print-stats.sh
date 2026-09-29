#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Single source for the test statistics README.md quotes.
#
#   sh tests/print-stats.sh
#
# The README used to restate the numbers by hand, so they drifted the moment a
# guard, a check or a test file was added: the architecture row still said
# "34 guards / 125 checks / 74 files" while the tree had 35 / 126 / 75, and the
# frontend-validator count was one short after a validator was added.  This
# script measures them instead, and the README cites it.
#
#   guards      guard sections in tests/arch-guard.sh
#   checks      the total arch-guard.sh counts and prints at the end of its run
#   test_files  files under tests/, excluding the gitignored .DS_Store
#
# `checks` costs one guard run: it is computed while the guards execute, so
# there is no cheaper honest way to report it. The run is pure shell/python
# (no ucode, no node) and takes well under a second. The guard's exit status is
# propagated, so a failing guard is never reported as a green statistic.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

GUARDS="$(grep -c '^echo "== guard ' "$ROOT/tests/arch-guard.sh")"

GUARD_OUT="$(sh "$ROOT/tests/arch-guard.sh" "$ROOT" 2>&1)"
GUARD_STATUS=$?
CHECKS="$(printf '%s\n' "$GUARD_OUT" | sed -n 's/^\([0-9][0-9]*\) checks, .*/\1/p' | tail -1)"

# find, not `git ls-files tests`: the count must be the same before and after
# the commit that adds a test file, and it must survive a tarball checkout.
# Excluding .DS_Store keeps it equal to `git ls-files tests | wc -l` in this
# tree (the file is gitignored but every macOS listing has one).
TEST_FILES="$(find "$ROOT/tests" -type f -not -name '.DS_Store' | grep -c .)"

printf 'guards=%s\n' "$GUARDS"
printf 'checks=%s\n' "$CHECKS"
printf 'test_files=%s\n' "$TEST_FILES"

if [ "$GUARD_STATUS" -ne 0 ]; then
	echo "warning: arch-guard.sh exited $GUARD_STATUS - the counts above come from a failing run" >&2
fi

exit "$GUARD_STATUS"
