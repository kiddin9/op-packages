#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

# Escape a shell string for use inside a JSON string literal.
# SmartSafeHub state/event payloads are single-line JSON, so CR/LF are
# normalized to spaces before escaping backslashes and double quotes.
json_escape() {
	printf '%s' "${1:-}" | tr '\r\n' '  ' | sed \
		-e 's/\\/\\\\/g' \
		-e 's/"/\\"/g'
}

# BusyBox tr builds used by some OpenWrt targets do not expand POSIX character
# classes such as [:lower:] / [:upper:] and can treat them as literal bytes.
# Use explicit ASCII alphabets for protocol/status tokens so, for example,
# `pro` always normalizes to `PRO` on every supported router.
ascii_upper() {
	printf '%s' "${1:-}" | tr 'abcdefghijklmnopqrstuvwxyz' 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
}

ascii_lower() {
	printf '%s' "${1:-}" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz'
}
