#!/bin/sh

# 功能入口负责命令执行；相邻 ucode 脚本只校验、转换及生成数据。
. /usr/lib/hijpass/common.sh

data="$HIJPASS_LIB/core/releasecli.uc"
action=${1:-}; core=${2:-}
case "$core" in xray|sing-box) ;; *) hijpass_json_error 'core action and name are required'; exit 1 ;; esac
case "$action" in version|latest|update) ;; *) hijpass_json_error 'unknown core update action'; exit 1 ;; esac
work=
temp=
stage=release
committed=0
started=$(date +%s)
trap 'code=$?; if [ -n "$temp" ]; then rm -f "$temp"; fi; rm -rf "$work"; if [ "$action" = update ] && [ "$code" -ne 0 ]; then hijpass_log ERROR "$core update failed: stage=$stage, exit=$code, binary_replaced=$committed"; fi' EXIT
if [ "$action" = version ]; then
    output=$("/usr/bin/$core" version 2>/dev/null) || output=
    printf '%s\n' "$output" | hijpass_run_ucode "$data" version "$core"
    exit $?
fi
if [ "$action" = update ]; then
    hijpass_progress metadata "$core"
    hijpass_lock_updates || { hijpass_json_error 'another update or service operation is running'; exit 75; }
    output=$("/usr/bin/$core" version 2>/dev/null) || output=
    current=$(printf '%s\n' "$output" | hijpass_run_ucode "$data" version "$core") || current='{}'
    json_load "$current"
    json_get_var current_version version
    hijpass_log INFO "$core update started: current=${current_version:-unknown}, architecture=$(uname -m)"
fi
url=$(hijpass_run_ucode "$data" source "$core") || exit 1
if [ "$action" = update ]; then
    release=$(hijpass_run_logged "Fetch $core release metadata" curl -f -sS -L --max-time 10 "$url") || { hijpass_json_error 'cannot fetch core release'; exit 1; }
else
    release=$(curl -f -sS -L --max-time 10 "$url") || { hijpass_json_error 'cannot fetch core release'; exit 1; }
fi
if [ "$action" = latest ]; then printf '%s\n' "$release" | hijpass_run_ucode "$data" latest "$core"; exit $?; fi
plan=$(printf '%s\n' "$release" | hijpass_run_ucode "$data" plan "$core" "$(uname -m)") || { printf '%s\n' "$plan"; exit 1; }
json_load "$plan" || exit 1
json_get_vars version number name url digest destination archive
work="$HIJPASS_JOB_ROOT/work"
rm -rf "$work" && mkdir -m 700 "$work" || exit 1
download="$work/$name"
hijpass_log INFO "$core downloading target=$number"
stage=download
hijpass_progress download "$name" "$download"
hijpass_run_logged "Download $core archive" curl -f -sS -L --max-time 120 -o "$download" -- "$url" || { hijpass_json_error 'core download failed'; exit 1; }
stage=checksum
hijpass_progress verify "$name"
actual=$(sha256sum "$download") || { hijpass_json_error 'cannot checksum archive'; exit 1; }
actual=${actual%% *}
[ "$actual" = "$digest" ] || { hijpass_json_error 'archive checksum verification failed'; exit 1; }
hijpass_log INFO "$core archive verified: bytes=$(wc -c <"$download")"
stage=extraction
hijpass_progress extract "$name"
# 只提取目标核心，不展开其它归档成员；二进制始终流式复制。
if [ "$archive" = zip ]; then
    hijpass_run_logged "Extract $core archive" unzip -q "$download" xray -d "$work" || { hijpass_json_error 'cannot extract core'; exit 1; }
    binary="$work/xray"
else
    members=$(hijpass_run_logged "Inspect $core archive" tar -tzf "$download") || { hijpass_json_error 'invalid core archive'; exit 1; }
    member=$(printf '%s\n' "$members" | hijpass_run_ucode "$data" member "$core") || exit 1
    hijpass_run_logged "Extract $core archive" tar -xzf "$download" -C "$work" "$member" || { hijpass_json_error 'cannot extract core'; exit 1; }
    binary="$work/$member"
fi
stage=binary-verification
hijpass_progress verify "$core"
chmod 755 "$binary" && output=$("$binary" version) || { hijpass_json_error 'binary verification failed'; exit 1; }
checked=$(printf '%s\n' "$output" | hijpass_run_ucode "$data" version "$core") || exit 1
json_load "$checked" || exit 1
json_get_var installed version
[ "$installed" = "$number" ] || { hijpass_json_error 'binary verification failed'; exit 1; }
# 同目录临时文件验证成功后再替换，失败始终保留原核心。
rm -f "$destination".new.* || { hijpass_json_error 'cannot remove old staged core'; exit 1; }
temp="$destination.new.$$"
stage=installation
hijpass_progress install "$core"
hijpass_run_logged "Save staged $core binary" cp "$binary" "$temp" || { hijpass_json_error 'cannot save staged core'; exit 1; }
hijpass_run_logged "Set $core binary permissions" chmod 755 "$temp" || { hijpass_json_error 'cannot set core permissions'; exit 1; }
hijpass_run_logged "Replace installed $core binary" mv -f "$temp" "$destination" || { hijpass_json_error 'cannot replace installed core'; exit 1; }
temp=
committed=1
hijpass_log INFO "$core installed: version=$number, elapsed=$(($(date +%s) - started))s"
hijpass_run_ucode "$data" result "$core" "$version"
