#!/bin/sh
# shellcheck shell=sh
set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TMPFILE="$(mktemp)"

cleanup() {
	rm -f "$TMPFILE"
}
trap cleanup EXIT HUP INT TERM

cd "$ROOT"

command -v shfmt >/dev/null 2>&1 || {
	echo "error: shfmt is required" >&2
	exit 127
}

command -v shellcheck >/dev/null 2>&1 || {
	echo "error: shellcheck is required" >&2
	exit 127
}

collect_file() {
	file="$1"
	[ -f "$file" ] || return 0

	case "$file" in
		spec/*_spec.sh)
			# ShellSpec DSL is valid shell syntax but is not supported by shfmt.
			return 0
			;;
		*.sh | */init.d/* | */uci-defaults/* | */hotplug.d/*)
			printf '%s\n' "$file" >>"$TMPFILE"
			return 0
			;;
	esac

	if head -n 1 "$file" 2>/dev/null | grep -Eq '^#!.*(sh|ash|bash)([[:space:]]|$)'; then
		printf '%s\n' "$file" >>"$TMPFILE"
	fi
}

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	git ls-files | while IFS= read -r file; do
		collect_file "$file"
	done
else
	find . -type f -print | sed 's#^\./##' | while IFS= read -r file; do
		collect_file "$file"
	done
fi

sort -u "$TMPFILE" -o "$TMPFILE"

if [ ! -s "$TMPFILE" ]; then
	echo "No shell files found."
	exit 0
fi

echo "Checking shell formatting with shfmt..."
xargs -r shfmt -d -ci <"$TMPFILE"

echo "Checking shell scripts with ShellCheck..."
xargs -r shellcheck -x -S warning <"$TMPFILE"

echo "Checking shell syntax..."
while IFS= read -r file; do
	sh -n "$file"
done <"$TMPFILE"

echo "Shell lint passed."
