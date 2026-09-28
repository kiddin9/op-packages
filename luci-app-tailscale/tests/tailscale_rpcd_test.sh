#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
RPCD_SCRIPT="$ROOT_DIR/root/usr/libexec/rpcd/luci.tailscale"
TMP_DIR="${TMPDIR:-/tmp}/tailscale-rpcd-test.$$"

cleanup() {
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

mkdir -p "$TMP_DIR"

REAL_JQ="$(command -v jq)"
export REAL_JQ
cat >"$TMP_DIR/jq-no-regex" <<'SH'
#!/bin/sh
filter=
skip=0
for arg do
	if [ "$skip" -gt 0 ]; then
		skip=$((skip - 1))
		continue
	fi
	[ -z "$filter" ] || continue
	case "$arg" in
	--arg|--argjson|--argfile|--slurpfile|--rawfile) skip=2 ;;
	-*) ;;
	*) filter="$arg" ;;
	esac
done
normalized_filter="$(printf '%s' "$filter" | tr '\n\r\t' '   ')"
if printf '%s\n' "$normalized_filter" |
	grep -Eq '(^|[^[:alnum:]_])(test|match|sub|gsub)[[:space:]]*\('; then
	printf '%s\n' 'jq regex functions are unavailable on the target OpenWrt build' >&2
	exit 3
fi
exec "${REAL_JQ:?}" "$@"
SH
chmod +x "$TMP_DIR/jq-no-regex"
export JQ_BIN="$TMP_DIR/jq-no-regex"

if "$TMP_DIR/jq-no-regex" -n '"x" | test
("x")' >/dev/null 2>&1; then
	fail "target jq shim must reject regex functions split across whitespace"
fi

cat >"$TMP_DIR/secrets" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${SECRETS_ARGV_LOG:?}"
case "${1:-}" in
	has)
		case "${2:-}" in
			authkey|adguard_password) exit 0 ;;
		esac
		;;
	matches-adguard)
		[ "${2:-}" = 'http://saved.example:3000' ] && [ "${3:-}" = 'saved-user' ]
		;;
	stage-batch)
		cat >"${SECRETS_STDIN_LOG:?}"
		printf '%s\n' 'staged-ref'
		;;
	migrate) ;;
	*) exit 1 ;;
esac
SH
chmod +x "$TMP_DIR/secrets"

cat >"$TMP_DIR/preflight" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >"${PREFLIGHT_ARGV_LOG:?}"
{
	printf 'candidate=%s\n' "${TAILSCALE_ADGUARD_PREFLIGHT_CANDIDATE:-}"
	printf 'api_url=%s\n' "${TAILSCALE_ADGUARD_PREFLIGHT_API_URL:-}"
	printf 'username=%s\n' "${TAILSCALE_ADGUARD_PREFLIGHT_USERNAME:-}"
	printf 'password_set=%s\n' "${TAILSCALE_ADGUARD_PREFLIGHT_PASSWORD_SET:-}"
	printf 'password=%s\n' "${TAILSCALE_ADGUARD_PREFLIGHT_PASSWORD:-}"
	printf 'default_upstreams=%s\n' "${TAILSCALE_ADGUARD_PREFLIGHT_DEFAULT_UPSTREAMS:-}"
	printf 'tailnet_upstreams=%s\n' "${TAILSCALE_ADGUARD_PREFLIGHT_TAILNET_UPSTREAMS:-}"
	printf 'health_domain=%s\n' "${TAILSCALE_ADGUARD_PREFLIGHT_HEALTH_DOMAIN:-}"
	printf 'expected_ips=%s\n' "${TAILSCALE_ADGUARD_PREFLIGHT_EXPECTED_IPS:-}"
} >"${PREFLIGHT_ENV_LOG:?}"
printf 'adguard_process=pass\nhealth_check=pass\nready=pass\n'
SH
chmod +x "$TMP_DIR/preflight"

cat >"$TMP_DIR/openclash-helper" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >"${OPENCLASH_HELPER_ARGV_LOG:?}"
case "${OPENCLASH_HELPER_MODE:-success}" in
	success)
		printf '%s\n' '{"state":"active","rules_present":4,"detail":"helper status"}'
		;;
	fail)
		printf '%s\n' 'partial helper output'
		printf '%s\n' 'helper failed' >&2
		exit 7
		;;
	invalid)
		printf '%s\n' 'not JSON'
		;;
	esac
SH
chmod +x "$TMP_DIR/openclash-helper"

cat >"$TMP_DIR/policy-routing-helper" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >"${POLICY_ROUTING_HELPER_ARGV_LOG:?}"
case "${POLICY_ROUTING_HELPER_MODE:-success}" in
	success)
		printf '%s\n' '{"state":"active","enabled":true,"mwan3_present":true}'
		;;
	fail)
		printf '%s\n' 'partial helper output'
		printf '%s\n' 'helper failed' >&2
		exit 7
		;;
	invalid)
		printf '%s\n' 'not JSON'
		;;
esac
SH
chmod +x "$TMP_DIR/policy-routing-helper"

PREFLIGHT_ARGV_LOG="$TMP_DIR/argv.log"
PREFLIGHT_ENV_LOG="$TMP_DIR/env.log"
SECRETS_ARGV_LOG="$TMP_DIR/secrets-argv.log"
SECRETS_STDIN_LOG="$TMP_DIR/secrets-stdin.log"
OPENCLASH_HELPER_ARGV_LOG="$TMP_DIR/openclash-helper-argv.log"
POLICY_ROUTING_HELPER_ARGV_LOG="$TMP_DIR/policy-routing-helper-argv.log"
export PREFLIGHT_ARGV_LOG PREFLIGHT_ENV_LOG SECRETS_ARGV_LOG SECRETS_STDIN_LOG OPENCLASH_HELPER_ARGV_LOG POLICY_ROUTING_HELPER_ARGV_LOG
: >"$SECRETS_ARGV_LOG"
: >"$SECRETS_STDIN_LOG"

list_json="$(PRECHECK_BIN="$TMP_DIR/preflight" SECRETS_BIN="$TMP_DIR/secrets" "$RPCD_SCRIPT" list)"
printf '%s' "$list_json" | jq -e '.adguard_preflight.candidate == "" and .adguard_preflight.password == ""' >/dev/null || \
	fail "rpcd list output must declare the AdGuard preflight string arguments"
printf '%s' "$list_json" | jq -e '.secret_status == {} and (has("set_secret") | not) and .set_secrets.authkey_set == "" and .set_secrets.adguard_password_set == "" and .set_secrets.base_ref == ""' >/dev/null || \
	fail "rpcd list output must declare secret status and write methods"
printf '%s' "$list_json" | jq -e '.openclash_bypass_status == {}' >/dev/null || \
	fail "rpcd list output must declare the read-only OpenClash bypass status method"
printf '%s' "$list_json" | jq -e '.policy_routing_status == {}' >/dev/null || \
	fail "rpcd list output must declare the read-only policy-routing status method"

openclash_status_response="$(printf '%s\n' '{"ignored":"caller-controlled input"}' | OPENCLASH_BYPASS_BIN="$TMP_DIR/openclash-helper" \
	"$RPCD_SCRIPT" call openclash_bypass_status)"
printf '%s' "$openclash_status_response" | jq -e '.state == "active" and .rules_present == 4 and .detail == "helper status"' >/dev/null || \
	fail "rpcd must return the helper status object unchanged"
[ "$(cat "$OPENCLASH_HELPER_ARGV_LOG")" = "status" ] || \
	fail "rpcd must invoke the OpenClash helper with the fixed status argument only"

if openclash_failure_response="$(printf '%s\n' '{}' | OPENCLASH_HELPER_MODE=fail OPENCLASH_BYPASS_BIN="$TMP_DIR/openclash-helper" \
	"$RPCD_SCRIPT" call openclash_bypass_status 2>&1)"; then
	fail "rpcd must fail when the OpenClash helper exits nonzero"
fi
printf '%s' "$openclash_failure_response" | jq -e '.code == 2 and .ready == "fail" and (.error | type == "string")' >/dev/null || \
	fail "nonzero OpenClash helper exits must return controlled JSON errors"

if openclash_invalid_response="$(printf '%s\n' '{}' | OPENCLASH_HELPER_MODE=invalid OPENCLASH_BYPASS_BIN="$TMP_DIR/openclash-helper" \
	"$RPCD_SCRIPT" call openclash_bypass_status 2>&1)"; then
	fail "rpcd must fail when the OpenClash helper returns invalid JSON"
fi
printf '%s' "$openclash_invalid_response" | jq -e '.code == 2 and .ready == "fail" and (.error | type == "string")' >/dev/null || \
	fail "invalid OpenClash helper JSON must return controlled JSON errors"

policy_status_response="$(printf '%s\n' '{"ignored":"caller-controlled input"}' | POLICY_ROUTING_BIN="$TMP_DIR/policy-routing-helper" \
	"$RPCD_SCRIPT" call policy_routing_status)"
printf '%s' "$policy_status_response" | jq -e '.state == "active" and .enabled == true and .mwan3_present == true' >/dev/null || \
	fail "rpcd must return the policy-routing helper status object unchanged"
[ "$(cat "$POLICY_ROUTING_HELPER_ARGV_LOG")" = "status" ] || \
	fail "rpcd must invoke the policy-routing helper with the fixed status argument only"

if policy_failure_response="$(printf '%s\n' '{}' | POLICY_ROUTING_HELPER_MODE=fail POLICY_ROUTING_BIN="$TMP_DIR/policy-routing-helper" \
	"$RPCD_SCRIPT" call policy_routing_status 2>&1)"; then
	fail "rpcd must fail when the policy-routing helper exits nonzero"
fi
printf '%s' "$policy_failure_response" | jq -e '.code == 2 and .ready == "fail" and (.error | type == "string")' >/dev/null || \
	fail "nonzero policy-routing helper exits must return controlled JSON errors"

if policy_invalid_response="$(printf '%s\n' '{}' | POLICY_ROUTING_HELPER_MODE=invalid POLICY_ROUTING_BIN="$TMP_DIR/policy-routing-helper" \
	"$RPCD_SCRIPT" call policy_routing_status 2>&1)"; then
	fail "rpcd must fail when the policy-routing helper returns invalid JSON"
fi
printf '%s' "$policy_invalid_response" | jq -e '.code == 2 and .ready == "fail" and (.error | type == "string")' >/dev/null || \
	fail "invalid policy-routing helper JSON must return controlled JSON errors"

status_response="$(printf '%s\n' '{}' | SECRETS_BIN="$TMP_DIR/secrets" "$RPCD_SCRIPT" call secret_status)"
printf '%s' "$status_response" | jq -e '.authkey_set == "1" and .adguard_password_set == "1"' >/dev/null || \
	fail "secret status must expose booleans without returning secret values"
grep -Fx 'migrate' "$SECRETS_ARGV_LOG" >/dev/null || fail "secret status must migrate readable legacy credentials before reporting status"

request='{"candidate":"1","api_url":"http://candidate.example:3000","username":"candidate-user","password_set":"1","password":"candidate-secret","default_upstreams":"1.1.1.1\\n8.8.8.8","tailnet_upstreams":"[/candidate.example/]100.100.100.100","health_domain":"candidate-health.example","expected_ips":"10.23.0.15\\n10.23.0.16"}'
response="$(printf '%s\n' "$request" | PRECHECK_BIN="$TMP_DIR/preflight" SECRETS_BIN="$TMP_DIR/secrets" "$RPCD_SCRIPT" call adguard_preflight)"

printf '%s' "$response" | jq -e '.ready == "pass" and .health_check == "pass" and .code == 0' >/dev/null || \
	fail "rpcd preflight must return the structured checker result"
[ "$(cat "$PREFLIGHT_ARGV_LOG")" = "--preflight" ] || fail "candidate values and credentials must not enter the checker argv"
grep -F 'candidate=1' "$PREFLIGHT_ENV_LOG" >/dev/null || fail "rpcd preflight must enable candidate mode"
grep -F 'api_url=http://candidate.example:3000' "$PREFLIGHT_ENV_LOG" >/dev/null || fail "rpcd preflight must pass the candidate API URL"
grep -F 'password=candidate-secret' "$PREFLIGHT_ENV_LOG" >/dev/null || fail "rpcd preflight must pass the candidate password through the child environment"
grep -F 'default_upstreams=1.1.1.1' "$PREFLIGHT_ENV_LOG" >/dev/null || fail "rpcd preflight must preserve candidate upstreams"

: >"$PREFLIGHT_ARGV_LOG"
reuse_request='{"candidate":"1","api_url":"http://attacker.example:3000","username":"saved-user","password_set":"0","password":"","default_upstreams":"1.1.1.1","tailnet_upstreams":"[/candidate.example/]100.100.100.100","health_domain":"candidate-health.example","expected_ips":"10.23.0.15"}'
if printf '%s\n' "$reuse_request" | PRECHECK_BIN="$TMP_DIR/preflight" SECRETS_BIN="$TMP_DIR/secrets" "$RPCD_SCRIPT" call adguard_preflight >/dev/null 2>&1; then
	fail "preflight must reject saved-password reuse for a different AdGuard endpoint"
fi
[ ! -s "$PREFLIGHT_ARGV_LOG" ] || fail "rejected credential reuse must not invoke the preflight checker"

: >"$PREFLIGHT_ARGV_LOG"
unsafe_request='{"candidate":"1","api_url":"file:///etc/shadow","username":"candidate-user","password_set":"1","password":"candidate-secret","default_upstreams":"1.1.1.1","tailnet_upstreams":"[/candidate.example/]100.100.100.100","health_domain":"candidate-health.example","expected_ips":"10.23.0.15"}'
if printf '%s\n' "$unsafe_request" | PRECHECK_BIN="$TMP_DIR/preflight" SECRETS_BIN="$TMP_DIR/secrets" "$RPCD_SCRIPT" call adguard_preflight >/dev/null 2>&1; then
	fail "preflight must reject non-HTTP AdGuard API URLs"
fi
[ ! -s "$PREFLIGHT_ARGV_LOG" ] || fail "rejected API schemes must not invoke the preflight checker"

: >"$SECRETS_ARGV_LOG"
: >"$SECRETS_STDIN_LOG"
batch_request='{"authkey_set":"1","authkey":"new-auth-key","adguard_password_set":"1","adguard_password":"new-batch-secret","api_url":"https://batch.example:3000","username":"batch-user","base_ref":"active-ref"}'
batch_response="$(printf '%s\n' "$batch_request" | SECRETS_BIN="$TMP_DIR/secrets" "$RPCD_SCRIPT" call set_secrets)"
[ "$(cat "$SECRETS_ARGV_LOG")" = "stage-batch active-ref" ] || fail "batch credential writes must stage one atomic secret version based on the current UCI reference"
printf '%s' "$(cat "$SECRETS_STDIN_LOG")" | jq -e '.authkey == "new-auth-key" and .adguard.password == "new-batch-secret" and .adguard.api_url == "https://batch.example:3000" and .adguard.username == "batch-user"' >/dev/null || \
	fail "batch credential writes must preserve both credentials and the AdGuard endpoint binding"
printf '%s' "$batch_response" | jq -e '.code == 0 and .ref == "staged-ref"' >/dev/null || \
	fail "batch credential staging must return the UCI version reference without activating it"

for invalid_ref_request in \
	'{"authkey_set":"1","authkey":"new-auth-key","adguard_password_set":"0","adguard_password":"","api_url":"","username":"","base_ref":"active-ref\n\n"}' \
	'{"authkey_set":"1","authkey":"new-auth-key","adguard_password_set":"0","adguard_password":"","api_url":"","username":"","base_ref":"active-ref\u0000"}'
do
	: >"$SECRETS_ARGV_LOG"
	if printf '%s\n' "$invalid_ref_request" | SECRETS_BIN="$TMP_DIR/secrets" "$RPCD_SCRIPT" call set_secrets >/dev/null 2>&1; then
		fail "credential batch RPC must reject control characters in base_ref"
	fi
	[ ! -s "$SECRETS_ARGV_LOG" ] || fail "invalid base_ref must not reach the protected credential helper"
done

legacy_set_request='{"name":"adguard_password","value":"new-secret","api_url":"http://new.example:3000","username":"new-user"}'
if printf '%s\n' "$legacy_set_request" | SECRETS_BIN="$TMP_DIR/secrets" "$RPCD_SCRIPT" call set_secret >/dev/null 2>&1; then
	fail "the non-transactional legacy secret write RPC must fail closed"
fi

printf '%s\n' '{}' | PRECHECK_BIN="$TMP_DIR/preflight" SECRETS_BIN="$TMP_DIR/secrets" "$RPCD_SCRIPT" call unknown >/dev/null 2>&1 && \
	fail "unknown rpcd methods must fail closed"

echo "tailscale rpcd tests passed"
