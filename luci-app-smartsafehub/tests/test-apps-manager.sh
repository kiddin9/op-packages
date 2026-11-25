#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
MANAGER="$ROOT/root/usr/libexec/smartsafehub-apps-manager"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail() { echo "FAIL: $*" >&2; exit 1; }
mkdir -p "$TMP/bin" "$TMP/runtime" "$TMP/owned" "$TMP/repo" "$TMP/overlay"
# A default OpenWrt BusyBox image does not provide od. Simulate that
# environment even if the developer workstation has GNU/coreutils od.
cat > "$TMP/bin/od" <<'SH_OD'
#!/bin/sh
exit 127
SH_OD
chmod +x "$TMP/bin/od"
PATH="$TMP/bin:$PATH"
export PATH
# Linux /proc is unavailable on macOS. A fixture keeps the production check enabled.
printf 'MemTotal:       262144 kB\n' > "$TMP/meminfo"
printf 'all\naarch64_cortex-a53\n' > "$TMP/apk-arch"
printf 'signed immutable package-index test fixture\n' > "$TMP/repo/packages.adb"
printf 'signed mock package payload\n' > "$TMP/repo/nlbwmon-2025.06.02~29236be6-r1.apk"
printf 'approved LuCI mock package payload\n' > "$TMP/repo/luci-app-nlbwmon-26.288.56989~75a306d.apk"
printf 'approved chart mock package payload\n' > "$TMP/repo/luci-lib-chartjs-26.288.56989~75a306d.apk"
printf 'approved Retro Arcade mock package payload\n' > "$TMP/repo/smartsafehub-app-retro-arcade-1.0.0-r1.apk"
printf 'approved etherwake mock package payload\n' > "$TMP/repo/etherwake-1.09-r5.apk"
printf 'approved WOL LuCI mock package payload\n' > "$TMP/repo/luci-app-wol-26.288.56989~75a306d.apk"
printf 'signed future dependency mock\n' > "$TMP/repo/new-signed-helper-1.0-r1.apk"
INDEX_SHA="$(sha256sum "$TMP/repo/packages.adb" | cut -d ' ' -f 1)"
ARCHIVE_SHA="$(sha256sum "$TMP/repo/nlbwmon-2025.06.02~29236be6-r1.apk" | cut -d ' ' -f 1)"
LUCISH="$(sha256sum "$TMP/repo/luci-app-nlbwmon-26.288.56989~75a306d.apk" | cut -d ' ' -f 1)"
CHARTSHA="$(sha256sum "$TMP/repo/luci-lib-chartjs-26.288.56989~75a306d.apk" | cut -d ' ' -f 1)"
RETROSHA="$(sha256sum "$TMP/repo/smartsafehub-app-retro-arcade-1.0.0-r1.apk" | cut -d ' ' -f 1)"
ETHERSHA="$(sha256sum "$TMP/repo/etherwake-1.09-r5.apk" | cut -d ' ' -f 1)"
WOLSHA="$(sha256sum "$TMP/repo/luci-app-wol-26.288.56989~75a306d.apk" | cut -d ' ' -f 1)"
HELPERSHA="$(sha256sum "$TMP/repo/new-signed-helper-1.0-r1.apk" | cut -d ' ' -f 1)"
cat > "$TMP/catalog.json" <<EOF
{"schema":1,"device_code":"iptime-ax3000sm","firmware_build_id":"mock-build-1","channel":"stable","apps":[{"id":"network-usage-monitor","version":"2025.06.02-r1","name":"네트워크 사용량 모니터","runtime":"router","installer":"apk","package_arch":"aarch64_cortex-a53","repository_release_id":"20261027T123000","repository_index_sha256":"$INDEX_SHA","packages":[{"name":"nlbwmon","version":"2025.06.02~29236be6-r1","sha256":"$ARCHIVE_SHA"},{"name":"luci-app-nlbwmon","version":"26.288.56989~75a306d","sha256":"$LUCISH"},{"name":"luci-lib-chartjs","version":"26.288.56989~75a306d","sha256":"$CHARTSHA"}],"requirements":{"min_memory_mb":1,"min_storage_mb":1}}]}
EOF
# Use jq when available for faster field lookups; the Python fallback is portable.
cat > "$TMP/bin/jsonfilter" <<'SH2'
#!/bin/sh
if command -v jq >/dev/null 2>&1; then
 file=''; expr=''
 while [ "$#" -gt 0 ]; do
  case "$1" in
   -i) file="$2"; shift 2;;
   -e) expr="$2"; shift 2;;
   *) exit 2;;
  esac
 done
 case "$expr" in
  '@.apps[*].id') jq_expr='.apps[].id';;
  @.*) jq_expr="${expr#@}";;
  *) exit 2;;
 esac
 jq -r "($jq_expr) | select(. != null)" "$file" 2>/dev/null
else
 exec python3 "$0.py" "$@"
fi
SH2
cat > "$TMP/bin/jsonfilter.py" <<'PY'
import json, re, sys
args=sys.argv
obj=json.load(open(args[args.index('-i')+1]))
expression=args[args.index('-e')+1]
if expression == '@.apps[*].id':
    for app in obj.get('apps',[]): print(app['id'])
else:
    try:
        for part in re.findall(r'[^.\[\]]+|\[\d+\]', expression[2:]):
            obj = obj[int(part[1:-1])] if part.startswith('[') else obj[part]
        if isinstance(obj,(str,int,float)): print(obj)
    except (KeyError,IndexError,TypeError): pass
PY
cat > "$TMP/bin/fetch-catalog" <<'SH2'
#!/bin/sh
cp "$APPS_TEST_CATALOG" "$SMARTSAFEHUB_APPS_RUNTIME_DIR/apps-catalog.json"
SH2
cat > "$TMP/bin/uclient-fetch" <<'SH2'
#!/bin/sh
while [ "$#" -gt 0 ]; do
 case "$1" in
 -O) dest="$2"; shift 2;;
 -q|-T) [ "$1" != -T ] || shift; shift;;
 *) url="$1"; shift;;
 esac
done
case "$url" in
 https://repo.smartsafehub.com/stable/packages/aarch64_cortex-a53/smartsafehub/20261027T123000/packages.adb|\
 https://repo.smartsafehub.com/stable/packages/mipsel_24kc/smartsafehub/20261027T123000/packages.adb)
   cp "$APPS_TEST_REPO/packages.adb" "$dest";;
 https://repo.smartsafehub.com/stable/packages/aarch64_cortex-a53/smartsafehub/20261027T123000/nlbwmon-2025.06.02~29236be6-r1.apk)
   cp "$APPS_TEST_REPO/nlbwmon-2025.06.02~29236be6-r1.apk" "$dest";;
 https://repo.smartsafehub.com/stable/packages/aarch64_cortex-a53/smartsafehub/20261027T123000/luci-app-nlbwmon-26.288.56989~75a306d.apk)
   cp "$APPS_TEST_REPO/luci-app-nlbwmon-26.288.56989~75a306d.apk" "$dest";;
 https://repo.smartsafehub.com/stable/packages/aarch64_cortex-a53/smartsafehub/20261027T123000/luci-lib-chartjs-26.288.56989~75a306d.apk)
   cp "$APPS_TEST_REPO/luci-lib-chartjs-26.288.56989~75a306d.apk" "$dest";;
 https://repo.smartsafehub.com/stable/packages/aarch64_cortex-a53/smartsafehub/20261027T123000/smartsafehub-app-retro-arcade-1.0.0-r1.apk)
   cp "$APPS_TEST_REPO/smartsafehub-app-retro-arcade-1.0.0-r1.apk" "$dest";;
 https://repo.smartsafehub.com/stable/packages/aarch64_cortex-a53/smartsafehub/20261027T123000/smartsafehub-app-retro-arcade-1.1.0-r1.apk)
   cp "$APPS_TEST_REPO/smartsafehub-app-retro-arcade-1.1.0-r1.apk" "$dest";;
 https://repo.smartsafehub.com/stable/packages/aarch64_cortex-a53/smartsafehub/20261027T123000/smartsafehub-app-retro-arcade-1.3.0-r6.apk)
   cp "$APPS_TEST_REPO/smartsafehub-app-retro-arcade-1.3.0-r6.apk" "$dest";;
 https://repo.smartsafehub.com/stable/packages/aarch64_cortex-a53/smartsafehub/20261027T123000/etherwake-1.09-r5.apk)
   cp "$APPS_TEST_REPO/etherwake-1.09-r5.apk" "$dest";;
 https://repo.smartsafehub.com/stable/packages/aarch64_cortex-a53/smartsafehub/20261027T123000/luci-app-wol-26.288.56989~75a306d.apk)
   cp "$APPS_TEST_REPO/luci-app-wol-26.288.56989~75a306d.apk" "$dest";;
 https://repo.smartsafehub.com/stable/packages/aarch64_cortex-a53/smartsafehub/20261027T123000/new-signed-helper-1.0-r1.apk)
   cp "$APPS_TEST_REPO/new-signed-helper-1.0-r1.apk" "$dest";;
 *) exit 2;;
esac
printf '%s\n' "$url" >> "$APPS_TEST_URL_LOG"
SH2
cat > "$TMP/bin/apk" <<'SH2'
#!/bin/sh
printf '%s\n' "$*" >> "$APPS_TEST_APK_LOG"
case "$1" in
 --print-arch) [ "${APPS_TEST_ARCH_CLI_FAIL:-0}" = 0 ] || exit 1; echo "${APPS_TEST_ARCH_CLI:-aarch64_cortex-a53}"; exit 0;;
 version)
   [ "$2" = -t ] || exit 2
   case "$3:$4" in
    1.0.0-r1:1.1.0-r1) echo '<';;
    1.1.0-r1:1.0.0-r1) echo '>';;
    1.2.0-r4:1.3.0-r4|1.2.0-r4:1.3.0-r6|1.3.0-r4:1.3.0-r6) echo '<';;
    1.3.0-r6:1.3.0-r4|1.3.0-r4:1.2.0-r4) echo '>';;
    *) [ "$3" = "$4" ] && echo '=' || exit 2;;
   esac
   exit 0;;
 info)
   if [ "$2" = -s ]; then
     shift 2
     [ "${APPS_TEST_SIZE_MISSING:-0}" = 0 ] || exit 2
     [ "$#" -eq 1 ] || exit 2
     [ "${APPS_TEST_SIZE_FULL_INFO_ONLY:-0}" = 0 ] || exit 2
     for name in "$@"; do
       grep -qxF "$name" "$APPS_TEST_INSTALLED" 2>/dev/null || exit 2
       [ "${APPS_TEST_SIZE_MISSING_PACKAGE:-}" != "$name" ] || exit 2
       # Device capture (OpenWrt 25.12 APK): repeating the same installed
       # size twice or three times is valid, but conflicting values are not.
       # During an update the APK index can expose old and new versions.
       # Only the installed version should determine the displayed size.
       if [ "${APPS_TEST_SIZE_MIXED_RELEASES:-0}" != 0 ] &&
          [ "$name" = smartsafehub-app-retro-arcade ]; then
         printf '%s-1.0.0-r1 installed size:\n1362 KiB\n\n' "$name"
         printf '%s-1.1.0-r1 installed size:\n2048 KiB\n\n' "$name"
         if [ "$APPS_TEST_SIZE_MIXED_RELEASES" = conflicting ]; then
           printf '%s-1.1.0-r1 installed size:\n2096 KiB\n\n' "$name"
         fi
         continue
       fi
       if [ "${APPS_TEST_SIZE_DEVICE_REPEAT:-0}" = 1 ]; then
         case "$name" in
          nlbwmon) version=2025.06.02~29236be6-r1; kib=46; copies=2;;
          luci-app-nlbwmon) version=26.288.56989~75a306d; kib=36; copies=3;;
          luci-lib-chartjs) version=26.288.56989~75a306d; kib=33; copies=3;;
          *) exit 2;;
         esac
         i=0
         while [ "$i" -lt "$copies" ]; do
           value="$kib"
           if [ "${APPS_TEST_SIZE_CONFLICTING_REPEAT:-0}" = 1 ] &&
              [ "$name" = nlbwmon ] && [ "$i" -eq 1 ]; then
             value=47
           fi
           printf '%s-%s installed size:\n%s KiB\n\n' "$name" "$version" "$value"
           i=$((i + 1))
         done
         continue
       fi
       if [ "${APPS_TEST_SIZE_INLINE:-0}" = 1 ]; then
         case "$name" in
          nlbwmon) printf '%s-1.0.0-r1 installed size: 1.5 MiB\n' "$name";;
          luci-app-nlbwmon) printf '%s-1.0.0-r1 installed size: 512KiB\n' "$name";;
          luci-lib-chartjs) printf '%s-1.0.0-r1 installed size: 256 KiB\n' "$name";;
          smartsafehub-app-retro-arcade) printf '%s-1.0.0-r1 installed size: 12.5 MiB\n' "$name";;
         esac
         continue
       fi
       printf '%s-1.0.0-r1 installed size:\n' "$name"
       if [ "${APPS_TEST_SIZE_INVALID:-0}" = 1 ]; then
         echo 'not-a-size'; continue
       fi
       case "$name" in
        nlbwmon) printf '1.5 MiB\n';;
        luci-app-nlbwmon) printf '512 KiB\n';;
        luci-lib-chartjs) printf '256 KiB\n';;
        smartsafehub-app-retro-arcade) printf '12.5 MiB\n';;
        *) printf '0 B\n';;
       esac
     done
     exit 0
   fi
   if [ "$#" -eq 2 ] && [ "${APPS_TEST_SIZE_FULL_INFO_ONLY:-0}" = 1 ]; then
     name="$2"
     grep -qxF "$name" "$APPS_TEST_INSTALLED" 2>/dev/null || exit 2
     printf '%s-1.0.0-r1 description:\nMock metadata\n\n%s-1.0.0-r1 installed size:\n' "$name" "$name"
     case "$name" in
       nlbwmon) printf '1.5 MiB\n';;
       luci-app-nlbwmon) printf '512 KiB\n';;
       luci-lib-chartjs) printf '256 KiB\n';;
       *) exit 2;;
     esac
     exit 0
   fi
   [ "$2" = -e ] || exit 2
   grep -qxF "$3" "$APPS_TEST_INSTALLED" 2>/dev/null; exit $?;;
 list)
   [ "$2" = -I ] || exit 2
   grep -qxF "$3" "$APPS_TEST_INSTALLED" 2>/dev/null || exit 0
   if [ -s "$APPS_TEST_VERSION_DB" ]; then
     version="$(awk -v n="$3" '$1 == n {print $2; exit}' "$APPS_TEST_VERSION_DB")"
     [ -z "$version" ] || { echo "$3-$version aarch64_cortex-a53 [installed]"; exit 0; }
   fi
   if [ "$3" = etherwake ]; then
     echo 'etherwake-1.09-r5 aarch64_cortex-a53 [installed]'
   else
     echo "$3-${APPS_TEST_SHARED_VERSION:-26.288.56989~75a306d} aarch64_cortex-a53 [installed]"
   fi
   exit 0;;
 --repositories-file)
   [ "$2" = /dev/null ] || exit 2
   [ "$3" = -X ] || exit 2
   case "$4" in
    file://*/apps-work.*/packages/packages.adb) repo=hub; local_index="${4#file://}";;
    *) exit 2;;
   esac
   [ -s "$local_index" ] || exit 2
   cmp -s "$local_index" "$APPS_TEST_REPO/packages.adb" || exit 2
   # The production adapter checks every approved hash. This fake index
   # permits any approved count so CI catches accidental fixed-size policies.
   [ "$(find "${local_index%/*}" -name '*.apk' | wc -l | tr -d ' ')" -gt 0 ] || exit 2
   if [ "$5" = update ]; then
     if [ "${APPS_TEST_REPO_UPDATE_FAIL:-0}" = 1 ]; then
       echo 'ERROR: repository index update rejected' >&2
       exit 1
     fi
     touch "$APPS_TEST_INDEX_READY"
     exit 0
   fi
   [ "$5" = add ] || exit 2
   [ -f "$APPS_TEST_INDEX_READY" ] || {
     echo 'WARNING: opening from cache: No such file or directory' >&2
     exit 1
   }
   shift 5;;
 del)
   if [ "$2" = --simulate ]; then
     [ "${APPS_TEST_DEL_CORE:-0}" = 1 ] && echo 'Purging kmod-nf-conntrack-netlink (mock)'
     [ "${APPS_TEST_DEL_SHARED:-0}" = 1 ] && echo 'Purging luci-lib-chartjs (mock)'
     shift 2
     for item in "$@"; do
       [ "${APPS_TEST_DEL_KEEP:-}" = "$item" ] || printf 'Purging %s (mock)\n' "$item"
     done
     exit 0
   fi
   shift
   [ "${APPS_TEST_DEL_FAIL:-0}" != 1 ] || exit 1
   for item in "$@"; do
     [ "${APPS_TEST_DEL_COMMIT_KEEP:-}" != "$item" ] || continue
     grep -vxF "$item" "$APPS_TEST_INSTALLED" > "$APPS_TEST_INSTALLED.new" || :
     mv "$APPS_TEST_INSTALLED.new" "$APPS_TEST_INSTALLED"
     if [ -n "${APPS_TEST_WORLD:-}" ]; then
       awk -v n="$item" 'index($0, n "><Q") != 1 && index($0, n "=") != 1 && $0 != n' "$APPS_TEST_WORLD" > "$APPS_TEST_WORLD.new"
       mv -f "$APPS_TEST_WORLD.new" "$APPS_TEST_WORLD"
     fi
   done
   exit 0;;
 *) exit 2;;
esac
upgrade=0
if [ "${1:-}" = --upgrade ]; then upgrade=1; shift; fi
if [ "${1:-}" = --simulate ]; then
 [ "${APPS_TEST_MISSING_DEP:-0}" = 1 ] && { echo 'ERROR: unable to select packages: missing dependency' >&2; exit 1; }
 shift
 for pin in "$@"; do
  name="${pin%%=*}"
  case "$repo:$name" in
   hub:nlbwmon|hub:luci-app-nlbwmon|hub:luci-lib-chartjs|hub:smartsafehub-app-retro-arcade|hub:etherwake|hub:luci-app-wol|hub:new-signed-helper) ;;
   *) exit 2;;
  esac
  if [ "${APPS_TEST_UPGRADE:-0}" = 1 ]; then
    echo '(1/3) Upgrading luci-base (mock)'
  elif [ "$upgrade" = 1 ] && grep -qxF "$name" "$APPS_TEST_INSTALLED" 2>/dev/null; then
    echo "(1/1) Upgrading $name (mock)"
  else
    echo "(1/2) Installing $name (mock)"
  fi
 done
 exit 0
fi
if [ "${APPS_TEST_INSTALL_FAIL:-0}" = 1 ]; then
 echo 'ERROR: simulated interrupted APK transaction' >&2
 exit 1
fi
for pin in "$@"; do
 name="${pin%%=*}"
 case "$repo:$name" in
  hub:nlbwmon|hub:luci-app-nlbwmon|hub:luci-lib-chartjs|hub:smartsafehub-app-retro-arcade|hub:etherwake|hub:luci-app-wol|hub:new-signed-helper) ;;
  *) exit 2;;
 esac
 grep -qxF "$name" "$APPS_TEST_INSTALLED" 2>/dev/null || printf '%s\n' "$name" >> "$APPS_TEST_INSTALLED"
 # Model apk add's exact-name replacement of world constraints on commit.
 # Simulations and rejected operations never write the fixture.
 if [ -n "${APPS_TEST_WORLD:-}" ]; then
   awk -v n="$name" 'index($0, n "><Q") != 1 && index($0, n "=") != 1 && $0 != n' "$APPS_TEST_WORLD" > "$APPS_TEST_WORLD.new"
   printf '%s\n' "$pin" >> "$APPS_TEST_WORLD.new"
   mv -f "$APPS_TEST_WORLD.new" "$APPS_TEST_WORLD"
 fi
 # Mock APK must record exact versions even on the first installation.
 awk -v n="$name" '$1 != n' "$APPS_TEST_VERSION_DB" > "$APPS_TEST_VERSION_DB.tmp"
 printf '%s %s\n' "$name" "${pin#*=}" >> "$APPS_TEST_VERSION_DB.tmp"
 mv -f "$APPS_TEST_VERSION_DB.tmp" "$APPS_TEST_VERSION_DB"
done
SH2
cat > "$TMP/bin/start-stop-daemon" <<'SH2'
#!/bin/sh
[ "$1" = -S ] && [ "$2" = -b ] && [ "$3" = -x ] && [ "$5" = -- ] || exit 2
# Starting and final states must carry the same operation ID.
awk -F '\t' '$1 == "operation_id" { print $2; exit }' \
  "$SMARTSAFEHUB_APPS_RUNTIME_DIR/apps-operation.state" >> "$APPS_TEST_OPERATION_START_LOG"
"$4" "$6" "$7" "$8"
SH2
chmod +x "$TMP/bin/"*
cat > "$TMP/bin/metrics-hook" <<'METRICS'
#!/bin/sh
printf '%s
' "$*" >> "$APPS_TEST_METRICS_LOG"
METRICS
chmod +x "$TMP/bin/metrics-hook"
export APPS_TEST_METRICS_LOG="$TMP/install-events"
export SMARTSAFEHUB_APPS_METRICS_BIN="$TMP/bin/metrics-hook"
: > "$APPS_TEST_METRICS_LOG"
export SMARTSAFEHUB_APPS_MANAGER_BIN="$MANAGER"
export SMARTSAFEHUB_APPS_HELPER_BIN="$TMP/bin/fetch-catalog"
export SMARTSAFEHUB_APPS_RUNTIME_DIR="$TMP/runtime"
export SMARTSAFEHUB_APPS_OWNED_DIR="$TMP/owned"
export SMARTSAFEHUB_HTTP_CURL_BIN="$ROOT/tests/support/mock-curl" MOCK_CURL_BACKEND="$TMP/bin/uclient-fetch"
export SMARTSAFEHUB_HTTP_UCLIENT_BIN="$TMP/bin/uclient-fetch"
export APPS_TEST_URL_LOG="$TMP/fetched-urls"
export SMARTSAFEHUB_APPS_OVERLAY_PATH="$TMP/overlay"
export SMARTSAFEHUB_APPS_MEMINFO_PATH="$TMP/meminfo"
export SMARTSAFEHUB_APPS_JSONFILTER_BIN="$TMP/bin/jsonfilter"
export SMARTSAFEHUB_APPS_APK_BIN="$TMP/bin/apk"
export SMARTSAFEHUB_APPS_ARCH_FILE="$TMP/apk-arch"
export SMARTSAFEHUB_APPS_DAEMON_BIN="$TMP/bin/start-stop-daemon"
export SMARTSAFEHUB_APPS_LUCI_INDEX_CACHE="$TMP/luci-indexcache"
export APPS_TEST_CATALOG="$TMP/catalog.json"
export APPS_TEST_REPO="$TMP/repo"
export APPS_TEST_INSTALLED="$TMP/installed"
export APPS_TEST_APK_LOG="$TMP/apk-commands"
export APPS_TEST_INDEX_READY="$TMP/index-ready"
export APPS_TEST_VERSION_DB="$TMP/installed-versions"
: > "$APPS_TEST_VERSION_DB"
export APPS_TEST_OPERATION_START_LOG="$TMP/operation-start-ids"
: > "$APPS_TEST_INSTALLED"
# A validated fixed release installs all three APKs from a single signed feed.
"$MANAGER" start install '../../../../etc/passwd' >/dev/null 2>&1 && fail 'invalid app ID accepted'
"$MANAGER" start install 'not-approved' || fail 'unknown app should queue'
grep -Fqx "$(printf 'code\tE22')" "$TMP/runtime/apps-operation.state" || fail 'unknown app was installed'
first_operation_id="$(awk -F '\t' '$1 == "operation_id" { print $2; exit }' "$TMP/runtime/apps-operation.state")"
[ -n "$first_operation_id" ] || fail 'first failed operation has no identity'
printf '%s\n' "$first_operation_id" | grep -Eq '^[0-9]{10}-[0-9]+-[0-9a-f]{16}$' || fail 'operation ID must include a valid random nonce without od'
[ "$(sed -n '1p' "$APPS_TEST_OPERATION_START_LOG")" = "$first_operation_id" ] || fail 'operation identity changed during failure'
"$MANAGER" start install not-approved || fail 'repeated failed install did not queue'
repeat_operation_id="$(awk -F '\t' '$1 == "operation_id" { print $2; exit }' "$TMP/runtime/apps-operation.state")"
[ "$repeat_operation_id" != "$first_operation_id" ] || fail 'repeated E22 failure reused dismissed operation ID'
[ "$(sed -n '2p' "$APPS_TEST_OPERATION_START_LOG")" = "$repeat_operation_id" ] || fail 'repeated failure changed identity between phases'
"$MANAGER" start install network-usage-monitor || fail 'install did not queue'
grep -Fqx "$(printf 'phase\tsuccess')" "$TMP/runtime/apps-operation.state" || fail 'three APK installation failed'
second_operation_id="$(awk -F '\t' '$1 == "operation_id" { print $2; exit }' "$TMP/runtime/apps-operation.state")"
[ -n "$second_operation_id" ] && [ "$first_operation_id" != "$second_operation_id" ] || fail 'new operation reused old identity'
[ "$(sed -n '3p' "$APPS_TEST_OPERATION_START_LOG")" = "$second_operation_id" ] || fail 'operation identity changed during success'
[ "$(wc -l < "$APPS_TEST_INSTALLED")" -eq 3 ] || fail 'all three APKs were not installed'
[ "$(wc -l < "$APPS_TEST_METRICS_LOG" | tr -d ' ')" -eq 1 ] || fail 'successful installation not recorded exactly once'
grep -Eq '^enqueue network-usage-monitor 2025\.06\.02-r1 [0-9]+-[0-9]+-[a-f0-9]{16} install$' "$APPS_TEST_METRICS_LOG" || fail 'invalid install receipt fields'

grep -Eq '^--repositories-file /dev/null -X file://.*/packages/packages.adb update$' "$APPS_TEST_APK_LOG" || fail 'approved local index not loaded before simulation'
grep -Eq '^--repositories-file /dev/null -X file://.*/packages/packages.adb add --simulate nlbwmon=2025\.06\.02~29236be6-r1 luci-app-nlbwmon=26\.288\.56989~75a306d luci-lib-chartjs=26\.288\.56989~75a306d$' "$APPS_TEST_APK_LOG" || fail 'isolated signed repository simulation not used'
grep -Eq '^--repositories-file /dev/null -X file://.*/packages/packages.adb add nlbwmon=' "$APPS_TEST_APK_LOG" || fail 'isolated signed repository install not used'
# A failed random-source read must never launch a removal or leave a lock.
# This also guards against accidentally generating a fixed nonce from empty data.
cat > "$TMP/bin/dd" <<'SH_DD'
#!/bin/sh
exit 1
SH_DD
chmod +x "$TMP/bin/dd"
if "$MANAGER" start remove network-usage-monitor >/dev/null 2>&1; then
 fail 'failed entropy read started a removal'
fi
rm -f "$TMP/bin/dd"
[ ! -e "$TMP/runtime/apps-operation.lock" ] || fail 'failed entropy read left a lock'
grep -Fqx "$(printf 'phase\tsuccess')" "$TMP/runtime/apps-operation.state" || fail 'failed launch overwrote existing operation'
[ "$(wc -l < "$APPS_TEST_INSTALLED" | tr -d ' ')" -eq 3 ] || fail 'failed entropy read touched installed APKs'
"$MANAGER" status
grep -Fq "$(printf 'network-usage-monitor\t1\t1\t1\t1')" "$TMP/runtime/apps-status.tsv" || fail 'ready state missing'
grep -Fq "$(printf 'network-usage-monitor\t1\t1\t1\t1\t0\t')" "$TMP/runtime/apps-status.tsv" || fail 'installed state changed'
# Optional size lookup must never run on the critical installation-status path.
[ "$(grep -c '^info -s ' "$APPS_TEST_APK_LOG" || :)" -eq 0 ] || fail 'status unexpectedly queried APK sizes'
"$MANAGER" sizes
grep -Fqx "$(printf 'network-usage-monitor\t2359296')" "$TMP/runtime/apps-size.tsv" || fail 'multi-package installed size not summed'
[ "$(grep -c '^info -s ' "$APPS_TEST_APK_LOG" || :)" -eq 3 ] || fail 'each network APK size must be queried separately'
for package in nlbwmon luci-app-nlbwmon luci-lib-chartjs; do
 grep -Fqx "info -s $package" "$APPS_TEST_APK_LOG" || fail "missing individual size lookup: $package"
done
# Standard apk info must work when this apk v3 variant does not expose -s.
export APPS_TEST_SIZE_FULL_INFO_ONLY=1
"$MANAGER" sizes
grep -Fqx "$(printf 'network-usage-monitor\t2359296')" "$TMP/runtime/apps-size.tsv" || fail 'full APK info fallback failed'
unset APPS_TEST_SIZE_FULL_INFO_ONLY
# OpenWrt APK versions may render the size on the header line or with no
# whitespace between the number and KiB. The sum must be identical.
export APPS_TEST_SIZE_INLINE=1
"$MANAGER" sizes
grep -Fqx "$(printf 'network-usage-monitor\t2359296')" "$TMP/runtime/apps-size.tsv" || fail 'inline/compact installed size not summed'
[ ! -e "$TMP/runtime/apps-size-diagnostics.tsv" ] || fail 'retired size diagnostic file was created'
unset APPS_TEST_SIZE_INLINE
# Real OpenWrt 25.12 device output repeats the *same* installed-size header:
# nlbwmon twice, luci-app-nlbwmon / luci-lib-chartjs three times each.
export APPS_TEST_SIZE_DEVICE_REPEAT=1
"$MANAGER" sizes
grep -Fqx "$(printf 'network-usage-monitor\t117760')" "$TMP/runtime/apps-size.tsv" || fail 'real duplicated APK info output did not sum to 115 KiB'
[ ! -e "$TMP/runtime/apps-size-diagnostics.tsv" ] || fail 'repeated APK size metadata wrote a diagnostic file'
# A repeated heading with a *different* size is ambiguous: refuse to guess.
export APPS_TEST_SIZE_CONFLICTING_REPEAT=1
"$MANAGER" sizes
[ ! -s "$TMP/runtime/apps-size.tsv" ] || fail 'conflicting duplicated size was accepted'
[ ! -e "$TMP/runtime/apps-size-diagnostics.tsv" ] || fail 'conflicting size metadata wrote a diagnostic file'
unset APPS_TEST_SIZE_CONFLICTING_REPEAT APPS_TEST_SIZE_DEVICE_REPEAT
# Do not show a misleading partial sum if one package cannot be measured.
export APPS_TEST_SIZE_MISSING_PACKAGE=luci-lib-chartjs
"$MANAGER" sizes
[ ! -s "$TMP/runtime/apps-size.tsv" ] || fail 'partial APK metadata reported as complete installed size'
[ ! -e "$TMP/runtime/apps-size-diagnostics.tsv" ] || fail 'missing package size wrote a diagnostic file'
unset APPS_TEST_SIZE_MISSING_PACKAGE
# Malformed and missing metadata must not alter the actual installed state.
export APPS_TEST_SIZE_INVALID=1
"$MANAGER" sizes
[ ! -s "$TMP/runtime/apps-size.tsv" ] || fail 'invalid APK size reported as bytes'
"$MANAGER" status
grep -Fq "$(printf 'network-usage-monitor\t1\t1\t1\t1\t0\t')" "$TMP/runtime/apps-status.tsv" || fail 'invalid size changed app state'
unset APPS_TEST_SIZE_INVALID
export APPS_TEST_SIZE_MISSING=1
"$MANAGER" sizes
[ ! -s "$TMP/runtime/apps-size.tsv" ] || fail 'missing APK size must be omitted'
[ ! -e "$TMP/runtime/apps-size-diagnostics.tsv" ] || fail 'invalid/missing APK size created retired diagnostics'
unset APPS_TEST_SIZE_MISSING
"$MANAGER" start remove network-usage-monitor || fail 'remove did not queue'
[ ! -s "$APPS_TEST_INSTALLED" ] || fail 'new Apps uninstall did not remove owned packages'
[ "$(wc -l < "$APPS_TEST_METRICS_LOG" | tr -d ' ')" -eq 1 ] || fail 'removal counted as an installation'

cp "$TMP/catalog.json" "$TMP/catalog-good.json"
python3 - "$TMP/catalog.json" <<'PY_BAD'
import json,sys
path=sys.argv[1]; obj=json.load(open(path)); obj['apps'][0].pop('repository_release_id')
open(path,'w').write(json.dumps(obj))
PY_BAD
"$MANAGER" start install network-usage-monitor || fail 'missing release ID did not queue'
grep -Fqx "$(printf 'code\tE25')" "$TMP/runtime/apps-operation.state" || fail 'missing release ID accepted'
cp "$TMP/catalog-good.json" "$TMP/catalog.json"
python3 - "$TMP/catalog.json" <<'PY_BAD'
import json,sys
path=sys.argv[1]; obj=json.load(open(path))
obj['apps'][0]['web_ui']={'package':'luci-lib-chartjs'}
obj['apps'][0]['packages'].pop()
open(path,'w').write(json.dumps(obj))
PY_BAD
"$MANAGER" start install network-usage-monitor || fail 'partial package set did not queue'
grep -Fqx "$(printf 'code\tE27')" "$TMP/runtime/apps-operation.state" || fail 'unapproved UI primary should fail before archive fetch'
cp "$TMP/catalog-good.json" "$TMP/catalog.json"
# A repository signature/index failure must fail closed before any install.
export APPS_TEST_REPO_UPDATE_FAIL=1
rm -f "$APPS_TEST_INDEX_READY"
"$MANAGER" start install network-usage-monitor || fail 'failed repository update did not queue'
grep -Fqx "$(printf 'code\tE34')" "$TMP/runtime/apps-operation.state" || fail 'failed repository update was accepted'
grep -Fq 'repository index update rejected' "$TMP/runtime/apps-last-error.log" || fail 'repository update error was not preserved'
[ ! -s "$APPS_TEST_INSTALLED" ] || fail 'failed repository update installed packages'
unset APPS_TEST_REPO_UPDATE_FAIL
cp "$TMP/catalog-good.json" "$TMP/catalog.json"
printf 'tampered APK\n' > "$TMP/repo/luci-lib-chartjs-26.288.56989~75a306d.apk"
"$MANAGER" start install network-usage-monitor || fail 'tampered APK did not queue'
grep -Fqx "$(printf 'code\tE33')" "$TMP/runtime/apps-operation.state" || fail 'modified APK accepted'
[ "$(wc -l < "$APPS_TEST_METRICS_LOG" | tr -d ' ')" -eq 1 ] || fail 'failed installation counted'

printf 'PASS: Apps install/remove signed immutable release, three APKs, ownership and hash checks\n'

# Self-built App publications must install from immutable signed releases.
if ! grep -Fq 'repo_url="$REPO_BASE/$channel/packages/$arch/smartsafehub/$publication"' "$MANAGER"; then
    echo 'FAIL: signed immutable Apps package publication is missing' >&2
    exit 1
fi

# Retro Arcade is a single APK from the same signed feed. Verify readiness of
# its static entry point independently of the package-manager install state.
: > "$APPS_TEST_INSTALLED"
export SMARTSAFEHUB_APPS_WEB_ROOT="$TMP/www"
cat > "$TMP/catalog.json" <<EOF_RETRO
{"schema":1,"device_code":"iptime-ax3000sm","firmware_build_id":"mock-build-1","channel":"stable","apps":[{"id":"retro-arcade","version":"1.0.0-r1","name":"Retro Arcade","runtime":"router","installer":"apk","package_arch":"aarch64_cortex-a53","repository_release_id":"20261027T123000","repository_index_sha256":"$INDEX_SHA","web_ui":{"type":"static","path":"/retro-arcade/","package":"smartsafehub-app-retro-arcade"},"packages":[{"name":"smartsafehub-app-retro-arcade","version":"1.0.0-r1","sha256":"$RETROSHA"}],"requirements":{"min_memory_mb":1,"min_storage_mb":1}}]}
EOF_RETRO
"$MANAGER" start install retro-arcade || fail 'Retro Arcade install did not queue'
grep -Fqx "$(printf 'phase\tsuccess')" "$TMP/runtime/apps-operation.state" || fail 'single Retro APK installation failed'
[ "$(cat "$APPS_TEST_INSTALLED")" = smartsafehub-app-retro-arcade ] || fail 'unexpected Retro APK installation set'
[ "$(wc -l < "$APPS_TEST_METRICS_LOG" | tr -d ' ')" -eq 2 ] || fail 'Retro install not counted'
grep -Eq '^enqueue retro-arcade 1\.0\.0-r1 [0-9]+-[0-9]+-[a-f0-9]{16} install$' "$APPS_TEST_METRICS_LOG" || fail 'Retro receipt incorrect'
# Pin the exact installed package version used by the status query. The
# approved catalog version must never be substituted for this value.
printf 'smartsafehub-app-retro-arcade 1.0.0-r1\n' > "$APPS_TEST_VERSION_DB"

"$MANAGER" status
grep -Fq "$(printf 'retro-arcade\t1\t1\t1\t0')" "$TMP/runtime/apps-status.tsv" || fail 'Retro Arcade should not launch before its HTML exists'
mkdir -p "$TMP/www/retro-arcade"
printf 'retro entry\n' > "$TMP/www/retro-arcade/index.html"
"$MANAGER" status
grep -Fq "$(printf 'retro-arcade\t1\t1\t1\t1')" "$TMP/runtime/apps-status.tsv" || fail 'Retro Arcade entry point is not ready'
grep -Fqx "$(printf 'retro-arcade\t1\t1\t1\t1\t0\t1.0.0-r1')" "$TMP/runtime/apps-status.tsv" || fail 'installed Retro version missing'
"$MANAGER" sizes
grep -Fqx "$(printf 'retro-arcade\t13107200')" "$TMP/runtime/apps-size.tsv" || fail 'Retro Arcade size missing'
rm "$TMP/www/retro-arcade/index.html"
"$MANAGER" status
grep -Fq "$(printf 'retro-arcade\t1\t1\t1\t0')" "$TMP/runtime/apps-status.tsv" || fail 'removed Retro Arcade entry point still launches'
# A malformed catalog must not allow more than one approved Retro APK.
python3 - "$TMP/catalog.json" <<'PY_RETRO_BAD'
import json,sys
p=sys.argv[1]; data=json.load(open(p)); data['apps'][0]['packages'].append(data['apps'][0]['packages'][0]); open(p,'w').write(json.dumps(data))
PY_RETRO_BAD
"$MANAGER" start install retro-arcade || fail 'invalid multi-APK Retro install should queue'
grep -Fqx "$(printf 'code\tE27')" "$TMP/runtime/apps-operation.state" || fail 'multiple Retro packages not rejected'
# Restore the catalog for safe removal of the original installed APK.
python3 - "$TMP/catalog.json" <<'PY_RETRO_GOOD'
import json,sys
p=sys.argv[1]; data=json.load(open(p)); data['apps'][0]['packages'].pop(); open(p,'w').write(json.dumps(data))
PY_RETRO_GOOD
"$MANAGER" start remove retro-arcade || fail 'Retro Arcade removal did not queue'
[ ! -s "$APPS_TEST_INSTALLED" ] || fail 'Retro Arcade was not uninstalled'
printf 'PASS: Retro Arcade single APK, static entry point readiness and safe removal\n'

# Restore the mock file deliberately corrupted by the earlier hash test.
printf 'approved chart mock package payload\n' > "$TMP/repo/luci-lib-chartjs-26.288.56989~75a306d.apk"
# A catalog may contain multiple apps. Each app must be visible to the
# installer and status reporter regardless of its position in the list.
: > "$APPS_TEST_INSTALLED"
rm -f "$TMP/owned/retro-arcade" "$TMP/owned/network-usage-monitor"
printf '%s\n' smartsafehub-app-retro-arcade > "$APPS_TEST_INSTALLED"
cat > "$TMP/catalog.json" <<EOF_BOTH
{"schema":1,"device_code":"iptime-ax3000sm","firmware_build_id":"mock-build-1","channel":"stable","apps":[{"id":"retro-arcade","version":"1.0.0-r1","name":"Retro Arcade","runtime":"router","installer":"apk","package_arch":"aarch64_cortex-a53","repository_release_id":"20261027T123000","repository_index_sha256":"$INDEX_SHA","web_ui":{"type":"static","path":"/retro-arcade/","package":"smartsafehub-app-retro-arcade"},"packages":[{"name":"smartsafehub-app-retro-arcade","version":"1.0.0-r1","sha256":"$RETROSHA"}],"requirements":{"min_memory_mb":1,"min_storage_mb":1}},{"id":"network-usage-monitor","version":"2025.06.02-r1","name":"네트워크 사용량 모니터","runtime":"router","installer":"apk","package_arch":"aarch64_cortex-a53","repository_release_id":"20261027T123000","repository_index_sha256":"$INDEX_SHA","packages":[{"name":"nlbwmon","version":"2025.06.02~29236be6-r1","sha256":"$ARCHIVE_SHA"},{"name":"luci-app-nlbwmon","version":"26.288.56989~75a306d","sha256":"$LUCISH"},{"name":"luci-lib-chartjs","version":"26.288.56989~75a306d","sha256":"$CHARTSHA"}],"requirements":{"min_memory_mb":1,"min_storage_mb":1}}]}
EOF_BOTH
# Retro Arcade was installed manually; testing the other app must not adopt it.
"$TMP/bin/fetch-catalog"
"$MANAGER" status
[ "$(wc -l < "$TMP/runtime/apps-status.tsv" | tr -d ' ')" -eq 2 ] || fail 'status lost the second approved app'
grep -Fq "$(printf 'retro-arcade\t1\t1\t0\t0\t')" "$TMP/runtime/apps-status.tsv" || fail 'manual Retro Arcade status incorrect'
grep -Fq "$(printf 'network-usage-monitor\t0\t0\t0\t0\t')" "$TMP/runtime/apps-status.tsv" || fail 'second app omitted from status'
"$MANAGER" start install network-usage-monitor || fail 'second app installation did not queue'
grep -Fqx "$(printf 'phase\tsuccess')" "$TMP/runtime/apps-operation.state" || fail 'second app install unexpectedly failed E22'
[ "$(wc -l < "$APPS_TEST_INSTALLED" | tr -d ' ')" -eq 4 ] || fail 'install changed unrelated packages'
grep -Fqx smartsafehub-app-retro-arcade "$APPS_TEST_INSTALLED" || fail 'manual Retro Arcade was modified'
[ ! -e "$TMP/owned/retro-arcade" ] || fail 'manual Retro Arcade was adopted'
"$MANAGER" status
grep -Fq "$(printf 'network-usage-monitor\t1\t1\t1\t1\t')" "$TMP/runtime/apps-status.tsv" || fail 'second app installed state missing'
"$MANAGER" start remove network-usage-monitor || fail 'second app removal did not queue'
[ "$(cat "$APPS_TEST_INSTALLED")" = smartsafehub-app-retro-arcade ] || fail 'remove touched manual Retro Arcade'
# Reverse the catalog to verify lookup and status for the other second app.
python3 - "$TMP/catalog.json" <<'PY_BOTH_REVERSED'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text())
data['apps'].reverse()
path.write_text(json.dumps(data))
PY_BOTH_REVERSED
"$TMP/bin/fetch-catalog"
"$MANAGER" status
[ "$(wc -l < "$TMP/runtime/apps-status.tsv" | tr -d ' ')" -eq 2 ] || fail 'reversed catalog lost an app'
grep -Fq "$(printf 'retro-arcade\t1\t1\t0\t0\t')" "$TMP/runtime/apps-status.tsv" || fail 'second Retro Arcade status missing'
"$MANAGER" start install retro-arcade || fail 'second Retro Arcade installation did not queue'
grep -Fqx "$(printf 'code\tE29')" "$TMP/runtime/apps-operation.state" || fail 'second app did not reach manual ownership check'
printf 'PASS: multi-app lookup, E22 regression and manual package protection\n'

# Firmware sysupgrade drops optional APKs but keeps Apps ownership. A newer
# firmware may approve a different APK version/hash for the same owned name.
# Only the privileged restore path may reconcile missing owned packages.
: > "$APPS_TEST_INSTALLED"
: > "$APPS_TEST_VERSION_DB"
rm -f "$TMP/owned/retro-arcade" "$TMP/owned/network-usage-monitor"
"$MANAGER" start install retro-arcade restore || fail 'repair without ownership did not queue'
grep -Fqx "$(printf 'code\tE28')" "$TMP/runtime/apps-operation.state" || fail 'restore without ownership was not blocked'
printf 'new signed Retro payload\n' > "$TMP/repo/smartsafehub-app-retro-arcade-1.1.0-r1.apk"
RESTORE_NEW_SHA="$(sha256sum "$TMP/repo/smartsafehub-app-retro-arcade-1.1.0-r1.apk" | cut -d ' ' -f 1)"
cat > "$TMP/catalog.json" <<EOF_RESTORE_NEW
{"schema":1,"device_code":"iptime-ax3000sm","firmware_build_id":"mock-new-firmware","channel":"stable","apps":[{"id":"retro-arcade","version":"1.1.0-r1","runtime":"router","installer":"apk","package_arch":"aarch64_cortex-a53","repository_release_id":"20261027T123000","repository_index_sha256":"$INDEX_SHA","packages":[{"name":"smartsafehub-app-retro-arcade","version":"1.1.0-r1","sha256":"$RESTORE_NEW_SHA"}],"requirements":{"min_memory_mb":1,"min_storage_mb":1}}]}
EOF_RESTORE_NEW
printf 'smartsafehub-app-retro-arcade\t1.0.0-r1\t%s\n' "$RETROSHA" > "$TMP/owned/retro-arcade"
RESTORE_OLD_MANIFEST="$(cat "$TMP/owned/retro-arcade")"
RESTORE_RECEIPTS="$(wc -l < "$APPS_TEST_METRICS_LOG" | tr -d ' ')"
"$MANAGER" start install retro-arcade || fail 'manual install with old ownership did not queue'
grep -Fqx "$(printf 'code\tE28')" "$TMP/runtime/apps-operation.state" || fail 'ordinary install bypassed version ownership check'
[ "$(cat "$TMP/owned/retro-arcade")" = "$RESTORE_OLD_MANIFEST" ] || fail 'failed manual install rewrote ownership'
# A different release that is still installed is not safe to replace.
printf 'smartsafehub-app-retro-arcade\n' > "$APPS_TEST_INSTALLED"
"$MANAGER" start install retro-arcade restore || fail 'installed old release restore did not queue'
grep -Fqx "$(printf 'code\tE28')" "$TMP/runtime/apps-operation.state" || fail 'restore silently replaced a present release'
[ "$(cat "$TMP/owned/retro-arcade")" = "$RESTORE_OLD_MANIFEST" ] || fail 'present package changed ownership'
: > "$APPS_TEST_INSTALLED"
# Missing dependencies and a tampered APK must fail before re-pinning records.
export APPS_TEST_MISSING_DEP=1
"$MANAGER" start install retro-arcade restore || fail 'dependency simulation failure did not queue'
grep -Fqx "$(printf 'code\tE34')" "$TMP/runtime/apps-operation.state" || fail 'restore bypassed solver guard'
grep -Fqx "$(printf 'detail\tapk_simulate')" "$TMP/runtime/apps-operation.state" || fail 'simulator failure detail missing'
[ "$(cat "$TMP/owned/retro-arcade")" = "$RESTORE_OLD_MANIFEST" ] || fail 'failed solver changed ownership'
unset APPS_TEST_MISSING_DEP
printf 'tampered new Retro payload\n' > "$TMP/repo/smartsafehub-app-retro-arcade-1.1.0-r1.apk"
"$MANAGER" start install retro-arcade restore || fail 'tampered restore did not queue'
grep -Fqx "$(printf 'code\tE33')" "$TMP/runtime/apps-operation.state" || fail 'tampered new APK passed restore'
[ "$(cat "$TMP/owned/retro-arcade")" = "$RESTORE_OLD_MANIFEST" ] || fail 'tampered APK re-pinned ownership'
printf 'new signed Retro payload\n' > "$TMP/repo/smartsafehub-app-retro-arcade-1.1.0-r1.apk"
# A package omitted from a new approval cannot be rescued by stale ownership.
printf 'unapproved-old-package\t1.0.0-r1\t%s\n' "$RETROSHA" >> "$TMP/owned/retro-arcade"
"$MANAGER" start install retro-arcade restore || fail 'unapproved old owner check did not queue'
grep -Fqx "$(printf 'code\tE28')" "$TMP/runtime/apps-operation.state" || fail 'unapproved old package re-pinned'
printf '%s\n' "$RESTORE_OLD_MANIFEST" > "$TMP/owned/retro-arcade"
printf '%s\n' "$RESTORE_OLD_MANIFEST" >> "$TMP/owned/retro-arcade"
"$MANAGER" start install retro-arcade restore || fail 'duplicate ownership check did not queue'
grep -Fqx "$(printf 'code\tE28')" "$TMP/runtime/apps-operation.state" || fail 'duplicate ownership authorized restore'
printf '%s\n' "$RESTORE_OLD_MANIFEST" > "$TMP/owned/retro-arcade"
# An unterminated or empty ownership record cannot authorize restoration.
printf '%s' "$RESTORE_OLD_MANIFEST" > "$TMP/owned/retro-arcade"
"$MANAGER" start install retro-arcade restore || fail 'truncated ownership check did not queue'
grep -Fqx "$(printf 'code\tE28')" "$TMP/runtime/apps-operation.state" || fail 'truncated ownership authorized restore'
printf '%s\n' "$RESTORE_OLD_MANIFEST" > "$TMP/owned/retro-arcade"
# A preinstalled system conntrack package must remain independent of Apps.
printf 'conntrack\n' > "$APPS_TEST_INSTALLED"
"$MANAGER" start install retro-arcade restore || fail 'approved new firmware restore not queued'
grep -Fqx "$(printf 'phase\tsuccess')" "$TMP/runtime/apps-operation.state" || fail 'new approved release was not restored'
grep -Fqx "$(printf 'smartsafehub-app-retro-arcade\t1.1.0-r1\t%s' "$RESTORE_NEW_SHA")" "$TMP/owned/retro-arcade" || fail 'ownership was not updated to newly approved version'
grep -Fqx conntrack "$APPS_TEST_INSTALLED" || fail 'restore removed preinstalled conntrack'
[ "$(wc -l < "$APPS_TEST_INSTALLED" | tr -d ' ')" -eq 2 ] || fail 'restore installed unrelated packages'
[ "$(wc -l < "$APPS_TEST_METRICS_LOG" | tr -d ' ')" -eq "$RESTORE_RECEIPTS" ] || fail 'automatic restore counted as user install'
"$MANAGER" start install retro-arcade restore || fail 'second restore not queued'
grep -Fqx "$(printf 'code\tE28')" "$TMP/runtime/apps-operation.state" || fail 'already restored app was installed twice'
# Ownership files cannot turn conntrack into a removable Apps package.
printf 'conntrack\t1.0-r1\t%s\n' "$RETROSHA" > "$TMP/owned/retro-arcade"
"$MANAGER" start remove retro-arcade || fail 'protected package remove did not queue'
grep -Fqx "$(printf 'code\tE42')" "$TMP/runtime/apps-operation.state" || fail 'conntrack was not protected during removal'
grep -Fqx conntrack "$APPS_TEST_INSTALLED" || fail 'protected conntrack was removed'
rm -f "$TMP/owned/retro-arcade"
# Multi-package restore must preserve existing ownership even when package
# records appear in a different order. It may re-pin the one missing APK but
# must never reinstall the other two or claim the system conntrack package.
cat > "$TMP/catalog.json" <<EOF_RESTORE_MULTI
{"schema":1,"device_code":"iptime-ax3000sm","firmware_build_id":"mock-new-firmware","channel":"stable","apps":[{"id":"network-usage-monitor","version":"2025.06.02-r1","runtime":"router","installer":"apk","package_arch":"aarch64_cortex-a53","repository_release_id":"20261027T123000","repository_index_sha256":"$INDEX_SHA","packages":[{"name":"nlbwmon","version":"2025.06.02~29236be6-r1","sha256":"$ARCHIVE_SHA"},{"name":"luci-app-nlbwmon","version":"26.288.56989~75a306d","sha256":"$LUCISH"},{"name":"luci-lib-chartjs","version":"26.288.56989~75a306d","sha256":"$CHARTSHA"}],"requirements":{"min_memory_mb":1,"min_storage_mb":1}}]}
EOF_RESTORE_MULTI
printf 'luci-app-nlbwmon\n' >> "$APPS_TEST_INSTALLED"
printf 'nlbwmon\n' >> "$APPS_TEST_INSTALLED"
cat > "$TMP/owned/network-usage-monitor" <<EOF_RESTORE_OWNED
luci-app-nlbwmon	26.288.56989~75a306d	$LUCISH
nlbwmon	2025.06.02~29236be6-r1	$ARCHIVE_SHA
luci-lib-chartjs	26.288.56989~75a306d	$RETROSHA
EOF_RESTORE_OWNED
"$MANAGER" start install network-usage-monitor restore || fail 'partial multi-package restore not queued'
grep -Fqx "$(printf 'phase\tsuccess')" "$TMP/runtime/apps-operation.state" || fail 'partial multi-package restore failed'
[ "$(wc -l < "$TMP/owned/network-usage-monitor" | tr -d ' ')" -eq 3 ] || fail 'partial restore duplicated owned packages'
grep -Fqx "$(printf 'luci-lib-chartjs\t26.288.56989~75a306d\t%s' "$CHARTSHA")" "$TMP/owned/network-usage-monitor" || fail 'partial restore did not re-pin missing chart package'
[ "$(wc -l < "$APPS_TEST_INSTALLED" | tr -d ' ')" -eq 5 ] || fail 'partial restore modified present packages'
grep -Fqx conntrack "$APPS_TEST_INSTALLED" || fail 'partial restore modified conntrack'
[ "$(wc -l < "$APPS_TEST_METRICS_LOG" | tr -d ' ')" -eq "$RESTORE_RECEIPTS" ] || fail 'partial restore counted as new user install'
rm -f "$TMP/owned/network-usage-monitor"
printf 'PASS: new-firmware Apps re-pinning, signed restore, no adoption, and conntrack protection\n'

# An Apps-owned app can update to a newer approved, signed package without
# reinstalling, touching system packages or generating a new install receipt.
: > "$APPS_TEST_INSTALLED"
rm -f "$TMP/owned/network-usage-monitor" "$TMP/owned/retro-arcade"
: > "$APPS_TEST_VERSION_DB"
cat > "$TMP/catalog.json" <<EOF_UPDATE_OLD
{"schema":1,"device_code":"iptime-ax3000sm","firmware_build_id":"mock-build-1","channel":"stable","apps":[{"id":"retro-arcade","version":"1.0.0-r1","name":"Retro Arcade","runtime":"router","installer":"apk","package_arch":"aarch64_cortex-a53","repository_release_id":"20261027T123000","repository_index_sha256":"$INDEX_SHA","packages":[{"name":"smartsafehub-app-retro-arcade","version":"1.0.0-r1","sha256":"$RETROSHA"}],"requirements":{"min_memory_mb":1,"min_storage_mb":1}}]}
EOF_UPDATE_OLD
"$MANAGER" start install retro-arcade || fail 'old Retro Arcade install not queued'
grep -Fqx "$(printf 'phase\tsuccess')" "$TMP/runtime/apps-operation.state" || fail 'old Retro Arcade install failed'
printf 'smartsafehub-app-retro-arcade 1.0.0-r1\n' > "$APPS_TEST_VERSION_DB"
receipt_before="$(wc -l < "$APPS_TEST_METRICS_LOG" | tr -d ' ')"
printf 'new signed Retro payload\n' > "$TMP/repo/smartsafehub-app-retro-arcade-1.1.0-r1.apk"
NEWRETROSHA="$(sha256sum "$TMP/repo/smartsafehub-app-retro-arcade-1.1.0-r1.apk" | cut -d ' ' -f 1)"
python3 - "$TMP/catalog.json" "$NEWRETROSHA" <<'PY_UPDATE'
import json,sys
p=sys.argv[1]; data=json.load(open(p)); app=data['apps'][0]
app['version']='1.1.0-r1'; app['packages'][0]['version']='1.1.0-r1'
app['packages'][0]['sha256']=sys.argv[2]
open(p,'w').write(json.dumps(data))
PY_UPDATE
"$TMP/bin/fetch-catalog"
"$MANAGER" status
grep -Fqx "$(printf 'retro-arcade\t1\t1\t1\t0\t1\t1.0.0-r1')" "$TMP/runtime/apps-status.tsv" || fail 'new approved release hid installed 1.0.0-r1'
# Prevent core upgrades even if the APK solver proposes them.
export APPS_TEST_UPGRADE=1
"$MANAGER" start update retro-arcade || fail 'unrelated package simulation did not queue'
grep -Fqx "$(printf 'code\tE53')" "$TMP/runtime/apps-operation.state" || fail 'unrelated system upgrade was not blocked'
grep -Fq "$(printf 'smartsafehub-app-retro-arcade\t1.0.0-r1\t')" "$TMP/owned/retro-arcade" || fail 'failed simulation changed ownership'
unset APPS_TEST_UPGRADE
# Reject altered signed payloads before mutation.
printf 'tampered\n' > "$TMP/repo/smartsafehub-app-retro-arcade-1.1.0-r1.apk"
"$MANAGER" start update retro-arcade || fail 'tampered update did not queue'
grep -Fqx "$(printf 'code\tE33')" "$TMP/runtime/apps-operation.state" || fail 'tampered update was not rejected'
printf 'new signed Retro payload\n' > "$TMP/repo/smartsafehub-app-retro-arcade-1.1.0-r1.apk"
"$MANAGER" start update retro-arcade || fail 'approved update did not queue'
grep -Fqx "$(printf 'phase\tsuccess')" "$TMP/runtime/apps-operation.state" || fail 'approved update did not succeed'
grep -Fqx "$(printf 'smartsafehub-app-retro-arcade\t1.1.0-r1\t%s' "$NEWRETROSHA")" "$TMP/owned/retro-arcade" || fail 'new version manifest not committed'
[ "$(awk '$1 == "smartsafehub-app-retro-arcade" {print $2}' "$APPS_TEST_VERSION_DB")" = 1.1.0-r1 ] || fail 'mock apk version did not update'
[ "$(wc -l < "$APPS_TEST_METRICS_LOG" | tr -d ' ')" -eq "$((receipt_before + 1))" ] || fail 'successful upgrade not recorded exactly once'
grep -Eq '^enqueue retro-arcade 1\.1\.0-r1 [0-9]+-[0-9]+-[a-f0-9]{16} update$' "$APPS_TEST_METRICS_LOG" || fail 'update receipt kind/version incorrect'
[ "$(awk '$1 == "enqueue" && $5 == "update" { n++ } END {print n+0}' "$APPS_TEST_METRICS_LOG")" -eq 1 ] || fail 'upgrade counted as a new install or multiple updates'
"$MANAGER" status
grep -Fqx "$(printf 'retro-arcade\t1\t1\t1\t0\t0\t1.1.0-r1')" "$TMP/runtime/apps-status.tsv" || fail 'installed version not updated after APK upgrade'
# Update releases may appear alongside older APK index metadata: the size
# must match the installed version, even if the older version appears first.
export APPS_TEST_SIZE_MIXED_RELEASES=1
"$MANAGER" sizes
grep -Fqx "$(printf 'retro-arcade\t2097152')" "$TMP/runtime/apps-size.tsv" || fail 'updated Retro size lost when APK info listed multiple releases'
# Contradictory records for that same installed version are still rejected.
export APPS_TEST_SIZE_MIXED_RELEASES=conflicting
"$MANAGER" sizes
[ ! -s "$TMP/runtime/apps-size.tsv" ] || fail 'conflicting current APK release size must be omitted'
unset APPS_TEST_SIZE_MIXED_RELEASES
"$MANAGER" start update retro-arcade || fail 'repeated update should report a no-op'
grep -Fqx "$(printf 'code\tE52')" "$TMP/runtime/apps-operation.state" || fail 'repeated update was not rejected'
[ "$(wc -l < "$APPS_TEST_METRICS_LOG" | tr -d ' ')" -eq "$((receipt_before + 1))" ] || fail 'no-op upgrade produced an event'
# Any attempt to downgrade a package must fail closed.
python3 - "$TMP/catalog.json" "$RETROSHA" <<'PY_DOWNGRADE'
import json,sys
p=sys.argv[1]; data=json.load(open(p)); app=data['apps'][0]
app['version']='1.0.0-r1'; app['packages'][0]['version']='1.0.0-r1'
app['packages'][0]['sha256']=sys.argv[2]
open(p,'w').write(json.dumps(data))
PY_DOWNGRADE
"$TMP/bin/fetch-catalog"
"$MANAGER" status
grep -Fqx "$(printf 'retro-arcade\t1\t1\t1\t0\t0\t1.1.0-r1')" "$TMP/runtime/apps-status.tsv" || fail 'downgrade must not be advertised'
"$MANAGER" start update retro-arcade || fail 'downgrade did not queue'
grep -Fqx "$(printf 'code\tE52')" "$TMP/runtime/apps-operation.state" || fail 'downgrade was not refused'
# A manual downgrade below the recorded approved version remains blocked.
python3 - "$TMP/catalog.json" "$NEWRETROSHA" <<'PY_NEW'
import json,sys
p=sys.argv[1]; data=json.load(open(p)); app=data['apps'][0]
app['version']='1.1.0-r1'; app['packages'][0]['version']='1.1.0-r1'
app['packages'][0]['sha256']=sys.argv[2]
open(p,'w').write(json.dumps(data))
PY_NEW
printf 'smartsafehub-app-retro-arcade 1.0.0-r1\n' > "$APPS_TEST_VERSION_DB"
"$MANAGER" start update retro-arcade || fail 'manual version change did not queue'
grep -Fqx "$(printf 'code\tE52')" "$TMP/runtime/apps-operation.state" || fail 'manual version drift not rejected'
printf 'PASS: selected-app signed updates, version checks, no core upgrades and no duplicate receipts\n'

# A future approved release can add a package without changing router source.
# If the real APK step fails, the pinned new package has a recovery ownership
# record and can be retried without adopting a manually installed package.
printf 'smartsafehub-app-retro-arcade 1.1.0-r1\n' > "$APPS_TEST_VERSION_DB"
python3 - "$TMP/catalog.json" "$HELPERSHA" <<'PY_ADD_DEP'
import json, sys
path, digest = sys.argv[1:]
data = json.load(open(path))
data['apps'][0]['packages'].append({
    'name': 'new-signed-helper', 'version': '1.0-r1', 'sha256': digest,
})
with open(path, 'w') as output:
    json.dump(data, output)
PY_ADD_DEP
"$TMP/bin/fetch-catalog"
"$MANAGER" status
grep -Fqx "$(printf 'retro-arcade\t0\t1\t1\t0\t1\t1.1.0-r1')" "$TMP/runtime/apps-status.tsv" ||
 fail 'added dependency should expose update on installed app'
export APPS_TEST_INSTALL_FAIL=1
"$MANAGER" start update retro-arcade || fail 'interrupted approved dependency update not queued'
grep -Fqx "$(printf 'code\tE54')" "$TMP/runtime/apps-operation.state" ||
 fail 'interrupted APK transaction did not report failure'
grep -q "^new-signed-helper$(printf '\t')" "$TMP/owned/retro-arcade" ||
 fail 'interrupted newly approved dependency was left unmanaged'
unset APPS_TEST_INSTALL_FAIL
"$MANAGER" start update retro-arcade || fail 'retry of approved dependency update not queued'
grep -Fqx "$(printf 'phase\tsuccess')" "$TMP/runtime/apps-operation.state" ||
 fail 'retry of newly approved dependency did not succeed'
grep -q "^new-signed-helper$(printf '\t')" "$TMP/owned/retro-arcade" ||
 fail 'successful dependency update lost ownership'
grep -Fxq new-signed-helper "$APPS_TEST_INSTALLED" ||
 fail 'newly approved dependency was never installed'
"$MANAGER" start update retro-arcade || fail 'repeated dependency update should be no-op'
grep -Fqx "$(printf 'code\tE52')" "$TMP/runtime/apps-operation.state" ||
 fail 'duplicate dependency update was allowed'
printf 'PASS: 신규 승인 의존성 업데이트와 설치 실패 후 재시도 보호\n'


# Approved catalog and installed status are fetched independently. A mismatch
# across requests is not an orphan: only an Apps-owned manifest for a package
# that remains installed can mark an approval as retired.
python3 - "$TMP/catalog.json" <<'PY_RETIRED'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
data['apps'] = []
with open(p, 'w') as fp:
    json.dump(data, fp)
PY_RETIRED
"$TMP/bin/fetch-catalog"
"$MANAGER" status
grep -Fqx "$(printf 'retro-arcade\t0\t1\t1\t0\t0\t\t1')" "$TMP/runtime/apps-status.tsv" ||     fail 'a genuinely Apps-owned removed approval was not marked retired'
# Manual APK installations have no ownership manifest and must not be promoted
# to managed/retired Apps. Likewise, forged/corrupt ownership is ignored.
rm -f "$TMP/owned/retro-arcade"
"$MANAGER" status
[ ! -s "$TMP/runtime/apps-status.tsv" ] || fail 'manually installed APK falsely marked retired'
printf 'invalid manifest contents\n' > "$TMP/owned/retro-arcade"
"$MANAGER" status
[ ! -s "$TMP/runtime/apps-status.tsv" ] || fail 'invalid manifest falsely marked retired'
rm -f "$TMP/owned/retro-arcade"
printf 'PASS: catalog/status refresh races do not mistake manual APK installs for retired Apps\n'

# Wake-on-LAN integrates with the same signed APK flow, but requires exactly
# etherwake + luci-app-wol. Its UI is NOT the etherwake helper executable.
printf 'signed index cache\n' > "$SMARTSAFEHUB_APPS_LUCI_INDEX_CACHE"
: > "$APPS_TEST_INSTALLED"
: > "$APPS_TEST_VERSION_DB"
cat > "$TMP/catalog.json" <<EOF_WOL
{"schema":1,"device_code":"iptime-ax3000sm","firmware_build_id":"mock-build-1","channel":"stable","apps":[{"id":"wake-on-lan","version":"26.288.56989~75a306d","name":"Wake-on-LAN","category":"utilities","runtime":"router","installer":"apk","package_arch":"aarch64_cortex-a53","repository_release_id":"20261027T123000","repository_index_sha256":"$INDEX_SHA","web_ui":{"type":"luci","path":"/cgi-bin/luci/admin/services/wol","package":"luci-app-wol"},"packages":[{"name":"etherwake","version":"1.09-r5","sha256":"$ETHERSHA"},{"name":"luci-app-wol","version":"26.288.56989~75a306d","sha256":"$WOLSHA"}],"requirements":{"min_memory_mb":1,"min_storage_mb":1}}]}
EOF_WOL
"$TMP/bin/fetch-catalog"
"$MANAGER" start install wake-on-lan || fail 'Wake-on-LAN install not queued'
grep -Fqx "$(printf 'phase\tsuccess')" "$TMP/runtime/apps-operation.state" || fail 'Wake-on-LAN installation failed'
[ ! -e "$SMARTSAFEHUB_APPS_LUCI_INDEX_CACHE" ] || fail 'LuCI menu cache not invalidated after WOL install'
[ "$(wc -l < "$TMP/owned/wake-on-lan" | tr -d ' ')" -eq 2 ] || fail 'WOL must own exactly two APKs'
grep -q "^etherwake$(printf '\t')" "$TMP/owned/wake-on-lan" || fail 'etherwake ownership missing'
grep -q "^luci-app-wol$(printf '\t')" "$TMP/owned/wake-on-lan" || fail 'luci-app-wol ownership missing'
"$MANAGER" status
grep -Fqx "$(printf 'wake-on-lan\t1\t1\t1\t1\t0\t26.288.56989~75a306d')" "$TMP/runtime/apps-status.tsv" || fail 'WOL should open LuCI after both APKs installed'
# A different LuCI route is not an approved WOL launch target.
python3 - "$TMP/catalog.json" <<'PY_WRONG_WOL_UI'
import json,sys
p=sys.argv[1]; data=json.load(open(p))
data['apps'][0]['web_ui']['path']='/cgi-bin/luci/admin/system/admin'
open(p,'w').write(json.dumps(data))
PY_WRONG_WOL_UI
"$TMP/bin/fetch-catalog"
"$MANAGER" status
grep -Fqx "$(printf 'wake-on-lan\t1\t1\t1\t0\t0\t26.288.56989~75a306d')" "$TMP/runtime/apps-status.tsv" || fail 'unexpected WOL LuCI route exposed'
# Fix approval, then remove both packages. LuCI must not retain a stale menu.
python3 - "$TMP/catalog.json" <<'PY_WOL_UI'
import json,sys
p=sys.argv[1]; data=json.load(open(p))
data['apps'][0]['web_ui']['path']='/cgi-bin/luci/admin/services/wol'
open(p,'w').write(json.dumps(data))
PY_WOL_UI
"$TMP/bin/fetch-catalog"
printf 'cached menu\n' > "$SMARTSAFEHUB_APPS_LUCI_INDEX_CACHE"
"$MANAGER" start remove wake-on-lan || fail 'WOL removal not queued'
grep -Fqx "$(printf 'phase\tsuccess')" "$TMP/runtime/apps-operation.state" || fail 'WOL removal failed'
[ ! -e "$SMARTSAFEHUB_APPS_LUCI_INDEX_CACHE" ] || fail 'LuCI menu cache not invalidated after WOL removal'
[ ! -e "$TMP/owned/wake-on-lan" ] || fail 'WOL ownership not cleared'
[ ! -s "$APPS_TEST_INSTALLED" ] || fail 'WOL left installed APKs behind'
# An additional signed dependency is accepted without a firmware/web UI update.
python3 - "$TMP/catalog.json" "$HELPERSHA" <<'PY_WOL_NEW_DEP'
import json, sys
path, digest = sys.argv[1:]
data = json.load(open(path))
data['apps'][0]['packages'].append({
    'name': 'new-signed-helper', 'version': '1.0-r1', 'sha256': digest,
})
with open(path, 'w') as fp:
    json.dump(data, fp)
PY_WOL_NEW_DEP
"$MANAGER" start install wake-on-lan || fail 'approved additional dependency install not queued'
grep -Fqx "$(printf 'phase\tsuccess')" "$TMP/runtime/apps-operation.state" || fail 'approved additional dependency was rejected'
grep -q "^new-signed-helper$(printf '\t')" "$TMP/owned/wake-on-lan" || fail 'new dependency not owned'
"$MANAGER" start remove wake-on-lan || fail 'removing generic dependency not queued'
[ ! -s "$APPS_TEST_INSTALLED" ] || fail 'generic dependency remained after safe removal'
# Reset the catalog for deliberately invalid pin fixtures.
python3 - "$TMP/catalog.json" <<'PY_WOL_CLEAR'
import json, sys
path=sys.argv[1]; data=json.load(open(path))
data['apps'][0]['packages']=[p for p in data['apps'][0]['packages'] if p['name'] != 'new-signed-helper']
with open(path, 'w') as fp: json.dump(data, fp)
PY_WOL_CLEAR
# An extra/omitted package in a bad catalog must be rejected before any APK
# download/install, even if the index and SHA values look valid.
python3 - "$TMP/catalog.json" <<'PY_WOL_EXTRA'
import json,sys
p=sys.argv[1]; data=json.load(open(p))
data['apps'][0]['packages'].append({'name':'luci-app-nlbwmon','version':'26.288.56989~75a306d','sha256': 'b'*64})
open(p,'w').write(json.dumps(data))
PY_WOL_EXTRA
"$MANAGER" start install wake-on-lan || fail 'bad WOL catalog not queued'
grep -Fqx "$(printf 'code\tE33')" "$TMP/runtime/apps-operation.state" || fail 'WOL dependency with unapproved archive hash was accepted'
[ ! -s "$APPS_TEST_INSTALLED" ] || fail 'invalid WOL feed changed package state'
[ ! -e "$TMP/owned/wake-on-lan" ] || fail 'invalid WOL feed wrote ownership'
python3 - "$TMP/catalog.json" <<'PY_WOL_MISSING'
import json,sys
p=sys.argv[1]; data=json.load(open(p))
data['apps'][0]['packages']=data['apps'][0]['packages'][:1]
open(p,'w').write(json.dumps(data))
PY_WOL_MISSING
"$MANAGER" start install wake-on-lan || fail 'incomplete WOL catalog not queued'
grep -Fqx "$(printf 'code\tE27')" "$TMP/runtime/apps-operation.state" || fail 'missing WOL LuCI APK was not rejected'
printf 'PASS: Wake-on-LAN signed dual-APK lifecycle, LuCI route and corrupt approvals\n'

# Jarbis accepts the Hub's reviewed dependency set without a fixed package
# count, including after the older manually installed release was removed.
# The cryptographic archive/solver validation still rejects unprovided pins.
# Mock download intentionally fails AFTER preflight to prove the failure is
# not E27/E29; no actual APKs or firmware packages are modified by this test.
: > "$APPS_TEST_INSTALLED"
: > "$APPS_TEST_VERSION_DB"
for name in rpcd-mod-ucode ucode-mod-uci ucode-mod-fs jsonfilter libpthread; do
 printf '%s\n' "$name" >> "$APPS_TEST_INSTALLED"
done
printf 'libpthread 1.0-r1\n' > "$APPS_TEST_VERSION_DB"
jarbis_catalog() {
 python3 - "$TMP/catalog.json" "$INDEX_SHA" "$1" "$2" <<'PY_JARBIS_FIXTURE'
import json
import sys

path, index_hash, arch, variant = sys.argv[1:]
packages = (
    'jarbis', 'mosquitto-ssl', 'mosquitto-client-ssl', 'libmosquitto-ssl',
    'libcares', 'cJSON', 'libpthread', 'librt', 'curl', 'libcurl4',
    'libnghttp2-14', 'libopenssl3',
)
if arch == 'mipsel_24kc':
    packages += ('libatomic1',)
if variant == 'missing':
    packages = tuple(name for name in packages if name != 'cJSON')
elif variant == 'extra':
    packages += ('unreviewed-package',)
elif variant == 'no_atomic':
    packages = tuple(name for name in packages if name != 'libatomic1')
elif variant == 'spoof':
    packages = tuple('notjarbis' if name == 'jarbis' else name for name in packages)
catalog = {
    'schema': 1, 'channel': 'stable', 'apps': [
        {
            'id': 'jarbis', 'version': '0.2.3-r1',
            'runtime': 'router', 'installer': 'apk', 'package_arch': arch,
            'repository_release_id': '20261027T123000',
            'repository_index_sha256': index_hash,
            'packages': [
                {'name': name, 'version': '1.0-r1', 'sha256': 'a' * 64}
                for name in packages
            ],
            'requirements': {'min_memory_mb': 1, 'min_storage_mb': 1},
        }
    ],
}
with open(path, 'w', encoding='utf-8') as stream:
    json.dump(catalog, stream)
PY_JARBIS_FIXTURE
}
assert_jarbis_code() {
 expected="$1"
 "$MANAGER" start install jarbis || fail 'Jarbis install did not queue'
 grep -Fqx "$(printf 'code\t%s' "$expected")" "$TMP/runtime/apps-operation.state" ||
  fail "Jarbis preflight expected $expected"
 [ ! -e "$TMP/owned/jarbis" ] || fail 'Jarbis failure adopted an unrelated APK'
 [ "$(wc -l < "$APPS_TEST_INSTALLED" | tr -d ' ')" -eq 5 ] ||
  fail 'Jarbis preflight modified firmware dependencies'
}
jarbis_catalog aarch64_cortex-a53 valid
# A manually installed Jarbis package may not be silently adopted by Apps.
printf 'jarbis\n' >> "$APPS_TEST_INSTALLED"
"$MANAGER" start install jarbis || fail 'manual Jarbis install did not queue'
grep -Fqx "$(printf 'code\tE29')" "$TMP/runtime/apps-operation.state" ||
 fail 'manually installed Jarbis was adopted'
grep -vxF jarbis "$APPS_TEST_INSTALLED" > "$APPS_TEST_INSTALLED.next" || :
mv "$APPS_TEST_INSTALLED.next" "$APPS_TEST_INSTALLED"
assert_jarbis_code E31
jarbis_catalog aarch64_cortex-a53 missing
assert_jarbis_code E31
jarbis_catalog aarch64_cortex-a53 extra
assert_jarbis_code E31
jarbis_catalog aarch64_cortex-a53 spoof
assert_jarbis_code E31
# A previously installed shared package must have exactly the reviewed
# version: reject drift instead of adopting it, upgrading it or uninstalling it.
jarbis_catalog aarch64_cortex-a53 valid
printf 'libpthread 0.9-r1\n' > "$APPS_TEST_VERSION_DB"
assert_jarbis_code E34
printf 'libpthread 1.0-r1\n' > "$APPS_TEST_VERSION_DB"
# MIPS is an independent contract; libatomic1 is mandatory only on MIPS.
printf 'all\nmipsel_24kc\n' > "$TMP/apk-arch"
jarbis_catalog mipsel_24kc valid
assert_jarbis_code E31
jarbis_catalog mipsel_24kc missing
assert_jarbis_code E31
jarbis_catalog mipsel_24kc extra
assert_jarbis_code E31
jarbis_catalog mipsel_24kc no_atomic
assert_jarbis_code E31
printf 'PASS: Jarbis generic signed APK pins, manual-install cleanup and shared libraries\n'

# Neither the manager nor the UI source knows this newly approved app ID.
# This must still install and remove via the same immutable signed index.
printf 'all\naarch64_cortex-a53\n' > "$TMP/apk-arch"
: > "$APPS_TEST_INSTALLED"
: > "$APPS_TEST_VERSION_DB"
cat > "$TMP/catalog.json" <<EOF_NEW_APP
{"schema":1,"device_code":"iptime-ax3000sm","firmware_build_id":"mock-build-1","channel":"stable","apps":[{"id":"future-lan-tool","version":"1.0-r1","name":"새 승인 앱","runtime":"router","installer":"apk","package_arch":"aarch64_cortex-a53","repository_release_id":"20261027T123000","repository_index_sha256":"$INDEX_SHA","packages":[{"name":"new-signed-helper","version":"1.0-r1","sha256":"$HELPERSHA"}],"requirements":{"min_memory_mb":1,"min_storage_mb":1}}]}
EOF_NEW_APP
"$MANAGER" start install future-lan-tool || fail 'new approved app required router code change'
grep -Fqx "$(printf 'phase\tsuccess')" "$TMP/runtime/apps-operation.state" || fail 'future app install did not succeed'
grep -Fxq new-signed-helper "$APPS_TEST_INSTALLED" || fail 'future app package missing'
"$MANAGER" start remove future-lan-tool || fail 'future app removal not queued'
grep -Fqx "$(printf 'phase\tsuccess')" "$TMP/runtime/apps-operation.state" || fail 'future app removal did not succeed'
[ ! -s "$APPS_TEST_INSTALLED" ] || fail 'future app left behind an APK'
printf 'PASS: 신규 앱도 공유기 코드 변경 없이 서명된 패키지를 설치하고 제거함\n'

# App catalog enumeration must not be corrupted by the pin parser's counters.
# This reproduces a real 5-app catalog with Jarbis first (12 approved APKs).
# Earlier builds reset the outer status() index to 12 while scanning Jarbis,
# causing all four already-installed apps to incorrectly show "재설치".
python3 - "$TMP/catalog.json" "$APPS_TEST_INSTALLED" "$APPS_TEST_VERSION_DB" "$TMP/owned" <<'PY_STATUS_INDEX'
import json
import pathlib
import sys

catalog_path, installed_path, versions_path, owned_dir = map(pathlib.Path, sys.argv[1:])
sha = "a" * 64
names = ["jarbis"] + [f"jar-dependency-{i:02}" for i in range(1, 12)]
apps = [
    ("jarbis", names, {"type": "smartsafehub", "path": "#smarthome", "package": "jarbis"}),
    ("retro-arcade", ["smartsafehub-app-retro-arcade"], {"type": "static", "path": "/retro-arcade/", "package": "smartsafehub-app-retro-arcade"}),
    ("travelmate", ["travelmate", "luci-app-travelmate"], {"type": "luci", "path": "/cgi-bin/luci/admin/services/travelmate", "package": "luci-app-travelmate"}),
    ("wake-on-lan", ["etherwake", "luci-app-wol"], {"type": "luci", "path": "/cgi-bin/luci/admin/services/wol", "package": "luci-app-wol"}),
    ("network-usage-monitor", ["nlbwmon", "luci-app-nlbwmon", "luci-lib-chartjs"], {"type": "luci", "path": "/cgi-bin/luci/admin/status/nlbwmon", "package": "luci-app-nlbwmon"}),
]
entries = []
all_names = []
for app_id, packages, web_ui in apps:
    entries.append({
        "id": app_id,
        "version": "1.0-r1",
        "runtime": "router",
        "installer": "apk",
        "package_arch": "aarch64_cortex-a53",
        "repository_release_id": "20261027T123000",
        "repository_index_sha256": sha,
        "web_ui": web_ui,
        "packages": [{"name": name, "version": "1.0-r1", "sha256": sha} for name in packages],
        "requirements": {"min_memory_mb": 1, "min_storage_mb": 1},
    })
    all_names.extend(packages)
    # Only the app's primary is Apps-owned; shared runtimes are not adopted.
    (owned_dir / app_id).write_text(f"{packages[0]}\t1.0-r1\t{sha}\n")
catalog_path.write_text(json.dumps({
    "schema": 1,
    "device_code": "iptime-ax3000sm",
    "firmware_build_id": "mock-build-1",
    "channel": "stable",
    "apps": entries,
}))
installed_path.write_text("\n".join(all_names) + "\n")
versions_path.write_text("".join(f"{name} 1.0-r1\n" for name in all_names))
PY_STATUS_INDEX
"$TMP/bin/fetch-catalog"
for order in original reversed; do
    if [ "$order" = reversed ]; then
        python3 - "$TMP/catalog.json" <<'PY_REVERSE_STATUS'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    data = json.load(source)
data["apps"].reverse()
with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump(data, output)
PY_REVERSE_STATUS
        "$TMP/bin/fetch-catalog"
    fi
    "$MANAGER" status
    [ "$(wc -l < "$TMP/runtime/apps-status.tsv" | tr -d ' ')" -eq 5 ] || fail '설치 상태 조회에서 승인 앱 5개가 누락되었습니다'
    for app in jarbis retro-arcade travelmate wake-on-lan network-usage-monitor; do
        grep -Fq "$(printf '%s\t1\t1\t1\t' "$app")" "$TMP/runtime/apps-status.tsv" ||
            fail "설치된 앱 $app 가 다른 앱의 의존성 개수 때문에 재설치로 표시됩니다 ($order)"
    done
done
printf 'PASS: Jarbis 12개 의존성 조회 후에도 나머지 승인 앱 4개의 설치 상태와 소유권이 유지됨\n'

# Device regression: Apps recorded 1.2.0-r4; manual APK 1.3.0-r4 left a
# world identity pin; the server now offers 1.3.0-r6.
rm -f "$TMP/owned/"*
printf 'smartsafehub-app-retro-arcade\n' > "$APPS_TEST_INSTALLED"
printf 'smartsafehub-app-retro-arcade 1.3.0-r4\n' > "$APPS_TEST_VERSION_DB"
printf 'signed approved Retro r6\n' > "$TMP/repo/smartsafehub-app-retro-arcade-1.3.0-r6.apk"
DRIFT_SHA="$(sha256sum "$TMP/repo/smartsafehub-app-retro-arcade-1.3.0-r6.apk" | cut -d ' ' -f 1)"
cat > "$TMP/catalog.json" <<EOF_DRIFT
{"schema":1,"device_code":"iptime-ax3000sm","firmware_build_id":"mock-build-1","channel":"stable","apps":[{"id":"retro-arcade","version":"1.3.0-r6","runtime":"router","installer":"apk","package_arch":"aarch64_cortex-a53","repository_release_id":"20261027T123000","repository_index_sha256":"$INDEX_SHA","packages":[{"name":"smartsafehub-app-retro-arcade","version":"1.3.0-r6","sha256":"$DRIFT_SHA"}],"requirements":{"min_memory_mb":1,"min_storage_mb":1}}]}
EOF_DRIFT
"$TMP/bin/fetch-catalog"
export APPS_TEST_WORLD="$TMP/world"
printf 'smartsafehub-app-retro-arcade><Qlocal-test=\nother-app><Qunrelated=\n' > "$APPS_TEST_WORLD"
cp "$APPS_TEST_WORLD" "$TMP/world-before"
"$MANAGER" status
grep -Fqx "$(printf 'retro-arcade\t1\t1\t0\t0\t0\t1.3.0-r4')" "$TMP/runtime/apps-status.tsv" || fail 'manual app was adopted'
"$MANAGER" start update retro-arcade || fail 'unmanaged update not queued'
grep -Fqx "$(printf 'code\tE51')" "$TMP/runtime/apps-operation.state" || fail 'unmanaged update accepted'
printf 'smartsafehub-app-retro-arcade\t1.2.0-r4\t%s\n' "$RETROSHA" > "$TMP/owned/retro-arcade"
cp "$TMP/owned/retro-arcade" "$TMP/manifest-before"
"$MANAGER" status
grep -Fqx "$(printf 'retro-arcade\t1\t1\t1\t0\t1\t1.3.0-r4')" "$TMP/runtime/apps-status.tsv" || fail 'forward manual drift hid update'
cmp -s "$TMP/manifest-before" "$TMP/owned/retro-arcade" || fail 'status blessed local APK'
cp "$TMP/manifest-before" "$TMP/owned/other-app"
"$MANAGER" status
grep -Fqx "$(printf 'retro-arcade\t1\t1\t1\t0\t0\t1.3.0-r4\t0\treview_required')" "$TMP/runtime/apps-status.tsv" || fail 'missing blocked reason'
"$MANAGER" start update retro-arcade || fail 'conflicting ownership not queued'
grep -Fqx "$(printf 'code\tE52')" "$TMP/runtime/apps-operation.state" || fail 'conflicting owner upgrade accepted'
rm "$TMP/owned/other-app"
printf 'smartsafehub-app-retro-arcade 1.3.0-r6\n' > "$APPS_TEST_VERSION_DB"
"$MANAGER" start update retro-arcade || fail 'equal version not queued'
grep -Fqx "$(printf 'code\tE52')" "$TMP/runtime/apps-operation.state" || fail 'equal local build accepted'
cp "$TMP/catalog.json" "$TMP/drift-catalog"
python3 - "$TMP/catalog.json" <<'PY_DRIFT_DOWN'
import json, sys
p = sys.argv[1]
with open(p) as f:
    data = json.load(f)
data['apps'][0]['packages'][0]['version'] = '1.3.0-r4'
with open(p, 'w') as f:
    json.dump(data, f)
PY_DRIFT_DOWN
"$MANAGER" start update retro-arcade || fail 'drift downgrade not queued'
grep -Fqx "$(printf 'code\tE52')" "$TMP/runtime/apps-operation.state" || fail 'drift downgrade accepted'
cp "$TMP/drift-catalog" "$TMP/catalog.json"
printf 'smartsafehub-app-retro-arcade 1.3.0-r4\n' > "$APPS_TEST_VERSION_DB"
printf 'tampered\n' > "$TMP/repo/smartsafehub-app-retro-arcade-1.3.0-r6.apk"
"$MANAGER" start update retro-arcade || fail 'tampered drift update not queued'
grep -Fqx "$(printf 'code\tE33')" "$TMP/runtime/apps-operation.state" || fail 'tampered drift update accepted'
printf 'signed approved Retro r6\n' > "$TMP/repo/smartsafehub-app-retro-arcade-1.3.0-r6.apk"
export APPS_TEST_UPGRADE=1
"$MANAGER" start update retro-arcade || fail 'unsafe drift update not queued'
grep -Fqx "$(printf 'code\tE53')" "$TMP/runtime/apps-operation.state" || fail 'unsafe drift plan accepted'
unset APPS_TEST_UPGRADE
export APPS_TEST_INSTALL_FAIL=1
"$MANAGER" start update retro-arcade || fail 'failed drift update not queued'
grep -Fqx "$(printf 'code\tE54')" "$TMP/runtime/apps-operation.state" || fail 'failed drift update not reported'
unset APPS_TEST_INSTALL_FAIL
cmp -s "$TMP/world-before" "$APPS_TEST_WORLD" || fail 'failed update changed world constraints'
cmp -s "$TMP/manifest-before" "$TMP/owned/retro-arcade" || fail 'failed update changed receipt'
"$MANAGER" start update retro-arcade || fail 'drift retry not queued'
grep -Fqx "$(printf 'phase\tsuccess')" "$TMP/runtime/apps-operation.state" || fail 'forward drift retry failed'
grep -Fqx 'smartsafehub-app-retro-arcade=1.3.0-r6' "$APPS_TEST_WORLD" || fail 'exact APK world pin not committed'
grep -Fqx 'other-app><Qunrelated=' "$APPS_TEST_WORLD" || fail 'unrelated pin changed'
grep -Fqx "$(printf 'smartsafehub-app-retro-arcade\t1.3.0-r6\t%s' "$DRIFT_SHA")" "$TMP/owned/retro-arcade" || fail 'approved receipt not committed'
grep -Fqx "$(printf 'retro-arcade\t1\t1\t1\t0\t0\t1.3.0-r6')" "$TMP/runtime/apps-status.tsv" || fail 'post-update status not refreshed'
python3 - "$TMP/catalog.json" <<'PY_DRIFT_HASH'
import json, sys
p = sys.argv[1]
with open(p) as f:
    data = json.load(f)
data['apps'][0]['packages'][0]['sha256'] = 'b' * 64
with open(p, 'w') as f:
    json.dump(data, f)
PY_DRIFT_HASH
"$MANAGER" start update retro-arcade || fail 'same version different hash not queued'
grep -Fqx "$(printf 'code\tE52')" "$TMP/runtime/apps-operation.state" || fail 'same version different hash accepted'
"$MANAGER" start remove retro-arcade || fail 'removal after reconciliation not queued'
grep -Fqx "$(printf 'phase\tsuccess')" "$TMP/runtime/apps-operation.state" || fail 'removal after signed update failed'
[ ! -e "$TMP/owned/retro-arcade" ] || fail 'reconciled ownership not cleared'
unset APPS_TEST_WORLD
printf 'PASS: forward manual APK drift, identity pin, safe retry, ownership and same-version guards\n'

# Jarbis device regression: a local build has the same version as the
# current approval, but the Apps ownership receipt predates that build.
rm -f "$TMP/owned/"*
cat > "$TMP/catalog.json" <<EOF_JARBIS_REMOVE
{"schema":1,"device_code":"iptime-ax3000sm","firmware_build_id":"mock-build-1","channel":"stable","apps":[{"id":"jarbis","version":"0.2.4-r1","runtime":"router","installer":"apk","package_arch":"aarch64_cortex-a53","repository_release_id":"20261027T123000","repository_index_sha256":"$INDEX_SHA","web_ui":{"type":"smartsafehub","path":"#smarthome","package":"jarbis"},"packages":[{"name":"jarbis","version":"0.2.4-r1","sha256":"$DRIFT_SHA"},{"name":"mosquitto-ssl","version":"1.0-r1","sha256":"$RETROSHA"}],"requirements":{"min_memory_mb":1,"min_storage_mb":1}}]}
EOF_JARBIS_REMOVE
"$TMP/bin/fetch-catalog"
printf 'jarbis\nmosquitto-ssl\nother-app\n' > "$APPS_TEST_INSTALLED"
printf 'jarbis 0.2.4-r1\nmosquitto-ssl 1.0-r1\nother-app 1.0-r1\n' > "$APPS_TEST_VERSION_DB"
export APPS_TEST_WORLD="$TMP/world"
printf 'jarbis><Qlocal-test=\nmosquitto-ssl\nother-app><Qunrelated=\n' > "$APPS_TEST_WORLD"
cp "$APPS_TEST_WORLD" "$TMP/world-before-remove"
"$MANAGER" start remove jarbis || fail 'unmanaged removal not queued'
grep -Fqx "$(printf 'code\tE41')" "$TMP/runtime/apps-operation.state" || fail 'manual-only Jarbis removal accepted'
printf 'jarbis\t0.2.3-r1\t%s\n' "$RETROSHA" > "$TMP/owned/jarbis"
cp "$TMP/owned/jarbis" "$TMP/jarbis-receipt"
"$MANAGER" status
grep -Fqx "$(printf 'jarbis\t1\t1\t1\t1\t0\t0.2.4-r1')" "$TMP/runtime/apps-status.tsv" || fail 'same-version Jarbis incorrectly offered update'
"$MANAGER" start update jarbis || fail 'same-version update not queued'
grep -Fqx "$(printf 'code\tE52')" "$TMP/runtime/apps-operation.state" || fail 'same-version local Jarbis approved'
cp "$TMP/jarbis-receipt" "$TMP/owned/other-app"
"$MANAGER" start remove jarbis || fail 'conflicting remove not queued'
grep -Fqx "$(printf 'code\tE43')" "$TMP/runtime/apps-operation.state" || fail 'other owner removal accepted'
rm "$TMP/owned/other-app"
# Truncated and duplicate receipts must not authorize removal.
printf 'jarbis\t0.2.3-r1\t%s' "$RETROSHA" > "$TMP/owned/jarbis"
"$MANAGER" start remove jarbis || fail 'truncated receipt remove not queued'
grep -Fqx "$(printf 'code\tE42')" "$TMP/runtime/apps-operation.state" || fail 'truncated removal receipt accepted'
cat "$TMP/jarbis-receipt" "$TMP/jarbis-receipt" > "$TMP/owned/jarbis"
"$MANAGER" start remove jarbis || fail 'duplicate receipt remove not queued'
grep -Fqx "$(printf 'code\tE42')" "$TMP/runtime/apps-operation.state" || fail 'duplicate removal receipt accepted'
cp "$TMP/jarbis-receipt" "$TMP/owned/jarbis"
printf 'mosquitto-ssl\t1.0-r1\t%s\n' "$RETROSHA" >> "$TMP/owned/jarbis"
"$MANAGER" start remove jarbis || fail 'shared runtime remove not queued'
grep -Fqx "$(printf 'code\tE42')" "$TMP/runtime/apps-operation.state" || fail 'shared runtime ownership accepted'
cp "$TMP/jarbis-receipt" "$TMP/owned/jarbis"
export APPS_TEST_DEL_CORE=1
"$MANAGER" start remove jarbis || fail 'unsafe remove not queued'
grep -Fqx "$(printf 'code\tE44')" "$TMP/runtime/apps-operation.state" || fail 'core removal accepted with drift'
unset APPS_TEST_DEL_CORE
export APPS_TEST_DEL_KEEP=jarbis
"$MANAGER" start remove jarbis || fail 'retained package remove not queued'
grep -Fqx "$(printf 'code\tE44')" "$TMP/runtime/apps-operation.state" || fail 'incomplete removal plan accepted'
unset APPS_TEST_DEL_KEEP
export APPS_TEST_DEL_FAIL=1
"$MANAGER" start remove jarbis || fail 'failed remove not queued'
grep -Fqx "$(printf 'code\tE45')" "$TMP/runtime/apps-operation.state" || fail 'failed removal not reported'
unset APPS_TEST_DEL_FAIL
export APPS_TEST_DEL_COMMIT_KEEP=jarbis
"$MANAGER" start remove jarbis || fail 'incomplete commit not queued'
grep -Fqx "$(printf 'code\tE45')" "$TMP/runtime/apps-operation.state" || fail 'retained package reported as removed'
unset APPS_TEST_DEL_COMMIT_KEEP
cmp -s "$TMP/jarbis-receipt" "$TMP/owned/jarbis" || fail 'failed removal changed receipt'
cmp -s "$TMP/world-before-remove" "$APPS_TEST_WORLD" || fail 'failed removal changed world'
"$MANAGER" start remove jarbis || fail 'Jarbis removal retry not queued'
grep -Fqx "$(printf 'phase\tsuccess')" "$TMP/runtime/apps-operation.state" || fail 'same-version manual Jarbis removal failed'
[ ! -e "$TMP/owned/jarbis" ] || fail 'Jarbis receipt not cleared'
if grep -Fxq jarbis "$APPS_TEST_INSTALLED"; then fail 'Jarbis still installed'; fi
grep -Fxq mosquitto-ssl "$APPS_TEST_INSTALLED" || fail 'MQTT broker removed'
grep -Fxq other-app "$APPS_TEST_INSTALLED" || fail 'unrelated package removed'
if grep -q '^jarbis' "$APPS_TEST_WORLD"; then fail 'Jarbis identity pin remained'; fi
grep -Fxq 'other-app><Qunrelated=' "$APPS_TEST_WORLD" || fail 'unrelated pin removed'
grep -Fqx "$(printf 'jarbis\t0\t0\t0\t0\t0\t')" "$TMP/runtime/apps-status.tsv" || fail 'post-removal status stale'
unset APPS_TEST_WORLD
printf 'PASS: same-version manual Jarbis removal, ownership, solver and safe retry\n'
