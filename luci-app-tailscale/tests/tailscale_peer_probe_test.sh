#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HELPER="$ROOT_DIR/root/usr/sbin/tailscale_peer_probe"
TMP_DIR="${TMPDIR:-/tmp}/tailscale-peer-probe-test.$$"

cleanup() {
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

assert_contains() {
	needle="$1"
	haystack="$2"
	case "$haystack" in
		*"${needle}"*) ;;
		*) fail "expected output to contain: $needle
actual: $haystack" ;;
	esac
}

assert_not_contains() {
	needle="$1"
	haystack="$2"
	case "$haystack" in
		*"${needle}"*) fail "expected output not to contain: $needle
actual: $haystack" ;;
	esac
}

assert_valid_json() {
	output="$1"
	if command -v node >/dev/null 2>&1; then
		printf '%s' "$output" | node -e 'let s = ""; process.stdin.on("data", c => s += c); process.stdin.on("end", () => { JSON.parse(s); });' \
			|| fail "expected valid JSON, actual: $output"
	fi
}

mkdir -p "$TMP_DIR"

cat >"$TMP_DIR/fake-tailscale" <<'SH'
#!/bin/sh
	case "$*" in
		"ping --c=1 --timeout=2s direct-peer")
			echo "pong from direct-peer (100.64.2.2) via 192.168.188.1:41641 in 12.4ms"
			exit 0
			;;
		"ping --c=1 --timeout=2s control-peer")
			printf 'pong from control-peer (100.64.2.3) via 192.168.188.1:41641 in 15.0ms\n"quoted" line has \\backslash\\ and tab:\t with carriage:\rreturn'
			exit 0
			;;
		"ping --c=1 --timeout=2s derp-peer")
			echo "pong from derp-peer (100.64.2.1) via DERP(test-relay) in 41.8ms"
			exit 0
			;;
		"ping --c=1 --timeout=2s derp-no-direct-peer")
			echo "pong from derp-no-direct-peer (100.64.2.6) via DERP(test-relay) in 67ms"
			echo "direct connection not established"
			exit 1
			;;
	"ping --c=1 --timeout=2s weird-peer")
		echo "pong from weird-peer using new format"
		exit 0
		;;
	"ping --c=1 --timeout=2s failed-peer")
		echo 'ping "100.64.2.6" timed out' >&2
		echo "no reply" >&2
		exit 1
		;;
	*)
		echo "unexpected fake tailscale args: $*" >&2
		exit 99
		;;
esac
SH
chmod +x "$TMP_DIR/fake-tailscale"

run_probe() {
	TAILSCALE_BIN="$TMP_DIR/fake-tailscale" "$HELPER" "$@"
}

direct_output="$(run_probe direct-peer)"
assert_valid_json "$direct_output"
assert_contains '"peer":"direct-peer"' "$direct_output"
assert_contains '"ok":true' "$direct_output"
assert_contains '"path":"direct"' "$direct_output"
assert_contains '"latency_ms":12.4' "$direct_output"
assert_contains '"summary":"direct 12.4 ms"' "$direct_output"

derp_output="$(run_probe derp-peer)"
assert_valid_json "$derp_output"
assert_contains '"peer":"derp-peer"' "$derp_output"
assert_contains '"ok":true' "$derp_output"
assert_contains '"path":"derp"' "$derp_output"
assert_contains '"relay":"test-relay"' "$derp_output"
assert_contains '"latency_ms":41.8' "$derp_output"
assert_contains '"summary":"DERP test-relay 41.8 ms"' "$derp_output"

derp_no_direct_output="$(run_probe derp-no-direct-peer)"
assert_valid_json "$derp_no_direct_output"
assert_contains '"peer":"derp-no-direct-peer"' "$derp_no_direct_output"
assert_contains '"ok":true' "$derp_no_direct_output"
assert_contains '"path":"derp"' "$derp_no_direct_output"
assert_contains '"relay":"test-relay"' "$derp_no_direct_output"
assert_contains '"latency_ms":67' "$derp_no_direct_output"
assert_contains '"summary":"DERP test-relay 67 ms - direct connection not established"' "$derp_no_direct_output"

unknown_output="$(run_probe weird-peer)"
assert_valid_json "$unknown_output"
assert_contains '"peer":"weird-peer"' "$unknown_output"
assert_contains '"ok":true' "$unknown_output"
assert_contains '"path":"unknown"' "$unknown_output"
assert_contains '"summary":"unknown path"' "$unknown_output"

control_output="$(run_probe control-peer)"
assert_valid_json "$control_output"
assert_contains '"peer":"control-peer"' "$control_output"
assert_contains '"ok":true' "$control_output"
assert_contains '"path":"direct"' "$control_output"
assert_contains '"latency_ms":15.0' "$control_output"
assert_contains '"summary":"direct 15.0 ms"' "$control_output"
assert_contains '\"' "$control_output"
assert_contains '\\' "$control_output"
assert_contains '\t' "$control_output"
assert_contains '\r' "$control_output"
assert_contains '\n' "$control_output"

control_output_lines="$(printf '%s\n' "$control_output" | wc -l | tr -d ' ')"
[ "$control_output_lines" -eq 1 ] || fail "expected control peer output to be single-line JSON: $control_output"

failed_output="$(run_probe failed-peer || true)"
assert_valid_json "$failed_output"
assert_contains '"peer":"failed-peer"' "$failed_output"
assert_contains '"ok":false' "$failed_output"
assert_contains '"path":"failed"' "$failed_output"
assert_contains '"summary":"tailscale ping failed"' "$failed_output"

invalid_output="$(run_probe 'bad peer;rm -rf /' || true)"
assert_valid_json "$invalid_output"
assert_contains '"ok":false' "$invalid_output"
assert_contains '"path":"failed"' "$invalid_output"
assert_contains '"summary":"invalid peer argument"' "$invalid_output"
assert_not_contains 'rm -rf' "$invalid_output"

missing_arg_output="$("$HELPER" || true)"
assert_valid_json "$missing_arg_output"
assert_contains '"ok":false' "$missing_arg_output"
assert_contains '"summary":"usage: tailscale_peer_probe <peer>"' "$missing_arg_output"

echo "tailscale_peer_probe tests passed"
