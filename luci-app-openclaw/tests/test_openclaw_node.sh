#!/bin/sh
set -eu

. ./root/usr/libexec/openclaw-node.sh

fail() {
	echo "FAIL: $1" >&2
	exit 1
}

[ "$(oc_normalize_node_version v22.16.0)" = "22.16.0" ] || fail "normalize v"
oc_node_version_ge 22.16.0 22.16.0 || fail "exact version"
oc_node_version_ge 22.16.1 22.16.0 || fail "patch version"
oc_node_version_ge 23.0.0 22.16.0 || fail "major version"
if oc_node_version_ge 22.15.1 22.16.0; then
	fail "older minor accepted"
fi

echo "ok"
