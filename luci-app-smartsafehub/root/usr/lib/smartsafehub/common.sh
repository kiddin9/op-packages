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
