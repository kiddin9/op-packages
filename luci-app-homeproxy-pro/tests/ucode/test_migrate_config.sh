#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Stage PHASE 9 close-out item: migrate_config.uc has never had a
# direct test. The migration runs on every UCI commit and was only
# ever exercised by full upgrade tests on a target, so a developer
# could break a step and never see it fail.
#
# The runner stages a sandboxed UCI dir with a file that needs every
# migration step it can see at once:
#
#   infra.china_dns_port            -> deleted (chinadns-ng removed)
#   config.china_dns_server         -> 'wan_114' mapped to 114.114.114.114
#   infra.github_token              -> moved to config
#   infra.ntp_server                -> defaulted to 'nil'
#   infra.tun_gso                   -> deleted (sb 1.11)
#   config.routing_port='all'       -> deleted
#   dns.default_server='block-dns'  -> 'default-dns' + final-block rule
#   dns.independent_cache           -> deleted (sb 1.14)
#   dns.cache_file_store_rdrc       -> renamed to cache_file_store_dns
#   dns.cache_file_rdrc_timeout     -> deleted
#   dns_server.address (legacy)     -> split into type/server/server_port
#   dns_server.strategy/client_subnet -> moved to the referencing rule
#   dns_server.address='rcode://x'  -> predefined rcode rule
#   dns_rule.server='block-dns'     -> action='reject'
#   dns_rule.rule_set_ipcidr_match_source -> renamed (sb 1.10)
#   routing_rule.outbound='block-out'     -> action='reject' (sb 1.11)
#   server.auto_firewall='1'        -> per-server firewall='1'
#   server.sniff_override           -> deleted (sb 1.11)
#
# The cursor override flows through HP_MIGRATE_UCI_DIR (see the
# comment at the top of migrate_config.uc); production keeps the
# default cursor() because the global is unset there.
#
# Usage: sh tests/ucode/test_migrate_config.sh <repo-root> [work-dir]

ROOT="${1:-.}"
WORK="${2:-/tmp/hp-migrate-test}"

ROOT="$(cd "$ROOT" && pwd)"
FAILED=0

SANDBOX="$WORK/sandbox"
STAGE="$WORK/scripts"

rm -rf "$WORK"
mkdir -p "$SANDBOX" "$STAGE"

# cursor(dir) reads <dir>/homeproxy-pro directly (NOT <dir>/config/homeproxy-pro).
cat > "$SANDBOX/homeproxy-pro" <<'EOF'
config homeproxy-pro 'config'
	option log_level ''
	option china_dns_server 'wan_114'
	option routing_port 'all'
config homeproxy-pro 'infra'
	option self_mark '100'
	option china_dns_port '5354'
	option github_token 'secret'
config homeproxy-pro 'dns'
	option default_server 'block-dns'
	option independent_cache '1'
	option cache_file_store_rdrc '1'
	option cache_file_rdrc_timeout '60'
config homeproxy-pro 'server'
	option auto_firewall '1'
config dns_server 'ds_default'
	option address 'tls://1.1.1.1:853'
	option strategy 'prefer_ipv4'
	option client_subnet '1.2.3.0/24'
config dns_server 'ds_rcode'
	option address 'rcode://name_error'
config dns_rule 'dr_block'
	option server 'block-dns'
config dns_rule 'dr_uses_default'
	option server 'ds_default'
config dns_rule 'dr_stale'
	option rule_set_ipcidr_match_source '1'
config routing_rule 'rr_block'
	option outbound 'block-out'
config server 'srv_one'
	option type 'shadowsocks'
	option sniff_override '1'
EOF

# Stage the mock homeproxy-pro + migrate_config.uc + test driver next to
# each other so the bare-name imports resolve through -L.
#
# migrate_config.uc runs at import time and writes through a UCI
# cursor that defaults to /etc/config. The test must not touch the
# real UCI tree, so the staged *copy* is rewritten to take the
# sandbox dir from ARGV[0]. Production source keeps the plain
# cursor() call - the project moved away from test seams in
# production code when HP_TEST_HOOK was removed, and re-adding one
# would go backwards.
cp "$ROOT/tests/ucode/mocks/homeproxy-pro.uc" "$STAGE/"
cp "$ROOT/root/etc/homeproxy-pro/scripts/migrate_config.uc" "$STAGE/"
cp "$ROOT/tests/ucode/test_migrate_config.uc" "$STAGE/"

# The shebang is dropped in the staged copy: migrate_config.uc is a
# program in production (`ucode -S .../migrate_config.uc`, where the
# shebang is fine), but this test *imports* it, and the target ucode
# rejects a `#!` line in a module ("Unexpected character" at line 1,
# followed by cascading lexer errors).
# The crontab path is a literal in the source (/etc/crontabs/root).  Point the
# staged copy at the sandbox too, or the run would edit the device's real
# crontab - the migration is supposed to do that once on a real upgrade, but a
# test must not.
sed -e '1{/^#!\/usr\/bin\/ucode$/d;}' \
	-e 's|^const uci = cursor();$|const uci = cursor(ARGV[0]);|' \
	-e "s|'/etc/crontabs/root'|'$SANDBOX/crontab'|" \
	"$STAGE/migrate_config.uc" > "$STAGE/migrate_config.uc.new"

# Hard guard: if an anchor ever stops matching (someone reformats the
# line), the sed silently no-ops. Losing the cursor redirect would make the
# migration run against the real /etc/config - which on a target would
# rewrite the live configuration; losing the shebang strip means the module
# cannot be imported at all. Refuse to run instead.
if ! grep -q 'cursor(ARGV\[0\])' "$STAGE/migrate_config.uc.new"; then
	echo "FAIL: migrate_config regressions: could not redirect the UCI cursor"
	echo "      (the 'const uci = cursor();' anchor no longer matches)"
	exit 1
fi
if head -1 "$STAGE/migrate_config.uc.new" | grep -q '^#!'; then
	echo "FAIL: migrate_config regressions: the shebang was not stripped"
	echo "      (the '#!/usr/bin/ucode' anchor no longer matches)"
	exit 1
fi
if ! grep -q "'$SANDBOX/crontab'" "$STAGE/migrate_config.uc.new"; then
	echo "FAIL: migrate_config regressions: could not redirect the crontab path"
	echo "      (the \"'/etc/crontabs/root'\" anchor no longer matches)"
	exit 1
fi

# A crontab that still carries the legacy entry, plus one line that must
# survive.  The migration has to remove exactly the former.
cat > "$SANDBOX/crontab" <<'CRONTAB'
0 3 * * * /etc/homeproxy-pro/scripts/update_crond.sh
*/5 * * * * /usr/bin/echo keep-me
CRONTAB
mv "$STAGE/migrate_config.uc.new" "$STAGE/migrate_config.uc"

if ( cd "$STAGE" && ucode -L "$STAGE" test_migrate_config.uc "$SANDBOX" ); then
	echo "PASS: migrate_config regressions"
else
	echo "FAIL: migrate_config regressions"
	FAILED=1
fi

# The crontab cleanup, asserted from the shell so the .uc test does not have to
# know about files.  The old form ran `sed -i ... 2>/dev/null`, so on a host
# whose sed has no bare -i (BSD) it failed silently and left the entry behind -
# and the marker was set anyway, so the migration never retried.
if grep -q 'update_crond.sh' "$SANDBOX/crontab"; then
	echo "FAIL: migrate_config regressions: the legacy update_crond.sh crontab entry survived"
	grep -n 'update_crond.sh' "$SANDBOX/crontab" | head -2
	FAILED=1
fi

if ! grep -q 'keep-me' "$SANDBOX/crontab"; then
	echo "FAIL: migrate_config regressions: the crontab rewrite dropped an unrelated line"
	cat "$SANDBOX/crontab"
	FAILED=1
fi

if ! grep -q "option crontab '1'" "$SANDBOX/homeproxy-pro"; then
	echo "FAIL: migrate_config regressions: the crontab marker was not set after a successful edit"
	FAILED=1
fi

exit $FAILED
