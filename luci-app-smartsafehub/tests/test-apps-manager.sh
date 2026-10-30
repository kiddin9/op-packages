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
INDEX_SHA="$(sha256sum "$TMP/repo/packages.adb" | cut -d ' ' -f 1)"
ARCHIVE_SHA="$(sha256sum "$TMP/repo/nlbwmon-2025.06.02~29236be6-r1.apk" | cut -d ' ' -f 1)"
LUCISH="$(sha256sum "$TMP/repo/luci-app-nlbwmon-26.288.56989~75a306d.apk" | cut -d ' ' -f 1)"
CHARTSHA="$(sha256sum "$TMP/repo/luci-lib-chartjs-26.288.56989~75a306d.apk" | cut -d ' ' -f 1)"
RETROSHA="$(sha256sum "$TMP/repo/smartsafehub-app-retro-arcade-1.0.0-r1.apk" | cut -d ' ' -f 1)"
ETHERSHA="$(sha256sum "$TMP/repo/etherwake-1.09-r5.apk" | cut -d ' ' -f 1)"
WOLSHA="$(sha256sum "$TMP/repo/luci-app-wol-26.288.56989~75a306d.apk" | cut -d ' ' -f 1)"
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
 https://repo.smartsafehub.com/stable/packages/aarch64_cortex-a53/smartsafehub/20261027T123000/packages.adb)
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
 https://repo.smartsafehub.com/stable/packages/aarch64_cortex-a53/smartsafehub/20261027T123000/etherwake-1.09-r5.apk)
   cp "$APPS_TEST_REPO/etherwake-1.09-r5.apk" "$dest";;
 https://repo.smartsafehub.com/stable/packages/aarch64_cortex-a53/smartsafehub/20261027T123000/luci-app-wol-26.288.56989~75a306d.apk)
   cp "$APPS_TEST_REPO/luci-app-wol-26.288.56989~75a306d.apk" "$dest";;
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
   if [ -s "${local_index%/*}/smartsafehub-app-retro-arcade-1.0.0-r1.apk" ] ||
      [ -s "${local_index%/*}/smartsafehub-app-retro-arcade-1.1.0-r1.apk" ]; then
     [ "$(find "${local_index%/*}" -name '*.apk' | wc -l | tr -d ' ')" -eq 1 ] || exit 2
   elif [ -s "${local_index%/*}/etherwake-1.09-r5.apk" ] ||
        [ -s "${local_index%/*}/luci-app-wol-26.288.56989~75a306d.apk" ]; then
     [ "$(find "${local_index%/*}" -name '*.apk' | wc -l | tr -d ' ')" -eq 2 ] || exit 2
     for name in etherwake-1.09-r5 luci-app-wol-26.288.56989~75a306d; do
       [ -s "${local_index%/*}/$name.apk" ] || exit 2
     done
   else
     for name in nlbwmon-2025.06.02~29236be6-r1 \
         luci-app-nlbwmon-26.288.56989~75a306d \
         luci-lib-chartjs-26.288.56989~75a306d; do
       [ -s "${local_index%/*}/$name.apk" ] || exit 2
     done
   fi
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
     exit 0
   fi
   shift
   for item in "$@"; do grep -vxF "$item" "$APPS_TEST_INSTALLED" > "$APPS_TEST_INSTALLED.new" || :; mv "$APPS_TEST_INSTALLED.new" "$APPS_TEST_INSTALLED"; done
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
   hub:nlbwmon|hub:luci-app-nlbwmon|hub:luci-lib-chartjs|hub:smartsafehub-app-retro-arcade|hub:etherwake|hub:luci-app-wol) ;;
   *) exit 2;;
  esac
  if [ "${APPS_TEST_UPGRADE:-0}" = 1 ]; then
    echo '(1/3) Upgrading luci-base (mock)'
  elif [ "$upgrade" = 1 ]; then
    echo "(1/1) Upgrading $name (mock)"
  else
    echo "(1/2) Installing $name (mock)"
  fi
 done
 exit 0
fi
for pin in "$@"; do
 name="${pin%%=*}"
 case "$repo:$name" in
  hub:nlbwmon|hub:luci-app-nlbwmon|hub:luci-lib-chartjs|hub:smartsafehub-app-retro-arcade|hub:etherwake|hub:luci-app-wol) ;;
  *) exit 2;;
 esac
 grep -qxF "$name" "$APPS_TEST_INSTALLED" 2>/dev/null || printf '%s\n' "$name" >> "$APPS_TEST_INSTALLED"
 if [ "$upgrade" = 1 ]; then
  awk -v n="$name" '$1 != n' "$APPS_TEST_VERSION_DB" > "$APPS_TEST_VERSION_DB.tmp"
  printf '%s %s\n' "$name" "${pin#*=}" >> "$APPS_TEST_VERSION_DB.tmp"
  mv -f "$APPS_TEST_VERSION_DB.tmp" "$APPS_TEST_VERSION_DB"
 fi
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
export SMARTSAFEHUB_APPS_UCLIENT_BIN="$TMP/bin/uclient-fetch"
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
path=sys.argv[1]; obj=json.load(open(path)); obj['apps'][0]['packages'].pop()
open(path,'w').write(json.dumps(obj))
PY_BAD
"$MANAGER" start install network-usage-monitor || fail 'partial package set did not queue'
grep -Fqx "$(printf 'code\tE27')" "$TMP/runtime/apps-operation.state" || fail 'partial package set accepted'
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
# Installed APK changed outside Apps ownership: never perform another upgrade.
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
# An extra/omitted package in a bad catalog must be rejected before any APK
# download/install, even if the index and SHA values look valid.
python3 - "$TMP/catalog.json" <<'PY_WOL_EXTRA'
import json,sys
p=sys.argv[1]; data=json.load(open(p))
data['apps'][0]['packages'].append({'name':'luci-app-nlbwmon','version':'26.288.56989~75a306d','sha256': 'b'*64})
open(p,'w').write(json.dumps(data))
PY_WOL_EXTRA
"$MANAGER" start install wake-on-lan || fail 'bad WOL catalog not queued'
grep -Fqx "$(printf 'code\tE27')" "$TMP/runtime/apps-operation.state" || fail 'WOL extra APK was not rejected'
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
