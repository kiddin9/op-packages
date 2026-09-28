#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/root/usr/sbin/tailscale_keepalive"
INIT_SCRIPT="$ROOT_DIR/root/etc/init.d/tailscale"
TMP_DIR="${TMPDIR:-/tmp}/tailscale-keepalive-test.$$"
STATUS_FILE="$TMP_DIR/status.json"

cleanup() {
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TMP_DIR"

cat >"$TMP_DIR/jshn.sh" <<'SH'
json_cleanup() {
	JSHN_LEVEL=
	JSHN_PEER=
}

json_load() {
	JSHN_JSON="$1"
	printf 'load\n' >>"${JSHN_TRACE:?}"
}

json_select() {
	printf 'select %s\n' "$1" >>"${JSHN_TRACE:?}"
	case "$1:$JSHN_LEVEL" in
		Peer:)
			JSHN_LEVEL=Peer
			;;
		TailscaleIPs:peer)
			JSHN_LEVEL=ips
			;;
		..:ips)
			JSHN_LEVEL=peer
			;;
		..:peer)
			JSHN_LEVEL=Peer
			JSHN_PEER=
			;;
		*:Peer)
			JSHN_PEER="$1"
			JSHN_LEVEL=peer
			;;
		*)
			return 1
			;;
	esac
}

json_get_keys() {
	values="$(printf '%s' "$JSHN_JSON" | "${REAL_JQ:?}" -r '.Peer | keys[]')"
	eval "$1=\$values"
	printf 'get_keys\n' >>"${JSHN_TRACE:?}"
}

json_get_var() {
	value="$(printf '%s' "$JSHN_JSON" | "${REAL_JQ:?}" -r --arg peer "$JSHN_PEER" --arg field "$2" '.Peer[$peer][$field] // ""')"
	eval "$1=\$value"
	printf 'get_var %s\n' "$2" >>"${JSHN_TRACE:?}"
}

json_get_values() {
	values="$(printf '%s' "$JSHN_JSON" | "${REAL_JQ:?}" -r --arg peer "$JSHN_PEER" '.Peer[$peer].TailscaleIPs[]?')"
	eval "$1=\$values"
	printf 'get_values\n' >>"${JSHN_TRACE:?}"
}
SH

cat >"$TMP_DIR/python3" <<'SH'
#!/bin/sh
printf 'python fallback invoked\n' >>"${PYTHON_TRACE:?}"
exit 1
SH
chmod +x "$TMP_DIR/python3"

REAL_JQ="${REAL_JQ:-$(command -v jq)}"
JSHN_TRACE="$TMP_DIR/jshn.trace"
PYTHON_TRACE="$TMP_DIR/python.trace"
: >"$JSHN_TRACE"
: >"$PYTHON_TRACE"
export REAL_JQ JSHN_TRACE PYTHON_TRACE

cat >"$STATUS_FILE" <<'JSON'
{
  "Peer": {
    "nodekey:one": {
      "HostName": "site-a-openwrt",
      "DNSName": "site-a-openwrt.example.tailnet.",
      "TailscaleIPs": [
        "100.64.100.2",
        "fd7a:115c:a1e0::2"
      ]
    },
    "nodekey:two": {
      "HostName": "site-b-gateway",
      "DNSName": "site-b-gateway.example.tailnet.",
      "TailscaleIPs": [
        "100.64.100.1"
      ]
    },
    "nodekey:three": {
      "HostName": "no-ip-peer",
      "DNSName": "no-ip-peer.example.ts.net.",
      "TailscaleIPs": []
    },
    "nodekey:four": {
      "HostName": "",
      "DNSName": "",
      "TailscaleIPs": [
        "100.64.100.44"
      ]
    }
  }
}
JSON

output="$(PATH="$TMP_DIR:$PATH" JSHN_LIB="$TMP_DIR/jshn.sh" TAILSCALE_STATUS_FILE="$STATUS_FILE" "$SCRIPT" --resolve-peers \
		site-a-openwrt \
		site-b-gateway.example.tailnet \
		100.64.100.2 \
		100.64.100.44 \
		missing-peer \
		no-ip-peer)"

expected="$(printf '%s\t%s\t%s\n%s\t%s\t%s\n%s\t%s\t%s\n%s\t%s\t%s\n%s\t%s\t%s\n%s\t%s\t%s' \
	site-a-openwrt OK 100.64.100.2 \
	site-b-gateway.example.tailnet OK 100.64.100.1 \
	100.64.100.2 OK 100.64.100.2 \
	100.64.100.44 OK 100.64.100.44 \
	missing-peer NOT_FOUND '' \
	no-ip-peer NO_IP '')"

if [ "$output" != "$expected" ]; then
	printf 'unexpected resolver output\nexpected:\n%s\nactual:\n%s\n' "$expected" "$output" >&2
	exit 1
fi

grep -F 'select Peer' "$JSHN_TRACE" >/dev/null || {
	printf 'expected production jshn resolver path to select Peer\n' >&2
	exit 1
}
grep -F 'get_values' "$JSHN_TRACE" >/dev/null || {
	printf 'expected production jshn resolver path to read TailscaleIPs\n' >&2
	exit 1
}
[ ! -s "$PYTHON_TRACE" ] || {
	printf 'jshn resolver unexpectedly fell back to Python:\n' >&2
	cat "$PYTHON_TRACE" >&2
	exit 1
}
rm -f "$TMP_DIR/python3"

cat >"$STATUS_FILE" <<'JSON'
{"Peer":{"nodekey:one":{"TailscaleIPs":["100.64.100.9"],"DNSName":"compact-peer.example.tailnet.","HostName":"compact-peer"},"nodekey:two":{"DNSName":"reordered.example.tailnet.","HostName":"reordered-peer","Online":true,"TailscaleIPs":["100.64.100.10"]}}}
JSON

output="$(TAILSCALE_STATUS_FILE="$STATUS_FILE" "$SCRIPT" --resolve-peers \
		compact-peer \
		reordered.example.tailnet)"

expected="$(printf '%s\t%s\t%s\n%s\t%s\t%s' \
	compact-peer OK 100.64.100.9 \
	reordered.example.tailnet OK 100.64.100.10)"

if [ "$output" != "$expected" ]; then
	printf 'unexpected compact resolver output\nexpected:\n%s\nactual:\n%s\n' "$expected" "$output" >&2
	exit 1
fi

cat >"$TMP_DIR/logger" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$LOGGER_OUTPUT"
SH
chmod +x "$TMP_DIR/logger"

LOGGER_OUTPUT="$TMP_DIR/logger.out"
PATH="$TMP_DIR:$PATH"
export LOGGER_OUTPUT PATH

(
	config_get_bool() {
		eval "$1=1"
	}

	config_get() {
		case "$3" in
			keepalive_peers) eval "$1=" ;;
			keepalive_interval) eval "$1=20" ;;
			keepalive_failure_log_interval) eval "$1=300" ;;
			log_stdout|log_stderr) eval "$1=0" ;;
			*) eval "$1=" ;;
		esac
	}

	procd_open_instance() { :; }
	procd_set_param() { :; }
	procd_append_param() { :; }
	procd_close_instance() { :; }

	. "$INIT_SCRIPT"
	tailscale_keepalive cfg
)

if ! grep -q 'keepalive enabled but no peers configured' "$LOGGER_OUTPUT"; then
	printf 'expected init script to log empty keepalive peers\n' >&2
	exit 1
fi

printf 'tailscale_keepalive resolver tests passed\n'
