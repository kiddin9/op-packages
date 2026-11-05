#!/bin/sh
# doctor.sh — 环境体检判据（唯一实现，两套入口共用）
#
# 消费者：
#   1) isp-split doctor [--json]    （files/usr/sbin/isp-split 里 source 本文件）
#   2) tools/router-preflight.sh    （部署前预检，source 同一份函数）
# 为什么共用：preflight 与 doctor 回答的是同一件事——"这台机器上的前提还在不在"。
# 两套判据各写一份的历史（F7）已经证明会立刻漂移，所以判据函数只在这里。
#
# 设计红线（AUDIT-SECURITY-v2 第三部分 C0）：
#   1. 不产生业务流量：不做 DNS 查询、不连外网、不 STUN。功能验证归其它子命令。
#   2. 不写系统配置：本文件唯一的写操作是 /tmp 下的临时文件（当前实现为零临时文件）。
#   3. 不假设工具存在：ss/lsof/pgrep/jq 一律按"可能没有"写；主判据落在
#      /proc、/sys、uci、nft、ip 五样上。
#   4. 永不 die：任何探针失败降级为 unknown + probe_errors（与 need_nft 的 die
#      风格相反，是有意的：体检要在半坏的机器上仍然说得上话）。
#
# 探针原语 P1–P11 一次定义、六项检查复用：`nft -a list ruleset` 全量只跑一次
# （DOC_P4），检查三/五共享，这是结构性保证而不是纪律要求。
#
# busybox 兼容：无 strtonum（十六进制统一走 printf/$(( ))）、无 and()/or()
# （位运算在 shell 里做）、ERE 里不写 \{ \}（busybox awk 会报 Invalid contents）。
set -u

DOC_SCHEMA=1
# 探针登记表默认先建好：本文件允许被单独 source（preflight 就只取主机判据），
# 此时 doc_main 还没跑，任何 _doc_probe 调用都不能因为 set -u 直接退出。
DOC_PROBES=""
DOC_PROBE_ERR=""
# mwan3 标记位段的默认值。真值永远取 mwan3.globals.mmx_mask（P11），
# 这里只是"读不到时"的兜底：硬编码 0x3f00 会在改过 mmx_mask 的机器上全盘误判。
DOC_MASK_DEFAULT=0x3F00
# mwan3 的 ip rule 起始 pref 兜底值（实测 2005）。真值优先从 P5 现算。
DOC_MINPREF_FALLBACK=2005

# ---------------------------------------------------------------- 小工具

_doc_have() { command -v "$1" >/dev/null 2>&1; }

# JSON 转义：优先复用主脚本的 _lc_json_esc（同一份语义，避免两套转义规则）。
_doc_esc() {
	# 快路径：不含引号/反斜杠/控制字符时直接输出（printf 是内建，零 fork）。
	case "${1:-}" in
	*'"'* | *'\\'* | *[[:cntrl:]]*) ;;
	*) printf '%s' "${1:-}" && return 0 ;;
	esac
	if _doc_have _lc_json_esc; then
		_lc_json_esc "${1:-}"
		return 0
	fi
	printf '%s' "${1:-}" |
		sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/ /g' |
		tr -d '\r\n' |
		sed -e 's/[[:cntrl:]]//g'
}

# 带引号的 JSON 字符串；空值/未知一律输出 null（UI 才不会把 "" 当"有值"）
_doc_jstr() {
	case "${1:-}" in
	"") printf 'null' ;;
	*) printf '"%s"' "$(_doc_esc "$1")" ;;
	esac
}

_doc_jbool() { [ "${1:-0}" = "1" ] && printf 'true' || printf 'false'; }

# 0x.. -> 十进制。空串/非法 -> 0（调用方不因此 die）。
_doc_hex() {
	case "${1:-}" in
	0x* | 0X*) ;;
	*)
		printf '0'
		return 0
		;;
	esac
	printf '%d' "$(( $1 ))" 2>/dev/null || printf '0'
}

# 同上，但结果放全局 HEX：循环里用它可以完全避免 fork（x86 VM 上 148 个写者
# 从 4.2s 降到 <1s）。用法：_doc_hx "$v"; _owned=$(( HEX & _M ))。
_doc_hx() {
	case "${1:-}" in
	0x* | 0X* | [0-9]*) HEX=$(( $1 )) 2>/dev/null || HEX=0 ;;
	*) HEX=0 ;;
	esac
}

# 十进制 -> 0x 小写字符串（用于 JSON 里的掩码/值展示）
_doc_hxstr() {
	printf '0x%x' "$(( ${1:-0} & 0xffffffff ))" 2>/dev/null || printf '0x0'
}

# grep -c 在"0 匹配"时已经打印了 0、却返回 1；写成 `|| printf 0` 会多打一行，
# 拼进 JSON 就变成 "0\n0"（本文件第一版踩过）。所有计数统一走这两个函数。
_doc_cnt() { # stdin -> 非空行数
	_dc=$(grep -c . 2>/dev/null) || true
	case "${_dc:-}" in '' | *[!0-9]*) _dc=0 ;; esac
	printf '%s' "$_dc"
}

_doc_cnt_pat() { # <pattern> stdin -> 匹配行数
	_dcp=$(grep -c -- "$1" 2>/dev/null) || true
	case "${_dcp:-}" in '' | *[!0-9]*) _dcp=0 ;; esac
	printf '%s' "$_dcp"
}

_doc_bool_uci() {
	case "${1:-}" in
	1 | true | TRUE | yes | on) printf '1' ;;
	*) printf '0' ;;
	esac
}

# 毫秒时间戳（busybox 的 date 没有 %N，用 /proc/uptime 的百分秒）
_doc_now_ms() {
	awk '{ printf "%d", $1 * 1000 }' /proc/uptime 2>/dev/null || printf '0'
}

# 时间文本：主脚本的 _ts_text 需要一个 epoch 参数（不是无参调用），
# sed/mawk 时代的实现差异在这里吃掉，命令行文本才不会变成 "-"。
_doc_ts_text() {
	if _doc_have _ts_text; then
		_ts_text "${DOC_GEN:-$(date +%s 2>/dev/null)}"
	else
		date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf '-'
	fi
}

# 探针登记：JSON 里必须始终有 probes / probe_errors 两个数组——
# "缺探针"不等于"没问题"，这是 unknown 从哪来的溯源。
_doc_probe() { # <id> <rc> <k=v...>
	_dp_id=$1
	_dp_rc=$2
	shift 2
	_dp_extra=""
	for _dp_kv in "$@"; do
		case "$_dp_kv" in
		*=*)
			_dp_k=${_dp_kv%%=*}
			_dp_v=${_dp_kv#*=}
			case "$_dp_v" in
			'' | *[!0-9]*) continue ;;
			esac
			_dp_extra="${_dp_extra}${_dp_extra:+,}\"$(_doc_esc "$_dp_k")\":$_dp_v"
			;;
		esac
	done
	DOC_PROBES="${DOC_PROBES}${DOC_PROBES:+,}{\"id\":\"$(_doc_esc "$_dp_id")\",\"rc\":$_dp_rc${_dp_extra:+,$_dp_extra}}"
}

_doc_probe_err() { # <probe> <cmd> <note>
	DOC_PROBE_ERR="${DOC_PROBE_ERR}${DOC_PROBE_ERR:+,}{\"probe\":$(_doc_jstr "$1"),\"cmd\":$(_doc_jstr "$2"),\"note\":$(_doc_jstr "$3")}"
}

# ---------------------------------------------------------------- 主机前提（preflight 共用判据）
#
# 任务书要求 doctor 收敛 tools/router-preflight.sh 的判据：固件 / 内存 / nft 版本 /
# mwan3-nft 存在性 / 依赖二进制。这五项在这里各有一个函数，preflight 直接调用，
# doctor 也直接用它们的返回值填 host 块——一份判据，两套出口。

doc_host_firmware() {
	DOC_FW_ID=""
	DOC_FW_RELEASE=""
	DOC_FW_TARGET=""
	DOC_FW_REV=""
	DOC_FW_DESC=""
	DOC_ARCH=$(uname -m 2>/dev/null) || DOC_ARCH=""
	[ -f /etc/openwrt_release ] || return 1
	# 用 sed 取值而不是 `. /etc/openwrt_release`：source 会覆盖调用方的同名变量
	# （preflight 以前就是这么干的），共享函数里不能有这种副作用。
	DOC_FW_ID=$(sed -n "s/^DISTRIB_ID='\(.*\)'$/\1/p" /etc/openwrt_release 2>/dev/null | head -1)
	DOC_FW_RELEASE=$(sed -n "s/^DISTRIB_RELEASE='\(.*\)'$/\1/p" /etc/openwrt_release 2>/dev/null | head -1)
	DOC_FW_TARGET=$(sed -n "s/^DISTRIB_TARGET='\(.*\)'$/\1/p" /etc/openwrt_release 2>/dev/null | head -1)
	DOC_FW_REV=$(sed -n "s/^DISTRIB_REVISION='\(.*\)'$/\1/p" /etc/openwrt_release 2>/dev/null | head -1)
	DOC_FW_DESC=$(sed -n "s/^DISTRIB_DESCRIPTION='\(.*\)'$/\1/p" /etc/openwrt_release 2>/dev/null | head -1)
	[ -n "$DOC_FW_ID" ] || DOC_FW_ID="OpenWrt"
	return 0
}

# 内存：数据管线峰值约为几个 MB（awk 流式处理），这里只挡"明显不够"的机器。
#   total < 32MiB  -> warn（可能跑不动 1.3 万条 CIDR 的互斥化）
#   avail < 8MiB   -> warn（同步时其它进程可能 OOM）
doc_host_mem() {
	DOC_MEM_TOTAL_KB=0
	DOC_MEM_AVAIL_KB=0
	DOC_MEM_VERDICT=unknown
	_doc_mem=$(sed -n 's/^MemTotal:[[:space:]]*\([0-9]*\).*/\1/p' /proc/meminfo 2>/dev/null | head -1)
	_doc_avail=$(sed -n 's/^MemAvailable:[[:space:]]*\([0-9]*\).*/\1/p' /proc/meminfo 2>/dev/null | head -1)
	# 老内核（4.14 之前）没有 MemAvailable：用 MemFree 兜底
	if [ -z "${_doc_avail:-}" ]; then
		_doc_avail=$(sed -n 's/^MemFree:[[:space:]]*\([0-9]*\).*/\1/p' /proc/meminfo 2>/dev/null | head -1)
	fi
	case "${_doc_mem:-}" in '' | *[!0-9]*) _doc_mem=0 ;; esac
	case "${_doc_avail:-}" in '' | *[!0-9]*) _doc_avail=0 ;; esac
	DOC_MEM_TOTAL_KB=$_doc_mem
	DOC_MEM_AVAIL_KB=$_doc_avail
	if [ "$_doc_mem" -eq 0 ]; then
		DOC_MEM_VERDICT=unknown
	elif [ "$_doc_mem" -lt 32768 ] || { [ "$_doc_avail" -gt 0 ] && [ "$_doc_avail" -lt 8192 ]; }; then
		DOC_MEM_VERDICT=warn
	else
		DOC_MEM_VERDICT=ok
	fi
	printf '%s\n' "$DOC_MEM_VERDICT"
}

# nft 版本：>= 1.0 才具备本仓库依赖的 `-a` / `list counters` 行为。
doc_nft_version() {
	DOC_NFT_VERSION=""
	DOC_NFT_FULL=""
	DOC_NFT_OK=0
	DOC_NFT_MAJOR=0
	if ! _doc_have nft; then
		return 1
	fi
	DOC_NFT_FULL=$(nft --version 2>/dev/null | head -1)
	DOC_NFT_VERSION=$(nft --version 2>/dev/null | head -1 |
		sed -n 's/.*v\([0-9][0-9.]*\).*/\1/p')
	[ -n "$DOC_NFT_VERSION" ] || DOC_NFT_VERSION=$(nft --version 2>/dev/null | awk '{print $2}' | head -1)
	DOC_NFT_MAJOR=$(printf '%s' "$DOC_NFT_VERSION" | cut -d. -f1)
	case "$DOC_NFT_MAJOR" in '' | *[!0-9]*) DOC_NFT_MAJOR=0 ;; esac
	[ "$DOC_NFT_MAJOR" -ge 1 ] 2>/dev/null && DOC_NFT_OK=1
	return 0
}

doc_mwan3_installed() { [ -f /lib/mwan3/mwan3.sh ]; }

# mwan3 是不是 nftables 版：判据沿用 install.sh / preflight，只此一处
# （grep render_config_ipsets）。iptables 版装上去不会报错，只会静默不生效。
doc_mwan3_is_nft() {
	doc_mwan3_installed || return 1
	grep -q render_config_ipsets /lib/mwan3/mwan3.sh 2>/dev/null
}

doc_mwan3_table() {
	_doc_have nft || return 1
	nft list table inet mwan3 >/dev/null 2>&1 && return 0
	# 3.6 的 nft 端口用 inet；个别固件（Kwrt 兼容层 / iptables-nft 残留）会同时
	# 留 ip、ip6 同名表。判据是"表在不在"，不能被 family 写死：只认 inet 会让
	# ip mwan3 里的 mwan3 自家规则整表落到 legacy 分支（fix38 的误报根因之一）。
	nft list table ip mwan3 >/dev/null 2>&1 && return 0
	nft list table ip6 mwan3 >/dev/null 2>&1 && return 0
	return 1
}

# 版本（P10）：opkg 与 apk 双分支；两者都没有 -> 空（不判"漂移"，判 unknown）
doc_pkg_version() {
	_dv_pkg=$1
	_dv_out=""
	if _doc_have opkg; then
		_dv_out=$(opkg list-installed 2>/dev/null |
			awk -v p="$_dv_pkg" '$1 == p { print $3; exit }')
	fi
	if [ -z "$_dv_out" ] && _doc_have apk; then
		# apk 的列形如 "mwan3-3.6.12-r5 x86_64 {...} [installed]"：
		# 只剥掉 "<包名>-" 前缀，剩下的整段（3.6.12-r5）才是版本。
		_dv_out=$(apk list -I 2>/dev/null |
			awk -v p="$_dv_pkg" 'index($1, p "-") == 1 {
				v = $1; sub("^" p "-", "", v); print v; exit }')
	fi
	printf '%s' "$_dv_out"
}

# 依赖二进制：必需项（缺了核心功能就不成立）与可选项分开，供 gate 使用。
DOC_BIN_REQUIRED="nft uci curl awk sed grep ip"
DOC_BIN_OPTIONAL="socat conntrack ubus jsonfilter dnsmasq ss"
doc_bins() {
	DOC_BINS_JSON=""
	DOC_BINS_HAVE=""
	DOC_BINS_MISSING=""
	_bn_all=0
	for _bn in $DOC_BIN_REQUIRED $DOC_BIN_OPTIONAL; do
		_bn_have=0
		_doc_have "$_bn" && _bn_have=1
		DOC_BINS_JSON="${DOC_BINS_JSON}${DOC_BINS_JSON:+,}\"$(_doc_esc "$_bn")\":$(_doc_jbool "$_bn_have")"
		[ "$_bn_have" = "1" ] && DOC_BINS_HAVE="${DOC_BINS_HAVE:+$DOC_BINS_HAVE }$_bn"
		case " $DOC_BIN_REQUIRED " in
		*" $_bn "*)
			[ "$_bn_have" = "0" ] && DOC_BINS_MISSING="${DOC_BINS_MISSING:+$DOC_BINS_MISSING }$_bn"
			;;
		esac
	done
	return 0
}

# 某个命令在不在（doc_bins 的结论；preflight 用它替代自己写 command -v）
doc_bin_have() {
	case " ${DOC_BINS_HAVE:-} " in
	*" $1 "*) return 0 ;;
	esac
	return 1
}

# ---------------------------------------------------------------- 探针 P1–P11

# P11：位段真值。空 -> 默认 0x3F00，并记录来源（默认值 vs 用户配置）。
doc_p11_mask() {
	[ "${DOC_P11_DONE:-0}" = "1" ] && return 0
	DOC_P11_DONE=1
	DOC_MMX_MASK=""
	DOC_MMX_SOURCE="default"
	_doc_mask=$(uci -q get mwan3.globals.mmx_mask 2>/dev/null) || _doc_mask=""
	case "${_doc_mask:-}" in
	0x* | 0X* | 0[0-9]* | [1-9]*)
		DOC_MMX_MASK="$_doc_mask"
		DOC_MMX_SOURCE="uci mwan3.globals.mmx_mask"
		;;
	esac
	[ -n "$DOC_MMX_MASK" ] || DOC_MMX_MASK=$DOC_MASK_DEFAULT
	DOC_MMX_MASK_DEC=$(_doc_hex "$DOC_MMX_MASK")
	_doc_probe P11 0
}

# P1：谁在听 :53。/proc/net 是硬证据，ss/netstat 只作加速器（可能没编进固件）。
doc_p1_listen() {
	[ "${DOC_P1_DONE:-0}" = "1" ] && return 0
	DOC_P1_DONE=1
	DOC_P1_TSV=""
	DOC_P1_RC=0
	if [ -r /proc/net/udp ]; then
		DOC_P1_TSV=$(awk 'FNR > 1 && $2 ~ /:0035$/ { print "udp\t" FILENAME "\t" $2 "\t" $4 "\t" $10 }' \
			/proc/net/udp /proc/net/udp6 2>/dev/null)
	else
		DOC_P1_RC=1
	fi
	if [ -r /proc/net/tcp ]; then
		DOC_P1_TCP=$(awk 'FNR > 1 && $2 ~ /:0035$/ && $4 == "0A" { print "tcp\t" FILENAME "\t" $2 "\t" $4 "\t" $10 }' \
			/proc/net/tcp /proc/net/tcp6 2>/dev/null)
		DOC_P1_TSV="${DOC_P1_TSV}${DOC_P1_TSV:+
}${DOC_P1_TCP}"
	fi
	DOC_P1_ROWS=$(printf '%s\n' "$DOC_P1_TSV" | _doc_cnt)
	_doc_probe P1 "$DOC_P1_RC" "rows=$DOC_P1_ROWS"
	# P1b 加速器：只用于交叉验证，不存在不报错
	if _doc_have ss; then
		DOC_P1B=$(ss -lunp 2>/dev/null | _doc_cnt_pat ':53 ')
		_doc_probe P1b 0 "rows=$DOC_P1B"
	else
		_doc_probe_err P1b "ss -lunp" "ss 不存在，已跳过（不影响结论）"
	fi
}

# 十六进制地址 -> 点分十进制 / "::" / "v6"。只做展示与"是否回环"两类判断，
# 不追求完整的 v6 格式化（没有消费方需要）。
_doc_addr_of() {
	_da_h=$(printf '%s' "$1" | awk -F: '{ print $1 }')
	_da_v6=0
	case "$_da_h" in
	????????????????????????????????) _da_v6=1 ;;
	esac
	if [ "$_da_v6" = "1" ]; then
		case "$_da_h" in
		00000000000000000000000000000000) printf '::' ;;
		*0000000000000000000000000100007F) printf '127.0.0.1' ;;
		*) printf 'v6:%s' "$(printf '%s' "$_da_h" | cut -c1-8)" ;;
		esac
		return 0
	fi
	printf '%s' "$_da_h" | awk '{
		h = toupper($0)
		d = "0123456789ABCDEF"
		n = 0
		for (i = 1; i <= 8; i += 2)
			b[++n] = (index(d, substr(h, i, 1)) - 1) * 16 + index(d, substr(h, i + 1, 1)) - 1
		printf "%d.%d.%d.%d", b[4], b[3], b[2], b[1]
	}'
}

_doc_is_loopback() {
	case "$1" in
	127.* | ::1 | "::") return 0 ;;
	esac
	return 1
}

# P2：inode -> pid -> comm。一次性把 /proc/*/fd 的符号链接表读进变量，
# 之后逐 inode 匹配，避免每个监听者都把整个 /proc 扫一遍。
doc_p2_map() {
	[ "${DOC_P2_DONE:-0}" = "1" ] && return 0
	DOC_P2_DONE=1
	DOC_P2_MAP=""
	DOC_P2_RC=0
	# ls 在非 root 下会因为读不到别人的 fd 目录而返回非 0；只认"表是不是空的"
	DOC_P2_MAP=$(ls -l /proc/[0-9]*/fd 2>/dev/null)
	[ -n "$DOC_P2_MAP" ] || DOC_P2_RC=1
	_doc_probe P2 "$DOC_P2_RC"
}

# inode -> "pid comm"，找不到输出空
_doc_pid_of_inode() {
	# busybox 的 `ls -l /proc/*/fd` 每个目录打一行 "/proc/<pid>/fd:" 头，
	# 条目只有裸文件名（"7 -> socket:[1234]"）；GNU ls 会把完整路径写进条目。
	# 两种都得认，否则 pid 永远是空 -> "谁在听 :53" 全线失效（VM 实测过）。
	_dpi_pid=$(printf '%s\n' "${DOC_P2_MAP:-}" | awk -v ino="$1" '
		/\/fd:$/ {
			p = $0
			sub(/^.*\/proc\//, "", p)
			sub(/\/fd:$/, "", p)
			pid = p
			next
		}
		{
			if (index($0, "socket:[" ino "]") == 0) next
			if (match($0, /\/proc\/[0-9]+\/fd\//)) {
				t = substr($0, RSTART + 6, RLENGTH - 6)
				sub(/\/fd\/$/, "", t)
				pid = t
			}
			print pid
			exit
		}')
	[ -n "${_dpi_pid:-}" ] || return 1
	_dpi_comm=$(cat "/proc/$_dpi_pid/comm" 2>/dev/null | tr -d '\n')
	printf '%s %s\n' "$_dpi_pid" "${_dpi_comm:-?}"
}

# P3：dnsmasq confdir 真值。四级优先级（runtime -> ps -> uci -> default）的实现
# 只有主脚本里的 _dns_confdir_detect 一份；doctor 直接复用它（同一 shell 里
# source 进来时就是同一个函数），独立运行时才用下面的精简兜底。
doc_p3_confdir() {
	[ "${DOC_P3_DONE:-0}" = "1" ] && return 0
	DOC_P3_DONE=1
	DOC_P3_SOURCE=""
	DOC_P3_DIRS=""
	DOC_P3_DETAIL=""
	DOC_P3_RC=0
	if _doc_have _dns_confdir_detect; then
		_dns_confdir_detect >/dev/null 2>&1
		DOC_P3_SOURCE=${DNS_CONFDIR_SOURCE:-}
		DOC_P3_DIRS=${DNS_CONFDIR_DIRS:-}
		DOC_P3_DETAIL=${DNS_CONFDIR_DETAIL:-}
		[ -n "$DOC_P3_SOURCE" ] || DOC_P3_SOURCE="unknown"
	else
		# 兜底：uci 值 -> 运行配置里的 conf-dir= -> 默认目录
		_doc_cd=$(uci -q get dhcp.@dnsmasq[0].confdir 2>/dev/null) || _doc_cd=""
		if [ -n "${_doc_cd:-}" ]; then
			DOC_P3_SOURCE="uci"
			DOC_P3_DETAIL="dhcp.@dnsmasq[0].confdir"
			DOC_P3_DIRS=$(printf '%s\n' "$_doc_cd" | tr ' ' '\n' | sed 's/,$//' | grep -v '^$' | tr '\n' ' ')
		else
			_doc_cd=$(sed -n 's/^[[:space:]]*conf-dir=//p' ${DNSMASQ_CONF_GLOB:-/var/etc/dnsmasq.conf.*} 2>/dev/null |
				head -1 | sed 's/,.*$//; s/[[:space:]]*$//')
			if [ -n "${_doc_cd:-}" ]; then
				DOC_P3_SOURCE="runtime"
				DOC_P3_DETAIL="${DNSMASQ_CONF_GLOB:-/var/etc/dnsmasq.conf.*}"
				DOC_P3_DIRS=$_doc_cd
			else
				DOC_P3_SOURCE="default"
				DOC_P3_DETAIL="dnsmasq 默认目录"
				DOC_P3_DIRS=${DNSMASQ_DEFAULT_DIR:-/tmp/dnsmasq.d}
			fi
		fi
	fi
	_doc_probe P3 "$DOC_P3_RC" "rows=$(printf '%s\n' "$DOC_P3_DIRS" | wc -w | tr -d ' ')"
}

# 运行中的 dnsmasq 实例：pid 列表（过滤 --test 之类的瞬时进程）
_doc_dnsmasq_pids() {
	_ddp_out=""
	for _ddp_p in $(pidof dnsmasq 2>/dev/null); do
		# OpenWrt 25.12 的 dnsmasq 跑在 ujail 里：pidof 会把 ujail 包装进程也
		# 列出来，而 ujail 会把 comm 改成 "dnsmasq"（VM 实测），所以 comm 不能
		# 用来区分。只认 argv[0] 是 dnsmasq 的那个进程。
		_ddp_exe=$(tr '\0' '\n' <"/proc/$_ddp_p/cmdline" 2>/dev/null | head -1)
		case "$_ddp_exe" in
		*/dnsmasq) ;;
		*) continue ;;
		esac
		_ddp_cmd=$(tr '\0' ' ' <"/proc/$_ddp_p/cmdline" 2>/dev/null) || continue
		case " $_ddp_cmd " in
		*" --test "*) continue ;;
		esac
		_ddp_out="${_ddp_out:+$_ddp_out }$_ddp_p"
	done
	printf '%s' "$_ddp_out"
}

# 某个 pid 是否把 <dir> 作为 conf-dir 加载：
#   ① cmdline 里直接有 --conf-dir=<dir>（OpenWrt 一般不这么传）
#   ② cmdline 里的 -C/--conf-file 指向的运行配置里有 conf-dir=<dir>
# ②是 24.10 的真实形态：conf-dir 写在 /var/etc/dnsmasq.conf.* 里，
# 只 grep cmdline 会得到"所有机器都是假阴性"（判据设计里的 1.6 必须这么落）。
_doc_pid_loads_dir() {
	_dpl_pid=$1
	_dpl_dir=$2
	_dpl_cmd=$(tr '\0' ' ' <"/proc/$_dpl_pid/cmdline" 2>/dev/null)
	for _dpl_tok in $_dpl_cmd; do
		case "$_dpl_tok" in
		--conf-dir=*)
			_dpl_v=${_dpl_tok#--conf-dir=}
			_dpl_v=${_dpl_v%%,*}
			_dpl_v=${_dpl_v%/}
			[ "$_dpl_v" = "${_dpl_dir%/}" ] && return 0
			;;
		--conf-file=*) _dpl_f=${_dpl_tok#--conf-file=} ;;
		esac
	done
	# -C <file> 两 token 形式（OpenWrt 实际用法）
	_dpl_f=${_dpl_f:-}
	if [ -z "$_dpl_f" ]; then
		_dpl_prev=""
		for _dpl_tok in $_dpl_cmd; do
			case "$_dpl_prev" in
			-C) _dpl_f=$_dpl_tok ;;
			esac
			_dpl_prev=$_dpl_tok
		done
	fi
	[ -n "$_dpl_f" ] || return 1
	[ -r "$_dpl_f" ] || return 1
	sed -n 's/^[[:space:]]*conf-dir=//p' "$_dpl_f" 2>/dev/null |
		while IFS= read -r _dpl_line; do
			for _dpl_d in $(printf '%s' "$_dpl_line" | tr ',' ' '); do
				[ "${_dpl_d%/}" = "${_dpl_dir%/}" ] && {
					printf x
					break
				}
			done
		done | grep -q x
}

# P4：一次全量 dump。DOC_P4_RAW 供 hijack 扫描（要看 tproxy/redirect），
# DOC_P4 是剥掉 comment 与 elements 段之后的解析面。
doc_p4_ruleset() {
	[ "${DOC_P4_DONE:-0}" = "1" ] && return 0
	DOC_P4_DONE=1
	DOC_P4_RC=0
	DOC_P4_RAW=""
	DOC_P4=""
	if ! _doc_have nft; then
		DOC_P4_RC=127
		_doc_probe_err P4 "nft -a list ruleset" "nft 不存在，检查三/五判 unknown"
		_doc_probe P4 127
		return 0
	fi
	DOC_P4_RAW=$(nft -a list ruleset 2>/dev/null) || DOC_P4_RC=$?
	if [ "$DOC_P4_RC" -ne 0 ]; then
		_doc_probe_err P4 "nft -a list ruleset" "nft 执行失败（rc=$DOC_P4_RC）"
		_doc_probe P4 "$DOC_P4_RC"
		return 0
	fi
	# 先剥 elements = { ... }（状态机，与 count_set_elements 同款思路），
	# 再剥 comment "..."：两者都会让 hex 解析误判/变慢。
	DOC_P4=$(printf '%s\n' "$DOC_P4_RAW" | awk '
		{
			line = $0
			if (inb) {
				if (index(line, "}")) inb = 0
				next
			}
			p = index(line, "elements = {")
			if (p) {
				pre = substr(line, 1, p - 1)
				rest = substr(line, p + 12)
				printf "%s}\n", pre
				if (!index(rest, "}")) inb = 1
				next
			}
			while (match(line, /comment "[^"]*"/))
				line = substr(line, 1, RSTART - 1) substr(line, RSTART + RLENGTH)
			print line
		}')
	_doc_probe P4 0 "bytes=$(printf '%s\n' "$DOC_P4_RAW" | wc -c | tr -d ' ')"
}

doc_p4b_table() {
	[ "${DOC_P4B_DONE:-0}" = "1" ] && return 0
	DOC_P4B_DONE=1
	DOC_P4B=0
	if doc_mwan3_table; then
		DOC_P4B=1
	fi
	_doc_probe P4b $([ "$DOC_P4B" = "1" ] && printf 0 || printf 1)
}

# 写者枚举（检查三/五共用）：一次 awk 出 TSV，位运算留给 shell（busybox awk
# 没有 and()/or()）。字段：fam tab chain handle field form mask value comment src
#   src = RHS 首个操作数的来源：meta / ct / lit / other（老夹具没有这列时为空，
#   求值按"同字段"处理，与 fix38 行为一致）
doc_p4_writers() {
	DOC_W=""
	[ -n "${DOC_P4:-}" ] || {
		DOC_W_ROWS=0
		return 0
	}
	DOC_W=$(printf '%s\n' "$DOC_P4" | awk '
		function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
		BEGIN { fam = ""; tab = ""; chain = "" }
		{
			tl = trim($0)
			if (index(tl, "table ") == 1) {
				n = split(tl, A, " ")
				fam = A[2]; tab = A[3]; chain = ""
				next
			}
			if (index(tl, "chain ") == 1) {
				n = split(tl, A, " ")
				chain = A[2]
				next
			}
			line = $0
			cm = ""
			p = index(line, "mark set")
			if (p == 0) next
			field = "mark"
			if (index(line, "ct mark set") > 0) {
				# "ct mark set" 是 11 字符 + 1 个空格 -> 值的起点是 index+12。
				# 旧实现写的 +13 会吃掉值的首字符：`ct mark set 0x100` 被读成
				# "x100" -> form=other -> ct 写者整条漏掉（fix38 顺带修的解析 bug）。
				field = "ctmark"; p = index(line, "ct mark set") + 12
			} else if (index(line, "meta mark set") > 0) {
				p = index(line, "meta mark set") + 14
			} else {
				p = p + 8
			}
			rest = trim(substr(line, p))
			h = ""
			q = index(rest, "# handle ")
			if (q > 0) { h = substr(rest, q + 9); rest = trim(substr(rest, 1, q - 1)) }
			sub(/[^0-9].*$/, "", h)
			form = "other"; mask = "-"; value = "-"; src = "other"
			# RHS 的首个操作数说明"这条规则读的是哪个字段"：meta mark / ct mark /
			# 字面值。fix39 的掩码求值靠它区分三种形态——跨字段同步（读 A 写 B）、
			# 同字段掩码（读 B 写 B）、读向（只写 packet mark，不写 ct mark）。
			# 只认行首锚定，避免把 `ct mark & ... != ...` 的条件部分误当来源。
			if (rest ~ /^meta mark/) src = "meta"
			else if (rest ~ /^ct mark/) src = "ct"
			else if (rest ~ /^0x/) src = "lit"
			if (index(rest, "&") > 0) {
				q = index(rest, "&")
				r2 = trim(substr(rest, q + 1))
				split(r2, B, " ")
				mask = B[1]
				if (index(rest, "|") > 0) {
					q2 = index(rest, "|")
					split(trim(substr(rest, q2 + 1)), C, " ")
					value = C[1]
					form = "mask_set"
				} else if (index(rest, "or ") > 0) {
					q2 = index(rest, "or ")
					split(trim(substr(rest, q2 + 3)), C, " ")
					value = C[1]
					form = "mask_or"
				} else {
					form = "mask_clear"
				}
			} else {
				# `meta mark set meta mark | 0x100`（OR 立即数）：nft 打印的是
				# `|`，不是 "or"，旧实现只认 & 分支会把它读成 other -> 漏掉。
				if (index(rest, "|") > 0) {
					q2 = index(rest, "|")
					split(trim(substr(rest, q2 + 1)), C, " ")
					value = C[1]
					form = "or"
				} else {
					split(rest, C, " ")
					value = C[1]
					form = "set"
				}
			}
			if (value != "-" && value != "" && substr(value, 1, 2) != "0x") {
				form = "other"; value = "-"; mask = "-"
			}
			if (fam == "" || tab == "") next
			printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", fam, tab, chain, (h == "" ? "-" : h), field, form, mask, value, (cm == "" ? "-" : cm), src
		}')
	DOC_W_ROWS=$(printf '%s\n' "$DOC_W" | _doc_cnt)
}

# 归属（检查三/五共用，顺序即优先级）：
#   ① 表名是 mwan3（任意 family：inet/ip/ip6 都算）-> 整张表连同全部子链都是
#      mwan3 自己的（iface_in_*、policy_*、mwan3_hook、dynamic、mwan3_or_ct_* 等）；
#   ② 表名是 isp-split 自己的表（isptest / isp_split*）-> isp-split；
#   ③ 任何表里链名是 mwan3* / iface_in_* / iface_out_* -> mwan3（表名被改过时兜底）；
#   ④ comment 含 isp-split -> isp-split；⑤ 非 inet 表 -> legacy（iptables-nft 残留）；
#   ⑥ 其余 -> third_party。
#
# 红线（fix38）：只看"表/链是谁的"，不看 mark 的值。mwan3 的线路值
# （0x100/0x200/...，掩码 mmx_mask）与 OAF 的默认 ct mark 0x100 完全撞值，
# 值签名永远不能当归属判据——否则 mwan3 自己的线路打标会被判成第三方 DPI。
_doc_owner_of() { # fam tab chain comment
	case "$2" in
	mwan3 | mwan3_* | mwan3-*) printf 'mwan3'; return 0 ;;
	isp_split | isp_split_* | isp-split | isp-split_* | isptest) printf 'isp-split'; return 0 ;;
	esac
	case "$3" in
	mwan3* | iface_in_* | iface_out_*) printf 'mwan3'; return 0 ;;
	esac
	case "${4:-}" in
	*isp-split*) printf 'isp-split'; return 0 ;;
	esac
	case "$1" in
	inet) printf 'third_party' ;;
	*) printf 'legacy' ;;
	esac
}

# 值是否整个落在 mmx_mask 位段内（mwan3 线路 mark 家族：0x100/0x200/... 或掩码本身）。
# 只用于"这条写者是不是线路打标形态"的说明与 hint，绝不参与归属判定。
_doc_val_in_mask() { # 0x..
	_doc_hx "${1:-}"
	[ "$HEX" -ne 0 ] || return 1
	[ "$(( HEX & DOC_MMX_MASK_DEC ))" -eq "$HEX" ]
}

# 写向位求值（检查三/五共用，唯一实现）：一条写 mark 的规则到底"写了哪些位"。
#
# nft 打印出来的写向有四种形态，旧实现把它们混在一起（mask 之外的位一律算成
# "清掉了位段内的位"），于是 OpenWrt 自带 fwmark 同步的 OUTPUT 规则必然误报：
#   ① `ct mark set 0x100`（字面值）                 覆盖位 = 值 & mmx_mask
#   ② `... set <别的字段> & 0x00ff0000`（跨字段/同步）覆盖位 = mask | orbits
#   ③ `... set <同字段> & 0xffffc1ff | 0x100`（清位+置位）写 = orbits，清 = ~mask
#   ④ `... set <别的字段>`（整值写，无掩码）        不可判定 -> 保守
# ②的语义：规则只把来源字段的 mask 段搬进目标字段，mask 之外的位由来源字段的
# 当时取值决定（OpenWrt 用 `ct state new` 限定，位段本身与 0x3f00 无重叠），
# 因此判据是"mask | orbits 与 mmx_mask 是否有交集"，不是"mask 之外被清了多少位"。
#
# 读向：`meta mark set ct mark & 0x00ff0000` 只写 packet mark、不写 ct mark，
# 进不了 conntrack，C3 不计（断言 a 的 PREROUTING 行）。
_doc_wr_eval() { # <field> <form> <mask> <value> <src>
	_wre_f=${1:-}
	_wre_form=${2:-other}
	_wre_msk=${3:--}
	_wre_val=${4:--}
	_wre_src=${5:-}
	WR_BITS=0   # 写进目标字段的位（可静态求值时）
	WR_CLEAR=0  # 被清 0 的位（只有同字段掩码写才算）
	WR_KNOWN=1  # 0 = 无法静态求值 -> 调用方按"整段可能被写"保守处理
	WR_KIND=""
	# 同字段（自引用）？空 src（老夹具/信息缺失）按同字段处理，保持 fix38 行为。
	_wre_own=1
	case "$_wre_src" in
	meta) [ "$_wre_f" = "mark" ] || _wre_own=0 ;;
	ct) [ "$_wre_f" = "ctmark" ] || _wre_own=0 ;;
	lit | other) _wre_own=0 ;;
	esac
	case "$_wre_form" in
	set)
		_doc_hx "$_wre_val"
		WR_BITS=$HEX
		WR_KIND=literal
		;;
	or)
		case "$_wre_src:$_wre_f" in
		ct:mark)
			WR_KIND=read_from_ct
			;;
		meta:ctmark)
			# `ct mark set meta mark | 0x100`：没有 & 的整值写，来源位未知
			WR_KNOWN=0
			WR_KIND=unevaluable
			;;
		*)
			_doc_hx "$_wre_val"
			WR_BITS=$HEX
			WR_KIND=or_literal
			;;
		esac
		;;
	mask_set | mask_or | mask_clear)
		case "$_wre_src:$_wre_f" in
		ct:mark)
			WR_KIND=read_from_ct
			;;
		*)
			if [ "$_wre_own" = "1" ]; then
				# 同字段掩码写：mask 内是"写进去的位"，mask 外是"清掉的位"，
				# 两半都动了目标字段 -> 取并集（与 fix38 相同的保守口径）
				_doc_hx "$_wre_val"
				WR_BITS=$HEX
				_doc_hx "$_wre_msk"
				WR_CLEAR=$(( ~HEX & DOC_MMX_MASK_DEC ))
				WR_KIND=same_field_mask
			else
				# 跨字段掩码写（fwmark 同步）：覆盖位 = mask | orbits
				_doc_hx "$_wre_msk"
				_wre_b=$HEX
				[ "$_wre_val" = "-" ] || {
					_doc_hx "$_wre_val"
					_wre_b=$(( _wre_b | HEX ))
				}
				WR_BITS=$_wre_b
				WR_KIND=mask_expr
			fi
			;;
		esac
		;;
	*)
		case "$_wre_src:$_wre_f" in
		ct:mark)
			WR_KIND=read_from_ct
			;;
		ct:ctmark | meta:mark)
			# 自赋值（`ct mark set ct mark`）：一个位都不改
			WR_KIND=self_noop
			;;
		*)
			# 无掩码整值写 / 无法解析的表达式：不知道会写哪些位 -> 保守
			WR_KNOWN=0
			WR_KIND=unevaluable
			;;
		esac
		;;
	esac
}

# 写向规则的 RHS 文本（人读/JSON 里的判定依据，不是判据本身）
_doc_wr_src_expr() { # <src> <field>
	case "${1:-}" in
	meta) printf 'meta mark' ;;
	ct) printf 'ct mark' ;;
	lit) printf '' ;;
	*)
		# src 缺失（老夹具）：按目标字段反推自引用，显示才不会出现 "?"
		case "${2:-}" in
		mark) printf 'meta mark' ;;
		ctmark) printf 'ct mark' ;;
		*) printf '?' ;;
		esac
		;;
	esac
}

_doc_wr_expr() { # <field> <form> <mask> <value> <src>
	case "${2:-}" in
	set) printf '%s' "${4:--}" ;;
	or) printf '%s | %s' "$(_doc_wr_src_expr "${5:-}" "${1:-}")" "${4:--}" ;;
	mask_set | mask_or) printf '%s & %s | %s' "$(_doc_wr_src_expr "${5:-}" "${1:-}")" "${3:--}" "${4:--}" ;;
	mask_clear) printf '%s & %s' "$(_doc_wr_src_expr "${5:-}" "${1:-}")" "${3:--}" ;;
	*) printf '%s（整值写）' "$(_doc_wr_src_expr "${5:-}" "${1:-}")" ;;
	esac
}

# 产品指纹（只用于文案，不作判据）
_doc_guess_product() { # fam tab chain
	case "$2|$3" in
	*clash* | *Clash*) printf 'openclash' ;;
	*PSW* | *passwall* | *PassWall*) printf 'passwall' ;;
	*tailscale* | *Tailscale*) printf 'tailscale' ;;
	*oaf* | *OAF*) printf 'oaf' ;;
	*mihomo* | *Mihomo* | *Meta*) printf 'mihomo' ;;
	*sing* | *SING*) printf 'sing-box' ;;
	*) printf '' ;;
	esac
}

# 产品名的展示写法（hint 用；不改变判据）
_doc_product_label() {
	case "$1" in
	oaf) printf 'OAF' ;;
	openclash) printf 'OpenClash' ;;
	passwall) printf 'PassWall' ;;
	tailscale) printf 'Tailscale' ;;
	mihomo) printf 'mihomo' ;;
	sing-box) printf 'sing-box' ;;
	*) printf '%s' "${1:-}" ;;
	esac
}

# P5：ip rule。无掩码规则等价掩码 0xffffffff——不补全会让位段判据全错。
doc_p5_iprule() {
	[ "${DOC_P5_DONE:-0}" = "1" ] && return 0
	DOC_P5_DONE=1
	DOC_P5=""
	DOC_P5_RC=0
	if ! _doc_have ip; then
		DOC_P5_RC=127
		_doc_probe_err P5 "ip -4 rule show" "ip 不存在"
		_doc_probe P5 127
		return 0
	fi
	DOC_P5=$(ip -4 rule show 2>/dev/null | awk '
		{
			# 空行不是规则：不 skip 会解析出一条 pref="-"、value=0xffffffff 的
			# 假"精确 fwmark 规则"，直接触发 MARK_READER_STARVED 误报（实测踩过）。
			if ($0 == "") next
			line = $0
			pref = $1; sub(/:$/, "", pref)
			val = ""; mask = "0xffffffff"; lk = ""; iif = ""; sup = ""; notv = ""
			if (index(line, "not fwmark ") > 0) { notv = "1"; p = index(line, "not fwmark ") + 11 }
			else if (index(line, "fwmark ") > 0) p = index(line, "fwmark ") + 7
			else p = 0
			if (p > 0) {
				t = substr(line, p)
				sub(/[ \t].*$/, "", t)
				if (index(t, "/") > 0) {
					val = substr(t, 1, index(t, "/") - 1)
					mask = substr(t, index(t, "/") + 1)
				} else {
					val = t
				}
			}
			if (index(line, "lookup ") > 0) {
				t = substr(line, index(line, "lookup ") + 7)
				sub(/[ \t].*$/, "", t)
				lk = t
			}
			if (index(line, "iif ") > 0) {
				t = substr(line, index(line, "iif ") + 4)
				sub(/[ \t].*$/, "", t)
				iif = t
			}
			if (index(line, "suppress_prefixlength ") > 0) {
				t = substr(line, index(line, "suppress_prefixlength ") + 23)
				sub(/[ \t].*$/, "", t)
				sup = t
			}
			printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", pref, (val == "" ? "-" : val), mask, (lk == "" ? "-" : lk), (iif == "" ? "-" : iif), (sup == "" ? "-" : sup), (notv == "" ? "0" : notv)
		}')
	DOC_P5_ROWS=$(printf '%s\n' "$DOC_P5" | _doc_cnt)
	_doc_probe P5 0 "rows=$DOC_P5_ROWS"
	# mwan3 的最小 pref：mask 等于 mmx_mask 且值非零的那些规则（mwan3 自己写的）。
	DOC_MINPREF=$DOC_MINPREF_FALLBACK
	DOC_MINPREF_FOUND=0
	while IFS="	" read -r _mp_pref _mp_val _mp_mask _mp_lk _mp_iif _mp_sup _mp_not; do
		[ -n "${_mp_pref:-}" ] || continue
		[ "$_mp_val" != "-" ] || continue
		_doc_hx "$_mp_mask" && [ "$HEX" = "$DOC_MMX_MASK_DEC" ] || continue
		_doc_hx "$_mp_val" && [ "$HEX" = "0" ] && continue
		case "$_mp_pref" in '' | *[!0-9]*) continue ;; esac
		if [ "$DOC_MINPREF_FOUND" = "0" ] || [ "$_mp_pref" -lt "$DOC_MINPREF" ]; then
			DOC_MINPREF=$_mp_pref
			DOC_MINPREF_FOUND=1
		fi
	done <<EOF
${DOC_P5:-}
EOF
}

# P6：路由真相（只读，不发包）。带 mark 的查询用 mwan3 自己的一条 rule 值。
doc_p6_route() {
	[ "${DOC_P6_DONE:-0}" = "1" ] && return 0
	DOC_P6_DONE=1
	DOC_RG_DEV=""
	DOC_RG_TABLE=""
	DOC_RG_VIA=""
	DOC_RG_RC=0
	DOC_DEF_V4=""
	DOC_DEF_V6=""
	if ! _doc_have ip; then
		DOC_RG_RC=127
		_doc_probe P6 127
		return 0
	fi
	_rg=$(ip -4 route get 223.5.5.5 2>/dev/null) || DOC_RG_RC=$?
	DOC_RG_DEV=$(printf '%s\n' "$_rg" | sed -n 's/.*[[:space:]]dev[[:space:]]\([^[:space:]]*\).*/\1/p' | head -1)
	DOC_RG_VIA=$(printf '%s\n' "$_rg" | sed -n 's/.*[[:space:]]via[[:space:]]\([^[:space:]]*\).*/\1/p' | head -1)
	DOC_RG_TABLE=$(printf '%s\n' "$_rg" | sed -n 's/.*[[:space:]]table[[:space:]]\([^[:space:]]*\).*/\1/p' | head -1)
	DOC_DEF_V4=$(ip -4 route show default 2>/dev/null | head -1)
	DOC_DEF_V6=$(ip -6 route show default 2>/dev/null | head -1)
	_doc_probe P6 "$DOC_RG_RC" "rows=1"
}

# P7：TUN 设备。/sys/class/net/*/tun_flags 是设备性质的硬证据，ip 侧只作加速器。
doc_p7_tun() {
	[ "${DOC_P7_DONE:-0}" = "1" ] && return 0
	DOC_P7_DONE=1
	DOC_TUN=""
	DOC_TUN_RC=0
	DOC_TUN=$(ls -d /sys/class/net/*/tun_flags 2>/dev/null |
		sed 's#^/sys/class/net/##; s#/tun_flags$##')
	[ -n "$DOC_TUN" ] || DOC_TUN_RC=0
	DOC_TUN_ROWS=$(printf '%s\n' "$DOC_TUN" | _doc_cnt)
	_doc_probe P7 0 "rows=$DOC_TUN_ROWS"
	if _doc_have ip && ip -o link show type tun >/dev/null 2>&1; then
		_doc_probe P7b 0
	else
		_doc_probe_err P7b "ip -o link show type tun" "ip-tiny 不支持 type 过滤（只作加速器，不影响结论）"
	fi
}

# 谁持有 /dev/net/tun（设备归属）
_doc_tun_owner() {
	_dto_pids=""
	_dto_out=""
	# 与 _doc_pid_of_inode 同一套目录头解析：谁持有 /dev/net/tun
	for _dto_line in $(printf '%s\n' "${DOC_P2_MAP:-}" | awk '
		/\/fd:$/ {
			p = $0
			sub(/^.*\/proc\//, "", p)
			sub(/\/fd:$/, "", p)
			pid = p
			next
		}
		{
			if (index($0, "/dev/net/tun") == 0) next
			if (match($0, /\/proc\/[0-9]+\/fd\//)) {
				t = substr($0, RSTART + 6, RLENGTH - 6)
				sub(/\/fd\/$/, "", t)
				pid = t
			}
			if (pid != "" && !seen[pid]++) print pid
		}'); do
		case " $_dto_pids " in
		*" $_dto_line "*) continue ;;
		esac
		_dto_pids="$_dto_pids $_dto_line"
		_dto_c=$(cat "/proc/$_dto_line/comm" 2>/dev/null | tr -d '\n')
		_dto_out="${_dto_out}${_dto_out:+/}${_dto_c:-?}:$_dto_line"
	done
	printf '%s' "$_dto_out"
}

# fake-ip 判据：优先认假 IP 段（198.18.0.0/16）而不是产品名
_doc_fakeip() {
	DOC_FIP_DETECTED=0
	DOC_FIP_PRODUCT=""
	DOC_FIP_RANGE=""
	DOC_FIP_EVIDENCE=""
	if _doc_have _openclash_fakeip && _openclash_fakeip; then
		DOC_FIP_DETECTED=1
		DOC_FIP_PRODUCT="openclash"
		DOC_FIP_RANGE="198.18.0.0/16"
		DOC_FIP_EVIDENCE="uci openclash.config.en_mode=fake-ip"
		return 0
	fi
	for _fip_f in /etc/config/openclash /etc/mihomo/config.yaml /etc/sing-box/config.json \
		/etc/config/mihomo /etc/config/sing-box; do
		[ -f "$_fip_f" ] || continue
		grep -q '198\.18\.' "$_fip_f" 2>/dev/null || continue
		DOC_FIP_DETECTED=1
		DOC_FIP_RANGE="198.18.0.0/16"
		case "$_fip_f" in
		*openclash*) DOC_FIP_PRODUCT="openclash" ;;
		*mihomo*) DOC_FIP_PRODUCT="mihomo" ;;
		*sing-box*) DOC_FIP_PRODUCT="sing-box" ;;
		*) DOC_FIP_PRODUCT="" ;;
		esac
		DOC_FIP_EVIDENCE="grep 198.18. $_fip_f"
		return 0
	done
	return 0
}

# P8：offload。uci 与 ruleset 双证——只读 uci 会漏掉"改了没 reload"。
doc_p8_offload() {
	[ "${DOC_P8_DONE:-0}" = "1" ] && return 0
	DOC_P8_DONE=1
	DOC_OFF_SW=$(_doc_bool_uci "$(uci -q get firewall.@defaults[0].flow_offloading 2>/dev/null)")
	DOC_OFF_HW=$(_doc_bool_uci "$(uci -q get firewall.@defaults[0].flow_offloading_hw 2>/dev/null)")
	DOC_OFF_FLOWTABLE=0
	DOC_OFF_FLOWADD=0
	if [ -n "${DOC_P4_RAW:-}" ]; then
		DOC_OFF_FLOWTABLE=$(printf '%s\n' "$DOC_P4_RAW" | grep -cE '^[[:space:]]*flowtable ' 2>/dev/null) || true
		DOC_OFF_FLOWADD=$(printf '%s\n' "$DOC_P4_RAW" | grep -c 'flow add @' 2>/dev/null) || true
		case "${DOC_OFF_FLOWTABLE:-}" in '' | *[!0-9]*) DOC_OFF_FLOWTABLE=0 ;; esac
		case "${DOC_OFF_FLOWADD:-}" in '' | *[!0-9]*) DOC_OFF_FLOWADD=0 ;; esac
	fi
	DOC_OFF_TURBOACC=0
	[ -f /etc/config/turboacc ] && DOC_OFF_TURBOACC=1
	DOC_OFF_VENDOR=""
	for _of_m in fast_classifier shortcut_fe ecm; do
		grep -q "^$_of_m" /proc/modules 2>/dev/null && DOC_OFF_VENDOR="${DOC_OFF_VENDOR:+$DOC_OFF_VENDOR }$_of_m"
	done
	[ -d /sys/kernel/debug/hnat ] && DOC_OFF_VENDOR="${DOC_OFF_VENDOR:+$DOC_OFF_VENDOR }hnat-sysfs"
	_doc_probe P8 0 "rows=$((DOC_OFF_FLOWTABLE + DOC_OFF_FLOWADD))"
}

# P9：conntrack 参数（弱证据：只说明"有人在调"，不说明是谁调的）
doc_p9_conntrack() {
	[ "${DOC_P9_DONE:-0}" = "1" ] && return 0
	DOC_P9_DONE=1
	DOC_CT_COUNT=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || printf '')
	DOC_CT_MAX=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || printf '')
	DOC_CT_ACCT=$(cat /proc/sys/net/netfilter/nf_conntrack_acct 2>/dev/null || printf '')
	DOC_CT_EST=$(cat /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established 2>/dev/null || printf '')
	DOC_CT_TUNED=""
	for _ct_f in /etc/sysctl.conf /etc/sysctl.d/turboacc.conf; do
		[ -f "$_ct_f" ] || continue
		grep -q nf_conntrack "$_ct_f" 2>/dev/null && DOC_CT_TUNED="${DOC_CT_TUNED:+$DOC_CT_TUNED }$_ct_f"
	done
	_doc_probe P9 0
}

# 接口计数（唯一"正确口径"的吞吐来源）
_doc_dev_bytes() { # <dev> -> "rx tx"，读不到输出 "- -"
	_ddb_dev=$1
	_ddb_rx=$(cat "/sys/class/net/$_ddb_dev/statistics/rx_bytes" 2>/dev/null || printf '')
	_ddb_tx=$(cat "/sys/class/net/$_ddb_dev/statistics/tx_bytes" 2>/dev/null || printf '')
	printf '%s %s\n' "${_ddb_rx:--}" "${_ddb_tx:--}"
}

# ---------------------------------------------------------------- 检查一：53 端口归属
#
# 只在"没人听也不会静默失效"的地方给 ok：owner 空且无劫持 -> unknown，因为
# 可能是没配 DNS，也可能是探针被裁掉了。这条与 preflight 的"缺就 ✗"不同：
# doctor 的 unknown 是"不知道"，不是"有问题"。
doc_check_dns53() {
	DOC_C1_ID="dns53_owner"
	DOC_C1_TITLE="53 端口归属与 dnsmasq 片段可达性"
	DOC_C1_VERDICT=unknown
	DOC_C1_CONF=high
	DOC_C1_SERVER=""

	doc_p1_listen
	doc_p2_map
	doc_p3_confdir

	_l_listeners=""
	_l_third=""
	_l_dnsq=0
	_l_lan_dnsq=0
	_l_count=0
	while IFS="	" read -r _l_proto _l_file _l_addr _l_st _l_inode; do
		[ -n "${_l_proto:-}" ] || continue
		_l_count=$((_l_count + 1))
		_l_ip=$(_doc_addr_of "$_l_addr")
		_l_owner=$(_doc_pid_of_inode "$_l_inode")
		_l_pid=${_l_owner%% *}
		_l_comm=${_l_owner#* }
		[ "$_l_owner" = "$_l_pid" ] && _l_comm=""
		# 0A=TCP LISTEN，07=UDP 未连接；其它状态（如 01 ESTABLISHED）不算"在听"
		_l_listen=0
		case "$_l_st" in
		0A | 07) _l_listen=1 ;;
		esac
		_l_listeners="${_l_listeners}${_l_listeners:+,}{\"pid\":${_l_pid:-0},\"comm\":$(_doc_jstr "$_l_comm"),\"proto\":$(_doc_jstr "$_l_proto"),\"addr\":$(_doc_jstr "$_l_ip"),\"port\":53,\"listen\":$(_doc_jbool "$_l_listen"),\"inode\":$(_doc_jstr "$_l_inode")}"
		if [ "$_l_comm" = "dnsmasq" ]; then
			_l_dnsq=1
			_doc_is_loopback "$_l_ip" || _l_lan_dnsq=1
		elif [ -n "$_l_comm" ]; then
			_l_third="${_l_third}${_l_third:+,}$(_doc_jstr "$_l_comm")"
			_doc_is_loopback "$_l_ip" || _l_lan_dnsq=1
		fi
	done <<EOF
${DOC_P1_TSV:-}
EOF

	# 1.2 透明劫持者：不 bind 端口也算（eBPF / redirect / tproxy）
	_l_hijack=""
	_l_hijack_n=0
	if [ -n "${DOC_P4_RAW:-}" ]; then
		_l_hijack=$(printf '%s\n' "$DOC_P4_RAW" |
			grep -E '(redirect|dnat|tproxy)[^#]*:53( |$)|dport 53[^#]*(redirect|dnat|tproxy)' 2>/dev/null |
			head -6)
		[ -n "$_l_hijack" ] && _l_hijack_n=$(printf '%s\n' "$_l_hijack" | _doc_cnt)
	fi
	_l_hijack_json=""
	if [ "$_l_hijack_n" -gt 0 ]; then
		while IFS= read -r _l_h; do
			[ -n "$_l_h" ] || continue
			_l_hijack_json="${_l_hijack_json}${_l_hijack_json:+,}$(_doc_jstr "$(printf '%s' "$_l_h" | sed 's/^[[:space:]]*//')")"
		done <<EOF
$_l_hijack
EOF
	fi

	# 1.6/1.7：片段在不在、有没有被"跑着的"实例加载
	_l_pids=$(_doc_dnsmasq_pids)
	_l_inst=0
	for _l_p in $_l_pids; do
		_l_inst=$((_l_inst + 1))
	done
	_l_target=$(_doc_have _dns_confdir_first && _dns_confdir_first 2>/dev/null)
	[ -n "${_l_target:-}" ] || _l_target=$(printf '%s\n' "${DOC_P3_DIRS:-}" | awk '{ print $1 }')
	[ -n "${_l_target:-}" ] || _l_target=${DNSMASQ_DEFAULT_DIR:-/tmp/dnsmasq.d}
	_l_frag="$_l_target/isp-split.conf"
	_l_loaded=""
	_l_loaded_n=0
	for _l_p in $_l_pids; do
		if _doc_pid_loads_dir "$_l_p" "${DOC_P3_DIRS:-$_l_target}"; then
			_l_loaded="${_l_loaded}${_l_loaded:+,}$_l_p"
			_l_loaded_n=$((_l_loaded_n + 1))
		fi
	done
	# 域名分流是否配置过：DOMAIN_SPLIT 非空，或 $DOMAINDIR/*.txt 非空。
	# 只做 IP 分流时 dnsmasq 片段本来就不生成（isp-split dns 会直接返回），
	# 把"没有片段"判成 conflict 是假阳性——VM 实测踩到过。
	_l_domcfg=0
	[ -n "${DOMAIN_SPLIT:-}" ] && _l_domcfg=1
	_l_domdir=${DOMAINDIR:-${DOMAIN_LIST_DIR:-${BASE:-/etc/isp-split}/domains}}
	for _l_df in "$_l_domdir"/*.txt; do
		[ -f "$_l_df" ] && {
			_l_domcfg=1
			break
		}
	done
	_l_fexists=0
	_l_fmtime=""
	_l_fserver=0
	if [ -f "$_l_frag" ]; then
		_l_fexists=1
		_l_fmtime=$(stat -c %Y "$_l_frag" 2>/dev/null || printf '')
		_l_fserver=$(grep -c '^server=' "$_l_frag" 2>/dev/null) || true
		case "${_l_fserver:-}" in '' | *[!0-9]*) _l_fserver=0 ;; esac
	fi
	_l_stale=0
	if [ -f "$_l_frag" ] && [ -f "${DATA:-/nonexistent}/.stamp" ]; then
		_l_stamp=$(stat -c %Y "${DATA}/.stamp" 2>/dev/null || printf '0')
		[ "${_l_fmtime:-0}" -lt "${_l_stamp:-0}" ] 2>/dev/null && _l_stale=1
	fi
	_l_dnsrules=$(_doc_have _dns_rule_count && _dns_rule_count 2>/dev/null)
	[ -n "${_l_dnsrules:-}" ] || _l_dnsrules=$(nft -a list chain inet mwan3 mwan3_output 2>/dev/null |
		grep -c 'comment "isp-split-dns"' 2>/dev/null) || true
		case "${_l_dnsrules:-}" in '' | *[!0-9]*) _l_dnsrules=0 ;; esac

	DOC_C1_FACTS="\"mode\":$(_doc_jstr "${DNS_MODE:-unknown}"),\"listeners\":[$_l_listeners],\"hijack_rules\":[$_l_hijack_json],\"dnsmasq_instances\":$_l_inst,\"confdir\":{\"source\":$(_doc_jstr "${DOC_P3_SOURCE:-unknown}"),\"detail\":$(_doc_jstr "${DOC_P3_DETAIL:-}"),\"dirs\":$(_doc_jstr "${DOC_P3_DIRS:-}"),\"loaded_by_running_pid\":[$_l_loaded]},\"domain_split_configured\":$(_doc_jbool "$_l_domcfg"),\"fragment\":{\"path\":$(_doc_jstr "$_l_frag"),\"exists\":$(_doc_jbool "$_l_fexists"),\"mtime\":$(_doc_jstr "$_l_fmtime"),\"server_lines\":$_l_fserver,\"stale\":$(_doc_jbool "$_l_stale")},\"nft_dns_rules\":{\"chain\":\"inet mwan3 mwan3_output\",\"comment\":\"isp-split-dns\",\"count\":${_l_dnsrules:-0}}"

	_l_find=""
	_doc_find() { # <code> <verdict> <detail> <evidence>
		_l_find="${_l_find}${_l_find:+,}{\"code\":$(_doc_jstr "$1"),\"verdict\":$(_doc_jstr "$2"),\"detail\":$(_doc_jstr "$3"),\"evidence\":$(_doc_jstr "$4")}"
	}

	if [ "$_l_count" -eq 0 ] && [ "$_l_hijack_n" -eq 0 ]; then
		DOC_C1_VERDICT=unknown
		_doc_find "" unknown "53 端口上没有任何监听者，也没有透明劫持规则" "P1 + P4"
		DOC_C1_ADVICE="可能是还没配 DNS，也可能是探针在裁剪过的固件上读不到；装好 dnsmasq 后重跑 doctor。"
	elif [ "$_l_dnsq" = "0" ] && [ "$_l_hijack_n" -gt 0 ]; then
		DOC_C1_VERDICT=unknown
		_doc_find "DNS_TRANSPARENT_HIJACK" unknown "只有透明劫持规则、没有程序 bind :53（eBPF/redirect 型），无法静态判定归属" "P4 redirect/tproxy 扫描"
		DOC_C1_ADVICE="这类接管常来自 eBPF 型 DNS 插件；把 DNS 模式改成 mark 后功能不再依赖 dnsmasq 片段。"
	elif [ "$_l_dnsq" = "1" ] && [ "$_l_fexists" = "1" ] && [ "$_l_loaded_n" -gt 0 ]; then
		if [ "$_l_inst" -gt 1 ]; then
			DOC_C1_VERDICT=warn
			_doc_find "DNS_MULTI_INSTANCE" warn "有 $_l_inst 个 dnsmasq 实例，片段可能只进了其中一个的加载目录" "P1 + /proc/<pid>/cmdline"
		else
			DOC_C1_VERDICT=ok
			_doc_find "" ok "dnsmasq 持有 :53，分线片段已被运行中的实例加载" "P1 + P3 + cmdline"
		fi
		[ "$_l_stale" = "1" ] && {
			DOC_C1_VERDICT=warn
			_doc_find "DNS_FRAGMENT_STALE" warn "片段比最新数据旧（sh -x：数据已更新但片段没重写）" "mtime(${_l_fmtime:-0}) < stamp"
		}
	elif [ "$_l_dnsq" = "1" ] && [ "$_l_fexists" = "0" ] && [ "$_l_domcfg" = "0" ]; then
		# 没有域名分流配置：片段本来就不该存在，DNS_TABLE 的 nft 旁路与它无关
		DOC_C1_VERDICT=ok
		_doc_find "DNS_FRAGMENT_NOT_NEEDED" ok "没有配置域名分流，dnsmasq 片段本来就不需要（DNS_TABLE 的 nft 旁路不受影响）" "DOMAIN_SPLIT 为空且 ${_l_domdir} 无清单"
	elif [ "$_l_dnsq" = "1" ] && { [ "$_l_fexists" = "0" ] || [ "$_l_loaded_n" -eq 0 ]; }; then
		DOC_C1_VERDICT=conflict
		_doc_find "DNS_FRAGMENT_ORPHAN" conflict "dnsmasq 在跑，但分线片段不在它加载的目录里（写了没人读）" "P3 dirs=${DOC_P3_DIRS:-} fragment=$_l_frag"
	elif [ "$_l_dnsq" = "0" ] && [ -n "$_l_third" ]; then
		if [ "${DNS_MODE:-bind}" = "mark" ]; then
			DOC_C1_VERDICT=warn
			_doc_find "DNS_BYPASS_PARTIAL" warn "53 端口由第三方程序持有；mark 模式下 nft 侧仍生效，dnsmasq 片段作废" "P1 owner=$_l_third"
		else
			DOC_C1_VERDICT=conflict
			_doc_find "DNS_BYPASS_DEAD" conflict "53 端口由第三方程序持有，bind 模式下 dnsmasq 片段与 nft 旁路都不生效" "P1 owner=$_l_third"
		fi
	else
		DOC_C1_VERDICT=warn
		_doc_find "" warn "没能把端口归属与片段加载状态对上（有第三方监听，dnsmasq 也在）" "P1 + P3"
	fi

	[ "$_l_lan_dnsq" = "0" ] && [ "$_l_count" -gt 0 ] && [ "$_l_dnsq" = "1" ] &&
		_doc_find "DNS_LOOPBACK_ONLY" warn "dnsmasq 只监听回环地址，LAN 客户端的查询可能根本不经过它" "P1 addr 字段"

	# 建议按"根因 code"给：还没生成片段 ≠ 被别人接管，两者的下一步完全不同。
	_l_code=""
	case "$_l_find" in
	*'"code":"DNS_FRAGMENT_NOT_NEEDED"'*) _l_code=DNS_FRAGMENT_NOT_NEEDED ;;
	*'"code":"DNS_FRAGMENT_ORPHAN"'*) _l_code=DNS_FRAGMENT_ORPHAN ;;
	*'"code":"DNS_BYPASS_DEAD"'*) _l_code=DNS_BYPASS_DEAD ;;
	*'"code":"DNS_BYPASS_PARTIAL"'*) _l_code=DNS_BYPASS_PARTIAL ;;
	*'"code":"DNS_TRANSPARENT_HIJACK"'*) _l_code=DNS_TRANSPARENT_HIJACK ;;
	*'"code":"DNS_MULTI_INSTANCE"'*) _l_code=DNS_MULTI_INSTANCE ;;
	*'"code":"DNS_FRAGMENT_STALE"'*) _l_code=DNS_FRAGMENT_STALE ;;
	esac
	case "$_l_code" in
	DNS_FRAGMENT_NOT_NEEDED)
		DOC_C1_ADVICE="只用 IP 分流，不需要 dnsmasq 片段；DNS_TABLE 的按目标 IP 旁路仍在 nft 里生效。" ;;
	DNS_FRAGMENT_ORPHAN)
		DOC_C1_ADVICE="dnsmasq 已在跑但还没有分线片段：先 isp-split dns 生成片段；若解析器不是 dnsmasq，就把 DNS_MODE 改成 mark。" ;;
	DNS_BYPASS_DEAD)
		DOC_C1_ADVICE="把 DNS 模式改成 mark（isp-split conf set DNS_MODE mark）再 isp-split dns 重放规则；dnsmasq 片段可保留但不再起作用。" ;;
	DNS_BYPASS_PARTIAL)
		DOC_C1_ADVICE="nft 侧（mark 模式）不受影响；dnsmasq 片段对第三方解析器的查询无效，可以忽略。" ;;
	DNS_TRANSPARENT_HIJACK)
		DOC_C1_ADVICE="这类接管常来自 eBPF 型 DNS 插件；把 DNS 模式改成 mark 后功能不再依赖 dnsmasq 片段。" ;;
	DNS_MULTI_INSTANCE)
		DOC_C1_ADVICE="多个解析器实例时片段可能只进了其中一个的目录；确认 LAN 面那个实例也加载同一目录（isp-split dns 会写进探测到的第一个目录）。" ;;
	DNS_FRAGMENT_STALE)
		DOC_C1_ADVICE="数据更新后片段没重写：跑一次 isp-split dns 即可。" ;;
	*)
		case "$DOC_C1_VERDICT" in
		ok) DOC_C1_ADVICE="DNS 由 dnsmasq 接管，分线片段已在它的加载目录里，域名分线正常生效。" ;;
		unknown) DOC_C1_ADVICE="没能确认谁在应答 DNS；先确认 dnsmasq 在跑，或把 DNS 模式改成 mark 以摆脱对解析器类型的依赖。" ;;
		*) DOC_C1_ADVICE="53 端口上有别的程序；建议把 DNS 模式改成 mark（isp-split conf set DNS_MODE mark），让 nft 侧承担分线。" ;;
		esac
		;;
	esac
	DOC_C1_FIND="$_l_find"
	DOC_C1_CONF=high
	[ "${DOC_P2_RC:-0}" -ne 0 ] && DOC_C1_CONF=low
	[ "${DOC_P1_RC:-0}" -ne 0 ] && DOC_C1_CONF=low
}

# ---------------------------------------------------------------- 检查二：TUN 劫持
doc_check_tun() {
	DOC_C2_ID="tun_hijack"
	DOC_C2_TITLE="TUN 设备与默认路由劫持"
	DOC_C2_VERDICT=ok
	DOC_C2_CONF=high

	doc_p7_tun
	doc_p6_route
	_doc_fakeip

	_t_tuns=""
	_t_n=0
	_t_hit=0
	_t_hijack_dev=""
	if [ "$DOC_RG_DEV" != "" ]; then
		case " $(printf '%s\n' "$DOC_TUN" | tr '\n' ' ') " in
		*" $DOC_RG_DEV "*) _t_hit=1 ;;
		esac
	fi
	# 也认 "名字像 tun" 的设备（tun_flags 缺失但路由指向它）
	case "$DOC_RG_DEV" in
	Meta | tun[0-9]* | utun* | singbox* | clash* | mihomo*) _t_hit=1 ;;
	esac
	while IFS= read -r _t_dev; do
		[ -n "$_t_dev" ] || continue
		_t_n=$((_t_n + 1))
		_t_owner=$(_doc_tun_owner)
		_t_ifidx=$(cat "/sys/class/net/$_t_dev/ifindex" 2>/dev/null || printf '')
		set -- $(_doc_dev_bytes "$_t_dev")
		_t_tuns="${_t_tuns}${_t_tuns:+,}{\"dev\":$(_doc_jstr "$_t_dev"),\"ifindex\":$(_doc_jstr "$_t_ifidx"),\"owner\":$(_doc_jstr "$_t_owner"),\"rx_bytes\":$(_doc_jstr "${1:--}"),\"tx_bytes\":$(_doc_jstr "${2:--}")}"
	done <<EOF
${DOC_TUN:-}
EOF
	[ "$_t_n" -eq 0 ] && case "$DOC_RG_DEV" in
	Meta | tun[0-9]* | utun* | singbox* | clash* | mihomo*)
		_t_tuns="{\"dev\":$(_doc_jstr "$DOC_RG_DEV"),\"ifindex\":null,\"owner\":$(_doc_jstr "$(_doc_tun_owner)"),\"note\":\"sysfs 里没有 tun_flags，按路由设备名判\"}"
		_t_n=1
		;;
	esac

	# 抢占 mwan3 的 ip rule（pref 更小且指向非 main/local/default 的表）
	_t_pre=""
	_t_pre_n=0
	while IFS="	" read -r _t_pref _t_val _t_mask _t_lk _t_iif _t_sup _t_not; do
		[ -n "${_t_pref:-}" ] || continue
		case "$_t_lk" in
		- | local | main | default) continue ;;
		esac
		case "$_t_pref" in '' | *[!0-9]*) continue ;; esac
		[ "$_t_pref" -lt "$DOC_MINPREF" ] || continue
		# mwan3 自己会给每条 WAN 写 `iif <iface> lookup N`（实测 pref 1005/1006）。
		# 这些不是第三方抢占；iif 在 mwan3 里有同名 interface 段就跳过。
		if [ "$_t_iif" != "-" ]; then
			[ "$(uci -q get "mwan3.$_t_iif" 2>/dev/null)" = "interface" ] && continue
		fi
		_t_pre="${_t_pre}${_t_pre:+,}{\"pref\":$_t_pref,\"match\":$(_doc_jstr "$( [ "$_t_val" = "-" ] && printf 'from all' || printf 'fwmark %s/%s' "$_t_val" "$_t_mask")"),\"lookup\":$(_doc_jstr "$_t_lk"),\"iif\":$(_doc_jstr "$_t_iif"),\"suppress_prefixlength\":$(_doc_jstr "$_t_sup")}"
		_t_pre_n=$((_t_pre_n + 1))
	done <<EOF
${DOC_P5:-}
EOF

	DOC_C2_FACTS="\"tun_devices\":[$_t_tuns],\"default_v4\":$(_doc_jstr "$DOC_DEF_V4"),\"default_v6\":$(_doc_jstr "$DOC_DEF_V6"),\"route_get\":{\"dst\":\"223.5.5.5\",\"dev\":$(_doc_jstr "$DOC_RG_DEV"),\"via\":$(_doc_jstr "$DOC_RG_VIA"),\"table\":$(_doc_jstr "$DOC_RG_TABLE")},\"rules_preempting_mwan3\":[$_t_pre],\"mwan3_min_pref\":$DOC_MINPREF,\"fakeip\":{\"detected\":$(_doc_jbool "$DOC_FIP_DETECTED"),\"product\":$(_doc_jstr "$DOC_FIP_PRODUCT"),\"range\":$(_doc_jstr "$DOC_FIP_RANGE"),\"evidence\":$(_doc_jstr "$DOC_FIP_EVIDENCE")}"

	_t_find=""
	_doc_find2() {
		_t_find="${_t_find}${_t_find:+,}{\"code\":$(_doc_jstr "$1"),\"verdict\":$(_doc_jstr "$2"),\"detail\":$(_doc_jstr "$3"),\"evidence\":$(_doc_jstr "$4")}"
	}

	if [ "$_t_n" -eq 0 ]; then
		DOC_C2_VERDICT=ok
		_doc_find2 "" ok "没有 TUN 设备，转发完整经过 mwan3" "P7"
	elif [ "$_t_hit" = "1" ]; then
		if [ "$DOC_FIP_DETECTED" = "1" ]; then
			DOC_C2_VERDICT=conflict
			_doc_find2 "TUN_FAKEIP" conflict "默认路由指向 TUN，且代理开了 fake-ip：目的地址是假 IP，运营商集合永不命中" "$DOC_FIP_EVIDENCE"
		else
			DOC_C2_VERDICT=conflict
			_doc_find2 "TUN_DEFAULT_ROUTE" conflict "ip route get 223.5.5.5 解析到 TUN 设备 $DOC_RG_DEV" "P6 + P7"
		fi
	elif [ "$_t_n" -gt 0 ] && [ "$_t_pre_n" -gt 0 ]; then
		DOC_C2_VERDICT=warn
		_doc_find2 "TUN_RULE_PREEMPT" warn "有 $_t_pre_n 条 pref 小于 mwan3($DOC_MINPREF) 的 ip rule 指向独立路由表，部分流量可能绕过 mwan3" "P5"
	else
		DOC_C2_VERDICT=ok
		_doc_find2 "TUN_IDLE" ok "有 TUN 设备，但默认路由与 ip rule 都没被它接管（空闲/残留设备）" "P6 + P5"
	fi
	if [ "$DOC_FIP_DETECTED" = "1" ] && [ "$_t_hit" = "0" ]; then
		DOC_C2_VERDICT=conflict
		_doc_find2 "TUN_FAKEIP" conflict "检测到 fake-ip（198.18.0.0/16）：假 IP 无法匹配运营商集合" "$DOC_FIP_EVIDENCE"
	fi

	case "$DOC_C2_VERDICT" in
	ok) DOC_C2_ADVICE="没有发现 TUN 接管默认路由，转发仍然完整经过 mwan3。" ;;
	warn) DOC_C2_ADVICE="发现一个 TUN 设备，部分流量可能绕过 mwan3；如果是有意为之可以忽略，否则关掉该代理的自动路由。" ;;
	conflict) DOC_C2_ADVICE="关掉 mihomo/sing-box 的 auto-route 或 tun.auto-route；若必须保留 TUN，就接受 IP 分流不生效，或把 TUN/fake-ip 网段从分流目标里排除。" ;;
	esac
	DOC_C2_FIND="$_t_find"
}

# ---------------------------------------------------------------- 检查三：位段占用与读写一致性
#
# 检查三回答"位段有没有被抢、抢了会不会出事"；检查五回答"名单上有谁"。
# summary 里只允许一条 conflict 计数，否则 3 与 5 同时 conflict 会让用户
# 以为有两处故障——所以本函数自己算 conflict，检查五只继承不重复。
doc_check_mark() {
	DOC_C3_ID="mark_segment"
	DOC_C3_TITLE="标记位段（mmx_mask）占用与读写一致性"
	DOC_C3_VERDICT=unknown
	DOC_C3_CONF=high

	doc_p11_mask
	doc_p4_ruleset
	doc_p5_iprule
	_M=$DOC_MMX_MASK_DEC

	if [ -z "${DOC_P4:-}" ] && [ "$DOC_P4_RC" -ne 0 ]; then
		DOC_C3_FACTS="\"mmx_mask\":$(_doc_jstr "$DOC_MMX_MASK"),\"mmx_mask_source\":$(_doc_jstr "$DOC_MMX_SOURCE"),\"writers\":[],\"readers\":[],\"mwan3_min_pref\":$DOC_MINPREF"
		DOC_C3_FIND=""
		DOC_C3_ADVICE="没能读取 nft 规则表，无法判断标记位是否被占用；先确认 nft 可用且 mwan3 在跑。"
		DOC_C3_CONF=low
		return 0
	fi

	_c3_writers=""
	_c3_writers_n=0
	_c3_excluded=""
	_c3_excl_n=0
	_c3_excl_mw=0
	_c3_excl_own=0
	_c3_wn=0
	_c3_third=0
	_c3_overlap=0
	_c3_overlap_ordered=0
	_c3_overlap_unordered=0
	_c3_ct=0
	_c3_ct_names=""
	_c3_hint=""
	_c3_hint_conf="none"
	_c3_hint_basis="none"
	_c3_outside=""
	_c3_outside_n=0
	# 第三方重叠写者的明细，供检查五继承
	DOC_C3_OVERLAP_NAMES=""
	# fix39：掩码表达式求值的判定记录（facts 里给用户看"为什么没报"）
	_c3_eval=""          # 第三方写者的形态/覆盖位/是否重叠
	# 「无重叠（已验证）」的 info：按 表/链/位段 去重，最多 4 条
	_c3_disjoint=""
	_c3_disjoint_keys=" "
	_c3_disjoint_n=0
	_c3_readn=0
	_c3_read_txt=""
	_c3_unknown_n=0
	_c3_ct_unknown=0
	_c3_find=""
	_doc_find3() {
		_c3_find="${_c3_find}${_c3_find:+,}{\"code\":$(_doc_jstr "$1"),\"verdict\":$(_doc_jstr "$2"),\"detail\":$(_doc_jstr "$3"),\"evidence\":$(_doc_jstr "$4")}"
	}
	while IFS="	" read -r _w_fam _w_tab _w_chn _w_hnd _w_fld _w_form _w_msk _w_val _w_cm _w_src; do
		[ -n "${_w_fam:-}" ] || continue
		_c3_wn=$((_c3_wn + 1))
		_w_owner=$(_doc_owner_of "$_w_fam" "$_w_tab" "$_w_chn" "$_w_cm")
		# 写向位求值（唯一实现，检查五同源）：形态 -> 覆盖位/清位/可否判定
		_doc_wr_eval "$_w_fld" "$_w_form" "$_w_msk" "$_w_val" "${_w_src:-}"
		_w_kind=$WR_KIND
		_w_known=$WR_KNOWN
		if [ "$_w_known" = "0" ]; then
			# 不可判定（整值写/无法解析）：按"整段都可能被写"保守处理
			_w_touched=$_M
		else
			_w_touched=$(( WR_CLEAR | WR_BITS ))
		fi
		_w_prod=$(_doc_guess_product "$_w_fam" "$_w_tab" "$_w_chn")
		case "$_w_owner" in
		mwan3 | isp-split)
			# 排除清单（fix38）：mwan3 自家表/链（iface_in_*、policy_*、mwan3_hook、
			# dynamic、mwan3_or_ct_* 等，任意 family）与 isp-split 自家表里的写者，
			# 都不是第三方。它们写的正是 mmx_mask 位段内的线路值——值签名不能
			# 反过来当"第三方 DPI"的证据。
			_c3_excl_n=$((_c3_excl_n + 1))
			case "$_w_owner" in
			mwan3) _c3_excl_mw=$((_c3_excl_mw + 1)) ;;
			*) _c3_excl_own=$((_c3_excl_own + 1)) ;;
			esac
			if [ "$_c3_excl_n" -le 40 ]; then
				_c3_excluded="${_c3_excluded}${_c3_excluded:+,}{\"fam\":$(_doc_jstr "$_w_fam"),\"table\":$(_doc_jstr "$_w_tab"),\"chain\":$(_doc_jstr "$_w_chn"),\"field\":$(_doc_jstr "$_w_fld"),\"form\":$(_doc_jstr "$_w_form"),\"mask\":$(_doc_jstr "$([ "$_w_msk" = "-" ] && printf '' || printf '%s' "$_w_msk")"),\"value\":$(_doc_jstr "$([ "$_w_val" = "-" ] && printf '' || printf '%s' "$_w_val")"),\"touched\":$(_doc_jstr "$(_doc_hxstr "$_w_touched")"),\"owner\":$(_doc_jstr "$_w_owner"),\"reason\":$(_doc_jstr "$([ "$_w_owner" = "mwan3" ] && printf 'mwan3_own_table' || printf 'isp_split_own')")}"
			fi
			;;
		*)
			_c3_third=$((_c3_third + 1))
			# 表达式文本只给第三方写者用（自家写者上百条，别为它们多 fork）
			_w_expr=$(_doc_wr_expr "$_w_fld" "$_w_form" "$_w_msk" "$_w_val" "${_w_src:-}")
			_w_inmask=$(( _w_touched & _M ))
			if [ "$_w_known" = "0" ]; then
				_c3_unknown_n=$((_c3_unknown_n + 1))
				[ "$_w_fld" = "ctmark" ] && _c3_ct_unknown=$((_c3_ct_unknown + 1))
			fi
			if [ "$_c3_writers_n" -lt 40 ]; then
				_c3_writers_n=$((_c3_writers_n + 1))
				_c3_writers="${_c3_writers}${_c3_writers:+,}{\"fam\":$(_doc_jstr "$_w_fam"),\"table\":$(_doc_jstr "$_w_tab"),\"chain\":$(_doc_jstr "$_w_chn"),\"handle\":$(_doc_jstr "$_w_hnd"),\"field\":$(_doc_jstr "$_w_fld"),\"form\":$(_doc_jstr "$_w_form"),\"mask\":$(_doc_jstr "$([ "$_w_msk" = "-" ] && printf '' || printf '%s' "$_w_msk")"),\"value\":$(_doc_jstr "$([ "$_w_val" = "-" ] && printf '' || printf '%s' "$_w_val")"),\"src\":$(_doc_jstr "${_w_src:-}"),\"expr\":$(_doc_jstr "$_w_expr"),\"eval\":$(_doc_jstr "$_w_kind"),\"bits\":$(_doc_jstr "$(_doc_hxstr "$WR_BITS")"),\"known\":$(_doc_jbool "$_w_known"),\"touched\":$(_doc_jstr "$(_doc_hxstr "$_w_touched")"),\"overlap\":$(_doc_jbool "$([ "$_w_inmask" -ne 0 ] && printf 1 || printf 0)"),\"owner\":$(_doc_jstr "$_w_owner"),\"product_guess\":$(_doc_jstr "$_w_prod")}"
			fi
			# 判定矩阵留痕：形态 -> 覆盖位 -> 是否与 mmx_mask 重叠
			if [ "$_c3_third" -le 40 ]; then
				_c3_eval="${_c3_eval}${_c3_eval:+,}{\"fam\":$(_doc_jstr "$_w_fam"),\"table\":$(_doc_jstr "$_w_tab"),\"chain\":$(_doc_jstr "$_w_chn"),\"handle\":$(_doc_jstr "$_w_hnd"),\"field\":$(_doc_jstr "$_w_fld"),\"form\":$(_doc_jstr "$_w_form"),\"src\":$(_doc_jstr "${_w_src:-}"),\"expr\":$(_doc_jstr "$_w_expr"),\"bits\":$(_doc_jstr "$(_doc_hxstr "$WR_BITS")"),\"known\":$(_doc_jbool "$_w_known"),\"kind\":$(_doc_jstr "$_w_kind"),\"overlap\":$(_doc_jbool "$([ "$_w_inmask" -ne 0 ] && printf 1 || printf 0)")}"
			fi
			if [ "$(( _w_touched & _M ))" -ne 0 ]; then
				_c3_overlap=$((_c3_overlap + 1))
				DOC_C3_OVERLAP_NAMES="${DOC_C3_OVERLAP_NAMES}${DOC_C3_OVERLAP_NAMES:+ }${_w_prod:-third_party}"
				# 先手判定：存在一条 pref < mwan3 最小 pref、且 fwmark 值等于该写者的 rule
				_w_ordered=0
				while IFS="	" read -r _r_pref _r_val _r_mask _r_lk _r_iif _r_sup _r_not; do
					[ -n "${_r_pref:-}" ] || continue
					case "$_r_pref" in '' | *[!0-9]*) continue ;; esac
					[ "$_r_pref" -lt "$DOC_MINPREF" ] || continue
					[ "$_r_val" = "-" ] && continue
					_doc_hx "$_r_val"
					_r_raw=$HEX
					_doc_hx "$_w_val"
					[ "$_r_raw" = "$HEX" ] || continue
					_w_ordered=1
				done <<EOF
${DOC_P5:-}
EOF
				if [ "$_w_ordered" = "1" ]; then
					_c3_overlap_ordered=$((_c3_overlap_ordered + 1))
				else
					_c3_overlap_unordered=$((_c3_overlap_unordered + 1))
				fi
				if [ "$_w_fld" = "ctmark" ]; then
					_c3_ct=$((_c3_ct + 1))
					[ "$_c3_ct" -le 3 ] &&
						_c3_ct_names="${_c3_ct_names}${_c3_ct_names:+, }${_w_fam} ${_w_tab} ${_w_chn}(${_w_expr})"
					# 产品名只是 hint：名字级证据 > 值签名（低置信度）> 未识别。
					if [ "$_c3_hint_conf" != "high" ]; then
						if [ -n "$_w_prod" ]; then
							_c3_hint=$_w_prod
							_c3_hint_conf=high
							_c3_hint_basis=name
						elif _doc_val_in_mask "$_w_val" && [ "$HEX" = "256" ]; then
							# 0x100 既可能是 OAF 的默认 ct mark，也是 mwan3 的 wan1
							# 线路值：只作低置信度猜测，绝不参与 verdict。
							_c3_hint=oaf
							_c3_hint_conf=low
							_c3_hint_basis=value_signature
						fi
					fi
				fi
			else
				_c3_outside="${_c3_outside}${_c3_outside:+,}{\"fam\":$(_doc_jstr "$_w_fam"),\"table\":$(_doc_jstr "$_w_tab"),\"chain\":$(_doc_jstr "$_w_chn"),\"handle\":$(_doc_jstr "$_w_hnd"),\"product\":$(_doc_jstr "${_w_prod:-third_party}"),\"form\":$(_doc_jstr "$_w_form"),\"expr\":$(_doc_jstr "$_w_expr"),\"bits\":$(_doc_jstr "$(_doc_hxstr "$WR_BITS")"),\"value\":$(_doc_jstr "$_w_val")}"
				_c3_outside_n=$((_c3_outside_n + 1))
				# fix39：求值结论 = 无重叠。必须让用户看见"为什么没报"，
				# 否则一次误报修完只留下"哦现在不报了"的不信任。
				if [ "$_w_kind" = "mask_expr" ]; then
					_w_seg=$_w_msk
					[ "$_w_val" = "-" ] || _w_seg="${_w_msk} | ${_w_val}"
					_w_key="${_w_tab}/${_w_chn}/${_w_seg}"
					case "$_c3_disjoint_keys" in
					*" $_w_key "*)
						;;
					*)
						_c3_disjoint_keys="${_c3_disjoint_keys}${_w_key} "
						_c3_disjoint_n=$((_c3_disjoint_n + 1))
						if [ "$_c3_disjoint_n" -le 4 ]; then
							_c3_disjoint="${_c3_disjoint}${_w_tab} ${_w_chn} 的 fwmark 同步使用 ${_w_seg} 位段，与 mmx_mask($DOC_MMX_MASK) 无重叠（已验证）
"
						fi
						;;
					esac
				elif [ "$_w_kind" = "read_from_ct" ]; then
					_c3_readn=$((_c3_readn + 1))
					[ -n "$_c3_read_txt" ] || _c3_read_txt="${_w_tab} ${_w_chn} 的 ${_w_expr}"
				fi
			fi
			;;
		esac
	done <<EOF
${DOC_W:-}
EOF

	# 读者：ip rule（mask 可能被补全成 0xffffffff）
	_c3_readers=""
	_c3_starved=""
	_c3_starved_n=0
	# mwan3 线路 rule 家族（fwmark <线值>/<mmx_mask>）：这是 mwan3 自己的读者，
	# 0x100/0x200/... 与 OAF 默认 mark 撞值也不改变归属（只做事实登记）。
	_c3_line_n=0
	_c3_line_vals=""
	while IFS="	" read -r _r_pref _r_val _r_mask _r_lk _r_iif _r_sup _r_not; do
		[ -n "${_r_pref:-}" ] || continue
		[ "$_r_val" = "-" ] && continue
		_c3_readers="${_c3_readers}${_c3_readers:+,}{\"where\":\"ip rule\",\"pref\":$(_doc_jstr "$_r_pref"),\"mask\":$(_doc_jstr "$_r_mask"),\"value\":$(_doc_jstr "$_r_val"),\"lookup\":$(_doc_jstr "$_r_lk")}"
		_doc_hx "$_r_val"
		_r_v=$HEX
		_doc_hx "$_r_mask"
		_r_m=$HEX
		if [ "$_r_m" -eq "$_M" ] && [ "$_r_v" -ne 0 ]; then
			_c3_line_n=$((_c3_line_n + 1))
			[ "$_c3_line_n" -le 8 ] &&
				_c3_line_vals="${_c3_line_vals}${_c3_line_vals:+,}$(_doc_jstr "$_r_val")"
		fi
		# 精确匹配（无掩码）且值的位段内有 mwan3 的位 -> mwan3 清位后这条规则失配
		if [ "$_r_m" -ne "$_M" ] && [ "$(( _r_v & _M ))" -ne 0 ]; then
			_c3_starved="${_c3_starved}${_c3_starved:+,}{\"where\":\"ip rule\",\"pref\":$(_doc_jstr "$_r_pref"),\"value\":$(_doc_jstr "$_r_val"),\"lookup\":$(_doc_jstr "$_r_lk")}"
			_c3_starved_n=$((_c3_starved_n + 1))
		fi
	done <<EOF
${DOC_P5:-}
EOF

	# 活体验证：拿 mwan3 自己的一个 mark 查一次路由（只读）
	_c3_route=""
	_c3_mark_ex=""
	while IFS="	" read -r _r_pref _r_val _r_mask _r_lk _r_iif _r_sup _r_not; do
		[ -n "${_r_pref:-}" ] || continue
		[ "$_r_val" = "-" ] && continue
		_doc_hx "$_r_mask"
		[ "$HEX" = "$_M" ] || continue
		_c3_mark_ex=$_r_val
		break
	done <<EOF
${DOC_P5:-}
EOF
	if [ -n "$_c3_mark_ex" ] && _doc_have ip; then
		_c3_rg=$(ip -4 route get 1.1.1.1 mark "$_c3_mark_ex" 2>/dev/null | head -1)
		_c3_dev=$(printf '%s' "$_c3_rg" | sed -n 's/.*[[:space:]]dev[[:space:]]\([^[:space:]]*\).*/\1/p')
		_c3_tab=$(printf '%s' "$_c3_rg" | sed -n 's/.*[[:space:]]table[[:space:]]\([^[:space:]]*\).*/\1/p')
		_c3_route="{\"mark\":$(_doc_jstr "$_c3_mark_ex"),\"dev\":$(_doc_jstr "$_c3_dev"),\"table\":$(_doc_jstr "$_c3_tab")}"
	else
		_c3_route="null"
	fi

	_c3_collision="null"
	if [ "$_c3_ct" -gt 0 ]; then
		_c3_collision="{\"kind\":\"ctmark\",\"count\":$_c3_ct,\"writers\":[$(_doc_jstr "$_c3_ct_names")],\"hint\":$(_doc_jstr "$_c3_hint"),\"hint_confidence\":$(_doc_jstr "$_c3_hint_conf"),\"hint_basis\":$(_doc_jstr "$_c3_hint_basis")}"
	fi
	DOC_C3_FACTS="\"mmx_mask\":$(_doc_jstr "$DOC_MMX_MASK"),\"mmx_mask_source\":$(_doc_jstr "$DOC_MMX_SOURCE"),\"writer_total\":$_c3_wn,\"writers\":[$_c3_writers],\"excluded_count\":$_c3_excl_n,\"excluded\":{\"mwan3\":$_c3_excl_mw,\"isp_split\":$_c3_excl_own},\"excluded_writers\":[$_c3_excluded],\"write_eval\":{\"rule\":\"覆盖位 = mask | orbits（跨字段）；同字段按 mask 内写 + mask 外清；无掩码整值写不可判定\",\"mmx_mask\":$(_doc_jstr "$DOC_MMX_MASK"),\"writers\":[$_c3_eval],\"disjoint_count\":$_c3_disjoint_n,\"read_direction_count\":$_c3_readn,\"unevaluable_count\":$_c3_unknown_n},\"line_mark_rules\":{\"owner\":\"mwan3\",\"mask\":$(_doc_jstr "$DOC_MMX_MASK"),\"count\":$_c3_line_n,\"values\":[$_c3_line_vals]},\"readers\":[$_c3_readers],\"mwan3_min_pref\":$DOC_MINPREF,\"third_party_outside_mask\":[$_c3_outside],\"reader_starved\":[$_c3_starved],\"collision\":$_c3_collision,\"route_get_mark\":$_c3_route"

	if [ "$DOC_P4B" != "1" ]; then
		DOC_C3_VERDICT=unknown
		_doc_find3 "" unknown "没有 mwan3 的 nft 表（inet/ip/ip6 都不存在，mwan3-nft 未运行），无法判定位段占用" "P4b"
		DOC_C3_ADVICE="先确认 mwan3（nft 版）在跑；只看 /etc/config/mwan3 无法判断运行态。"
	elif [ "$_c3_wn" -eq 0 ]; then
		DOC_C3_VERDICT=ok
		_doc_find3 "" ok "规则表里没有任何 mark 写者" "P4"
	elif [ "$_c3_ct" -gt 0 ]; then
		DOC_C3_VERDICT=conflict
		case "$_c3_hint_basis" in
		name) _c3_hint_txt="疑似 $(_doc_product_label "$_c3_hint")（表名/链名匹配，置信度高）" ;;
		value_signature) _c3_hint_txt="疑似 $(_doc_product_label "$_c3_hint")（ct mark 0x100 与 mwan3 的 wan1 线路值撞值；仅值签名，置信度低，不作判据）" ;;
		*) _c3_hint_txt="产品未识别（不建议按名字臆断）" ;;
		esac
		_c3_hint_txt_more=""
		[ "$_c3_ct_unknown" -gt 0 ] &&
			_c3_hint_txt_more="；其中 $_c3_ct_unknown 条 ct mark 写入形态无法静态求值（整值写/未加掩码），按保守口径计入"
		_doc_find3 "CTMARK_COLLISION" conflict "有第三方程序改写了 ct mark 中与 mmx_mask($DOC_MMX_MASK) 重叠的位：$_c3_ct_names；$_c3_hint_txt${_c3_hint_txt_more}" "P4 ct mark set（已排除 mwan3/isp-split 自家写者 $_c3_excl_n 条）"
	elif [ "$_c3_overlap_unordered" -gt 0 ]; then
		DOC_C3_VERDICT=conflict
		_doc_find3 "MARK_OVERLAP_UNORDERED" conflict "有 $_c3_overlap_unordered 个第三方写者落在 mmx_mask 位段内，且没有排在 mwan3 之前的 rule" "P4 + P5"
	elif [ "$_c3_overlap_ordered" -gt 0 ] || [ "$_c3_overlap" -gt 0 ]; then
		DOC_C3_VERDICT=warn
		_doc_find3 "MARK_OVERLAP_ORDERED" warn "有 $_c3_overlap 个第三方写者与位段有交集，但其 ip rule 排在 mwan3($DOC_MINPREF) 之前（先手），实际按它的规则走" "P4 + P5"
	elif [ "$_c3_outside_n" -gt 0 ]; then
		DOC_C3_VERDICT=ok
		_doc_find3 "MARK_OUTSIDE" ok "第三方 mark 写者共 $_c3_outside_n 个，全部落在 mmx_mask 之外" "P4"
	else
		DOC_C3_VERDICT=ok
		_doc_find3 "" ok "标记位段只有 mwan3/isp-split 自己在用（$_c3_excl_n 条自家写者已按归属排除，第三方 0 条）" "P4"
	fi
	# fix39：求值结论 = 无重叠的写者，逐条记 info。判据是"覆盖位 & mmx_mask == 0"，
	# 文案必须带上具体位段，否则用户只看到"现在不报了"而不知道为什么。
	while IFS= read -r _c3_note; do
		[ -n "${_c3_note:-}" ] || continue
		_doc_find3 "MARK_FWMARK_DISJOINT" info "$_c3_note" "P4 表达式求值：覆盖位 = mask | orbits；(mask|orbits) & mmx_mask($DOC_MMX_MASK) = 0"
	done <<EOF
${_c3_disjoint}
EOF
	if [ "$_c3_readn" -gt 0 ]; then
		_doc_find3 "MARK_READ_DIRECTION" info "有 $_c3_readn 条规则只读 ct mark、写 packet mark（读向，例如 ${_c3_read_txt}），不写 ct mark，不计入冲突" "P4 读向（ct -> packet）"
	fi
	if [ "$_c3_starved_n" -gt 0 ]; then
		[ "$DOC_C3_VERDICT" = "ok" ] && DOC_C3_VERDICT=warn
		_doc_find3 "MARK_READER_STARVED" warn "有 $_c3_starved_n 条精确 fwmark 的 ip rule 落在位段内：mwan3 无条件清位后它们不再匹配" "P4 + P5（COMPAT B1④）"
	fi
	[ "$DOC_MMX_MASK" != "$DOC_MASK_DEFAULT" ] &&
		_doc_find3 "MMX_MASK_CUSTOM" ok "mmx_mask=$(printf '%s' "$DOC_MMX_MASK") 不是默认 0x3F00，本报告的阈值已按它现算" "P11"

	case "$DOC_C3_VERDICT" in
	ok) DOC_C3_ADVICE="标记位段只有 mwan3/isp-split 自己（或位段之外的第三方）在用，分流选路正常。" ;;
	warn) DOC_C3_ADVICE="无需改动即可用；若要彻底消除歧义，把代理的 fwmark 移到 mmx_mask 之外（如 0x80000 段）。" ;;
	conflict)
		if [ "$_c3_ct" -gt 0 ]; then
			DOC_C3_ADVICE="检测到第三方程序改写了 mwan3 用的 ct mark 位段（mmx_mask）；分流可能选错线。先把它的 mark 值移到位段之外，或让它排在 mwan3 之后；产品名只是提示，别按名字下结论。"
		else
			DOC_C3_ADVICE="检测到第三方程序改写了与 mwan3 相同的标记位，分流可能选错线；建议把它的标记值改到位段之外，或把它排到 mwan3 之后。"
		fi
		;;
	unknown) DOC_C3_ADVICE="没能读取当前 nft 规则，无法判断标记位是否被占用。" ;;
	esac
	DOC_C3_FIND="$_c3_find"
}

# ---------------------------------------------------------------- 检查四：统计口径
doc_check_offload() {
	DOC_C4_ID="offload_accounting"
	DOC_C4_TITLE="flow offload / turboacc 对统计口径的影响"
	DOC_C4_VERDICT=ok
	DOC_C4_CONF=high

	doc_p8_offload
	doc_p9_conntrack

	_c4_devs=""
	_c4_truth=""
	# 只有默认路由设备与 lan 设备两个取样点：足够交叉显示，不引入额外开销
	_c4_rg=$DOC_RG_DEV
	[ -n "${_c4_rg:-}" ] || _c4_rg=$(_doc_have ip && ip -4 route show default 2>/dev/null |
		sed -n 's/.*[[:space:]]dev[[:space:]]\([^[:space:]]*\).*/\1/p' | head -1)
	for _c4_d in $_c4_rg $(printf '%s\n' "$DOC_DEF_V4" | sed -n 's/.*[[:space:]]dev[[:space:]]\([^[:space:]]*\).*/\1/p'); do
		[ -n "${_c4_d:-}" ] || continue
		case " $_c4_devs " in
		*" $_c4_d "*) continue ;;
		esac
		set -- $(_doc_dev_bytes "$_c4_d")
		[ "$1" = "-" ] && continue
		_c4_devs="$_c4_devs $_c4_d"
		_c4_truth="${_c4_truth}${_c4_truth:+,}{\"dev\":$(_doc_jstr "$_c4_d"),\"rx_bytes\":$(_doc_jstr "$1"),\"tx_bytes\":$(_doc_jstr "$2")}"
	done

	DOC_C4_FACTS="\"flow_offloading\":$(_doc_jstr "$DOC_OFF_SW"),\"flow_offloading_hw\":$(_doc_jstr "$DOC_OFF_HW"),\"vocabulary\":{\"flowtable_chains\":$DOC_OFF_FLOWTABLE,\"flow_add_rules\":$DOC_OFF_FLOWADD},\"owner\":{\"turboacc_uci\":$(_doc_jbool "$DOC_OFF_TURBOACC"),\"vendor_accel\":$(_doc_jstr "$DOC_OFF_VENDOR")},\"conntrack\":{\"count\":$(_doc_jstr "$DOC_CT_COUNT"),\"max\":$(_doc_jstr "$DOC_CT_MAX"),\"acct\":$(_doc_jstr "$DOC_CT_ACCT"),\"tcp_established\":$(_doc_jstr "$DOC_CT_EST"),\"tuned_by\":$(_doc_jstr "$DOC_CT_TUNED")},\"truth_counters\":[${_c4_truth}]"

	_c4_find=""
	_doc_find4() {
		_c4_find="${_c4_find}${_c4_find:+,}{\"code\":$(_doc_jstr "$1"),\"verdict\":$(_doc_jstr "$2"),\"detail\":$(_doc_jstr "$3"),\"evidence\":$(_doc_jstr "$4")}"
	}
	if [ "$DOC_OFF_HW" = "1" ] || [ -n "${DOC_OFF_VENDOR:-}" ]; then
		DOC_C4_VERDICT=conflict
		DOC_C4_CONF=medium
		_doc_find4 "OFFLOAD_HW_ROUTING" conflict "已开启硬件流量加速：除了统计偏差，mwan3 的选路语义也可能失效" "uci flow_offloading_hw=$DOC_OFF_HW / vendor=$DOC_OFF_VENDOR"
	elif [ "$DOC_OFF_SW" = "1" ]; then
		DOC_C4_VERDICT=warn
		_doc_find4 "OFFLOAD_SW_COUNTERS" warn "软件 flow offload 生效：已建流的后续包不走 mwan3_rules，命中包数只反映建连首包" "uci flow_offloading=1；flowtable=$DOC_OFF_FLOWTABLE flow_add=$DOC_OFF_FLOWADD"
	elif [ "$DOC_OFF_FLOWADD" -gt 0 ]; then
		DOC_C4_VERDICT=warn
		_doc_find4 "OFFLOAD_STALE" warn "uci 里 offload 已关，但规则表里仍有 flow add 规则（改了没 reload）" "P4 计数=$DOC_OFF_FLOWADD"
	else
		DOC_C4_VERDICT=ok
		_doc_find4 "" ok "没有开启流量加速，页面上的命中包数与实际流量口径一致" "P8"
	fi

	case "$DOC_C4_VERDICT" in
	ok) DOC_C4_ADVICE="无需处理；命中包数可以直接当参考。" ;;
	warn) DOC_C4_ADVICE="统计口径问题，不影响分流选路：要看真实速率请读 /sys/class/net/<wan>/statistics/。不要为了数字关掉 offload。" ;;
	conflict) DOC_C4_ADVICE="建议先关掉硬件加速（firewall.@defaults[0].flow_offloading_hw=0）并 fw4 reload，观察分流是否恢复；这台固件也可能默认就开着，不是你的操作。" ;;
	esac
	DOC_C4_FIND="$_c4_find"
}

# ---------------------------------------------------------------- 检查五：写者清单
doc_check_writers() {
	DOC_C5_ID="mark_writers"
	DOC_C5_TITLE="第三方 mark 写者清单与 mwan3 归属"
	DOC_C5_VERDICT=ok
	DOC_C5_CONF=high

	if [ -z "${DOC_W:-}" ] && [ "${DOC_P4_RC:-0}" -ne 0 ]; then
		DOC_C5_VERDICT=unknown
		DOC_C5_CONF=low
		DOC_C5_FACTS="\"counts\":{},\"writers\":[],\"foreign_chains_in_mwan3\":[],\"legacy_writers\":[]"
		DOC_C5_FIND=""
		DOC_C5_ADVICE="没能读取 nft 规则表，无法列出标记写者。"
		return 0
	fi

	_c5_total=0
	_c5_mw=0
	_c5_own=0
	_c5_third=0
	_c5_inmask=0
	_c5_out=0
	_c5_legacy=0
	_c5_legacy_inmask=0
	_c5_third_inmask=0
	# 清单分两段：第三方/legacy 最多 40 条（决策相关，优先展示），
	# mwan3/isp-split 自家写者最多 10 条（生产上 mwan3_or_* 有上百条，
	# 全列会把真正的第三方挤出清单）。
	_c5_list=""
	_c5_list_n=0
	_c5_list_mw=""
	_c5_list_mw_n=0
	while IFS="	" read -r _w_fam _w_tab _w_chn _w_hnd _w_fld _w_form _w_msk _w_val _w_cm _w_src; do
		[ -n "${_w_fam:-}" ] || continue
		_c5_total=$((_c5_total + 1))
		_w_owner=$(_doc_owner_of "$_w_fam" "$_w_tab" "$_w_chn" "$_w_cm")
		# 与检查三同源求值（fix39）：不允许两套"写了哪些位"的算法漂移
		_doc_wr_eval "$_w_fld" "$_w_form" "$_w_msk" "$_w_val" "${_w_src:-}"
		if [ "$WR_KNOWN" = "0" ]; then
			_w_touched=$DOC_MMX_MASK_DEC
		else
			_w_touched=$(( WR_CLEAR | WR_BITS ))
		fi
		_w_prod=$(_doc_guess_product "$_w_fam" "$_w_tab" "$_w_chn")
		case "$_w_owner" in
		mwan3) _c5_mw=$((_c5_mw + 1)) ;;
		isp-split) _c5_own=$((_c5_own + 1)) ;;
		legacy) _c5_legacy=$((_c5_legacy + 1)) ;;
		*) _c5_third=$((_c5_third + 1)) ;;
		esac
		if [ "$(( _w_touched & DOC_MMX_MASK_DEC ))" -ne 0 ]; then
			_c5_inmask=$((_c5_inmask + 1))
			case "$_w_owner" in
			legacy) _c5_legacy_inmask=$((_c5_legacy_inmask + 1)) ;;
			third_party) _c5_third_inmask=$((_c5_third_inmask + 1)) ;;
			esac
		else
			_c5_out=$((_c5_out + 1))
		fi
		# JSON 体积上限 + 优先级：第三方最多 40 条，自家写者最多 10 条
		case "$_w_owner" in
		mwan3 | isp-split)
			if [ "$_c5_list_mw_n" -lt 10 ]; then
				_c5_list_mw_n=$((_c5_list_mw_n + 1))
				_c5_list_mw="${_c5_list_mw}${_c5_list_mw:+,}{\"owner\":$(_doc_jstr "$_w_owner"),\"product_guess\":$(_doc_jstr "$_w_prod"),\"fam\":$(_doc_jstr "$_w_fam"),\"table\":$(_doc_jstr "$_w_tab"),\"chain\":$(_doc_jstr "$_w_chn"),\"handle\":$(_doc_jstr "$_w_hnd"),\"field\":$(_doc_jstr "$_w_fld"),\"form\":$(_doc_jstr "$_w_form"),\"mask\":$(_doc_jstr "$([ "$_w_msk" = "-" ] && printf '' || printf '%s' "$_w_msk")"),\"value\":$(_doc_jstr "$([ "$_w_val" = "-" ] && printf '' || printf '%s' "$_w_val")"),\"touched\":$(_doc_jstr "$(_doc_hxstr "$_w_touched")")}"
			fi
			;;
		*)
			if [ "$_c5_list_n" -lt 40 ]; then
				_c5_list_n=$((_c5_list_n + 1))
				_c5_list="${_c5_list}${_c5_list:+,}{\"owner\":$(_doc_jstr "$_w_owner"),\"product_guess\":$(_doc_jstr "$_w_prod"),\"fam\":$(_doc_jstr "$_w_fam"),\"table\":$(_doc_jstr "$_w_tab"),\"chain\":$(_doc_jstr "$_w_chn"),\"handle\":$(_doc_jstr "$_w_hnd"),\"field\":$(_doc_jstr "$_w_fld"),\"form\":$(_doc_jstr "$_w_form"),\"mask\":$(_doc_jstr "$([ "$_w_msk" = "-" ] && printf '' || printf '%s' "$_w_msk")"),\"value\":$(_doc_jstr "$([ "$_w_val" = "-" ] && printf '' || printf '%s' "$_w_val")"),\"touched\":$(_doc_jstr "$(_doc_hxstr "$_w_touched")")}"
			fi
			;;
		esac
	done <<EOF
${DOC_W:-}
EOF

	# mwan3 表里的外来链（有人往 mwan3 表里塞规则）。
	# 3.6 的自有链名并不都是 mwan3* 前缀（iface_in_*、policy_*、dynamic、mwan3_hook），
	# 只认 mwan3* 会把 mwan3 自己的子链当成"外来"（fix38 同一类误判）。
	_c5_foreign=""
	_c5_foreign_n=0
	if [ -n "${DOC_P4:-}" ]; then
		while IFS= read -r _c5_f; do
			[ -n "$_c5_f" ] || continue
			_c5_foreign="${_c5_foreign}${_c5_foreign:+,}$(_doc_jstr "$_c5_f")"
			_c5_foreign_n=$((_c5_foreign_n + 1))
		done <<EOF
$(printf '%s\n' "$DOC_P4" | awk '
	/^[ \t]*table / {
		intab = (($2 == "inet" || $2 == "ip" || $2 == "ip6") &&
		         ($3 == "mwan3" || $3 ~ /^mwan3[_-]/))
		next
	}
	{
		if (!intab) next
		tl = $0
		sub(/^[ \t]*/, "", tl)
		if (index(tl, "chain ") != 1) next
		n = split(tl, A, " ")
		c = A[2]
		if (c ~ /^mwan3/ || c ~ /^iface_(in|out)_/ || c ~ /^policy_/ || c ~ /^dynamic/ || c == "mwan3_hook") next
		print c
	}')
EOF
	fi

	_c5_writers_all="$_c5_list"
	[ -n "$_c5_list_mw" ] &&
		_c5_writers_all="${_c5_writers_all}${_c5_writers_all:+,}${_c5_list_mw}"
	DOC_C5_FACTS="\"counts\":{\"total\":$_c5_total,\"mwan3\":$_c5_mw,\"isp_split\":$_c5_own,\"third_party\":$_c5_third,\"legacy\":$_c5_legacy,\"legacy_in_mask\":$_c5_legacy_inmask,\"in_mask\":$_c5_inmask,\"third_party_in_mask\":$_c5_third_inmask,\"outside_mask\":$_c5_out},\"writers\":[$_c5_writers_all],\"foreign_chains_in_mwan3\":[$_c5_foreign],\"legacy_writers\":$(_doc_jbool "$([ "$_c5_legacy" -gt 0 ] && printf 1 || printf 0)")"

	_c5_find=""
	_doc_find5() {
		_c5_find="${_c5_find}${_c5_find:+,}{\"code\":$(_doc_jstr "$1"),\"verdict\":$(_doc_jstr "$2"),\"detail\":$(_doc_jstr "$3"),\"evidence\":$(_doc_jstr "$4")}"
	}
	# 继承检查三的结论：3 已判 conflict 时本项不重复计数
	if [ "${DOC_C3_VERDICT:-ok}" = "conflict" ]; then
		_c5_verdict=conflict
	elif [ "$_c5_foreign_n" -gt 0 ]; then
		_c5_verdict=warn
		_doc_find5 "MWAN3_TABLE_FOREIGN_CHAIN" warn "mwan3 表里有不属于 mwan3 的链（已排除 mwan3*/iface_in_*/iface_out_*/policy_*/dynamic 等自有链名）：$_c5_foreign" "P4"
	elif [ "$_c5_legacy_inmask" -gt 0 ]; then
		_c5_verdict=warn
		_doc_find5 "LEGACY_MARK_WRITER" warn "非 mwan3 的 ip/ip6 表里有 mark 写者落在 mmx_mask 位段内（iptables-nft 残留），清单里已列出" "P4 fam=ip/ip6"
	elif [ "$_c5_third" -eq 0 ] && [ "$_c5_legacy" -eq 0 ]; then
		_c5_verdict=ok
		_doc_find5 "" ok "规则表里没有第三方 mark 写者" "P4"
	elif [ "$_c5_third_inmask" -gt 0 ] && [ "${DOC_C3_VERDICT:-ok}" != "warn" ]; then
		_c5_verdict=warn
		_doc_find5 "MARK_WRITERS_IN_MASK" warn "有写者的位段与 mmx_mask 有交集（明细见清单）" "P4 + P5"
	else
		_c5_verdict=ok
		_c5_out_txt="第三方写者共 $_c5_third 个，均不在 mmx_mask 位段内"
		[ "$_c5_legacy" -gt 0 ] &&
			_c5_out_txt="第三方/legacy 写者共 $((_c5_third + _c5_legacy)) 个，写入位均不在 mmx_mask 位段内（ip/ip6 表里的 $_c5_legacy 条经掩码表达式求值也不重叠）"
		_doc_find5 "MARK_WRITERS_OUTSIDE" ok "$_c5_out_txt" "P4"
	fi
	DOC_C5_VERDICT=$_c5_verdict
	DOC_C5_ADVICE="清单仅供排查；位段是否真的冲突以 mark_segment 的结论为准。"
	DOC_C5_FIND="$_c5_find"
}

# ---------------------------------------------------------------- 检查六：共存白名单
#
# 白名单是"版本绑定"的：G1–G5 是机制门槛（每次现算），G6 是版本基线。
# 六条全过才 green；只有 G6 不过 -> green_with_version_drift（展示为绿但带角标）。
_doc_wl_baseline() {
	case "$1" in
	tailscale) printf '1.78' ;;
	ddns-go) printf '5.7' ;;
	*) printf '' ;;
	esac
}

# 产品是否装了：二进制 / uci / 配置文件，任一命中即算
_doc_wl_installed() {
	case "$1" in
	tailscale)
		_doc_have tailscale || _doc_have tailscaled || [ -f /etc/config/tailscale ] || [ -e /sys/class/net/tailscale0 ]
		;;
	ntopng)
		_doc_have ntopng || [ -f /etc/config/ntopng ] || [ -d /etc/ntopng ]
		;;
	ddns-go)
		_doc_have ddns-go || [ -f /etc/config/ddns-go ] || [ -f /etc/ddns-go/config.yaml ]
		;;
	*) return 1 ;;
	esac
}

_doc_wl_running() {
	case "$1" in
	tailscale) pidof tailscaled >/dev/null 2>&1 ;;
	ntopng) pidof ntopng >/dev/null 2>&1 ;;
	ddns-go) pidof ddns-go >/dev/null 2>&1 ;;
	*) return 1 ;;
	esac
}

_doc_wl_comm() {
	case "$1" in
	tailscale) printf 'tailscaled' ;;
	ntopng) printf 'ntopng' ;;
	ddns-go) printf 'ddns-go' ;;
	*) printf '' ;;
	esac
}

doc_check_whitelist() {
	DOC_C6_ID="coexist_whitelist"
	DOC_C6_TITLE="已实测共存白名单（tailscale / ntopng / ddns-go）"
	DOC_C6_VERDICT=ok
	DOC_C6_CONF=medium

	_c6_products=""
	_c6_find=""
	_doc_find6() {
		_c6_find="${_c6_find}${_c6_find:+,}{\"code\":$(_doc_jstr "$1"),\"verdict\":$(_doc_jstr "$2"),\"detail\":$(_doc_jstr "$3"),\"evidence\":$(_doc_jstr "$4")}"
	}
	_c6_warn=""
	_c6_worst=ok

	for _p in tailscale ntopng ddns-go; do
		_inst=0
		_doc_wl_installed "$_p" && _inst=1
		_run=0
		_doc_wl_running "$_p" && _run=1
		_ver=""
		[ "$_inst" = "1" ] && _ver=$(doc_pkg_version "$_p")
		_base=$(_doc_wl_baseline "$_p")
		_vib=null
		if [ -n "$_base" ] && [ -n "${_ver:-}" ]; then
			case "$_ver" in
			"$_base"*) _vib=1 ;;
			*) _vib=0 ;;
			esac
		fi
		# G1：不占 LAN 面 :53
		_g1=1
		if [ "$_run" = "1" ]; then
			case "${DOC_C1_FACTS:-}" in
			*"\"comm\":\"$(_doc_wl_comm "$_p")\""*) _g1=0 ;;
			esac
		fi
		# G2：没有覆盖位段的写者
		_g2=1
		case " ${DOC_C3_OVERLAP_NAMES:-} " in
		*" $_p "*) _g2=0 ;;
		esac
		# G3：没有 pref 更小且会改默认路径的 rule（tailscale 的精确 fwmark 例外）
		_g3=1
		case "$_p" in
		tailscale)
			# fwmark 0x80000 与 mmx 位段无交集：命中也不例外
			_g3=1
			;;
		*)
			case " ${DOC_C3_OVERLAP_NAMES:-} " in
			*" $_p "*) _g3=0 ;;
			esac
			;;
		esac
		# G4：不改 offload / 默认路由
		_g4=1
		[ "${DOC_OFF_TURBOACC:-0}" = "1" ] && [ "$_p" = "turboacc" ] && _g4=0
		# G5：不往 inet mwan3 塞链
		_g5=1
		if [ "${DOC_C5_FACTS:-}" != "" ]; then
			case "$DOC_C5_FACTS" in
			*"foreign_chains_in_mwan3\":[\"$_p"*) _g5=0 ;;
			esac
		fi
		# G6：版本在基线内
		_g6=null
		case "$_vib" in
		1) _g6=1 ;;
		0) _g6=0 ;;
		esac

		_state=not_running
		if [ "$_inst" = "0" ]; then
			_state=not_installed
		elif [ "$_run" = "0" ]; then
			_state=not_running
		elif [ "$_g1" = "0" ] || [ "$_g2" = "0" ] || [ "$_g3" = "0" ] || [ "$_g4" = "0" ] || [ "$_g5" = "0" ]; then
			_state=conflict
		elif [ "$_g6" = "0" ]; then
			_state=green_with_version_drift
		else
			_state=green
		fi

		# 即使 GREEN 也要说的事（不升 verdict）；没装就不提
		case "$_inst" in
		0) _p_skip_warn=1 ;;
		*) _p_skip_warn=0 ;;
		esac
		[ "$_p_skip_warn" = "1" ] || case "$_p" in
		tailscale)
			_en=$(uci -q get tailscale.settings.exit_node 2>/dev/null) || _en=""
			if [ -n "${_en:-}" ] && [ "$_en" != "0" ]; then
				_c6_warn="${_c6_warn}${_c6_warn:+,}{\"product\":\"tailscale\",\"code\":\"EXIT_NODE_HIJACK\",\"detail\":\"uci tailscale.settings.exit_node=$_en：全部上网流量走 tailnet，分流彻底不生效\",\"verdict\":\"warn\"}"
				[ "$_c6_worst" = "ok" ] && _c6_worst=warn
			fi
			;;
		ntopng)
			if [ "${DOC_CT_ACCT:-}" = "1" ]; then
				_c6_warn="${_c6_warn}${_c6_warn:+,}{\"product\":\"ntopng\",\"code\":\"CT_ACCT_BYTES\",\"detail\":\"nf_conntrack_acct=1：ntopng 的连接级字节与 nft 规则计数不同源\",\"verdict\":\"warn\"}"
				[ "$_c6_worst" = "ok" ] && _c6_worst=warn
			fi
			;;
		ddns-go)
			_c6_warn="${_c6_warn}${_c6_warn:+,}{\"product\":\"ddns-go\",\"code\":\"NO_IFACE_BIND\",\"detail\":\"ddns-go 不支持绑定出接口：无法按线路取出口 IP（需要按线测出口 IP 请用本工具的探测）\",\"verdict\":\"warn\"}"
			[ "$_c6_worst" = "ok" ] && _c6_worst=warn
			;;
		esac

		case "$_state" in
		conflict) [ "$_c6_worst" != "conflict" ] && _c6_worst=conflict ;;
		green_with_version_drift) [ "$_c6_worst" = "ok" ] && _c6_worst=warn ;;
		esac

		_c6_products="${_c6_products}${_c6_products:+,}{\"name\":$(_doc_jstr "$_p"),\"installed\":$(_doc_jbool "$_inst"),\"running\":$(_doc_jbool "$_run"),\"version\":$(_doc_jstr "$_ver"),\"version_in_baseline\":$_vib,\"gates\":{\"G1\":$(_doc_jbool "$_g1"),\"G2\":$(_doc_jbool "$_g2"),\"G3\":$(_doc_jbool "$_g3"),\"G4\":$(_doc_jbool "$_g4"),\"G5\":$(_doc_jbool "$_g5"),\"G6\":$_g6},\"state\":$(_doc_jstr "$_state")}"
	done

	DOC_C6_FACTS="\"products\":[$_c6_products],\"warnings_kept\":[$_c6_warn]"
	if [ "$_c6_worst" = "ok" ]; then
		_doc_find6 "WHITELIST_GREEN" ok "白名单产品与实测基线一致，五条机制门槛全过" "P7 + P5 + P10"
	else
		_doc_find6 "WHITELIST_REVIEW" "$_c6_worst" "白名单里有产品需要复核（见 products[].gates 与 warnings_kept）" "P7 + P5 + P10"
	fi
	DOC_C6_VERDICT=$_c6_worst
	DOC_C6_ADVICE="可以共存；若发现分流不生效，先确认没有开 tailscale 的 exit node、也没有别的代理在改默认路由。"
	DOC_C6_FIND="$_c6_find"
}

# ---------------------------------------------------------------- 汇总 / 输出

doc_summary() {
	DOC_SUM_OK=0
	DOC_SUM_WARN=0
	DOC_SUM_CONFLICT=0
	DOC_SUM_UNKNOWN=0
	# 只统计本次真的跑了的检查：--profile=page 只跑 1/4/6，把没跑的 2/3/5
	# 算成 unknown 会让页面快照永远显示"三项不知道"（实测踩过）。
	for _s in ${DOC_RUN_SET:-1 2 3 4 5 6}; do
		case "$_s" in
		1) _v=${DOC_C1_VERDICT:-unknown} ;;
		2) _v=${DOC_C2_VERDICT:-unknown} ;;
		3) _v=${DOC_C3_VERDICT:-unknown} ;;
		4) _v=${DOC_C4_VERDICT:-unknown} ;;
		5) _v=${DOC_C5_VERDICT:-unknown} ;;
		6) _v=${DOC_C6_VERDICT:-unknown} ;;
		esac
		case "$_v" in
		ok) DOC_SUM_OK=$((DOC_SUM_OK + 1)) ;;
		warn) DOC_SUM_WARN=$((DOC_SUM_WARN + 1)) ;;
		conflict) DOC_SUM_CONFLICT=$((DOC_SUM_CONFLICT + 1)) ;;
		*) DOC_SUM_UNKNOWN=$((DOC_SUM_UNKNOWN + 1)) ;;
		esac
	done
	# 偏序：conflict > warn > unknown > ok
	if [ "$DOC_SUM_CONFLICT" -gt 0 ]; then
		DOC_SUM_WORST=conflict
	elif [ "$DOC_SUM_WARN" -gt 0 ]; then
		DOC_SUM_WORST=warn
	elif [ "$DOC_SUM_UNKNOWN" -gt 0 ]; then
		DOC_SUM_WORST=unknown
	else
		DOC_SUM_WORST=ok
	fi

	# gate：能不能继续 wire/apply。主机前提与兼容矩阵都算进来。
	DOC_GATE_CAN_WIRE=1
	DOC_GATE_REASONS=""
	DOC_GATE_REASONS_TEXT=""
	_gate_add() {
		DOC_GATE_CAN_WIRE=0
		DOC_GATE_REASONS="${DOC_GATE_REASONS}${DOC_GATE_REASONS:+,}$(_doc_jstr "$1")"
		DOC_GATE_REASONS_TEXT="${DOC_GATE_REASONS_TEXT}${DOC_GATE_REASONS_TEXT:+, }$1"
	}
	doc_mwan3_installed || _gate_add "MWAN3_NOT_INSTALLED"
	if doc_mwan3_installed && ! doc_mwan3_is_nft; then
		_gate_add "MWAN3_NOT_NFT"
	fi
	[ "${DOC_NFT_OK:-0}" = "1" ] || _gate_add "NFT_MISSING_OR_OLD"
	[ "${DOC_P4B:-0}" = "1" ] || _gate_add "MWAN3_TABLE_MISSING"
	[ -n "${DOC_BINS_MISSING:-}" ] && _gate_add "BIN_MISSING:${DOC_BINS_MISSING}"
	[ "${DOC_MEM_VERDICT:-ok}" = "warn" ] && _gate_add "MEM_LOW"
	[ "$DOC_SUM_CONFLICT" -gt 0 ] && _gate_add "CHECK_CONFLICT"

	# headline：第一条 conflict 的 detail，否则 worst 的第一条 warn
	DOC_SUM_HEADLINE=""
	if [ "$DOC_SUM_CONFLICT" -gt 0 ]; then
		DOC_SUM_HEADLINE=$(_doc_first_detail conflict)
	elif [ "$DOC_SUM_WARN" -gt 0 ]; then
		DOC_SUM_HEADLINE=$(_doc_first_detail warn)
	fi
	[ -n "${DOC_SUM_HEADLINE:-}" ] || DOC_SUM_HEADLINE="没有发现会让分流静默失效的冲突"
}

_doc_first_detail() { # <verdict> -> 第一条匹配的 finding detail
	_dfv_want=$1
	for _dfv_i in 1 2 3 4 5 6; do
		case "$_dfv_i" in
		1) _dfv_f=${DOC_C1_FIND:-} ;;
		2) _dfv_f=${DOC_C2_FIND:-} ;;
		3) _dfv_f=${DOC_C3_FIND:-} ;;
		4) _dfv_f=${DOC_C4_FIND:-} ;;
		5) _dfv_f=${DOC_C5_FIND:-} ;;
		6) _dfv_f=${DOC_C6_FIND:-} ;;
		esac
		_dfv_d=$(printf '%s\n' "$_dfv_f" |
			sed -n "s/.*\"verdict\":\"$_dfv_want\",\"detail\":\"\([^\"]*\)\".*/\1/p" | head -1)
		[ -n "${_dfv_d:-}" ] && {
			printf '%s' "$_dfv_d"
			return 0
		}
	done
	return 0
}

_doc_check_json() { # <n>
	case "$1" in
	1) _cj_id=${DOC_C1_ID} _cj_title=${DOC_C1_TITLE} _cj_v=${DOC_C1_VERDICT} _cj_c=${DOC_C1_CONF} _cj_facts=${DOC_C1_FACTS} _cj_find=${DOC_C1_FIND} _cj_adv=${DOC_C1_ADVICE} ;;
	2) _cj_id=${DOC_C2_ID} _cj_title=${DOC_C2_TITLE} _cj_v=${DOC_C2_VERDICT} _cj_c=${DOC_C2_CONF} _cj_facts=${DOC_C2_FACTS} _cj_find=${DOC_C2_FIND} _cj_adv=${DOC_C2_ADVICE} ;;
	3) _cj_id=${DOC_C3_ID} _cj_title=${DOC_C3_TITLE} _cj_v=${DOC_C3_VERDICT} _cj_c=${DOC_C3_CONF} _cj_facts=${DOC_C3_FACTS} _cj_find=${DOC_C3_FIND} _cj_adv=${DOC_C3_ADVICE} ;;
	4) _cj_id=${DOC_C4_ID} _cj_title=${DOC_C4_TITLE} _cj_v=${DOC_C4_VERDICT} _cj_c=${DOC_C4_CONF} _cj_facts=${DOC_C4_FACTS} _cj_find=${DOC_C4_FIND} _cj_adv=${DOC_C4_ADVICE} ;;
	5) _cj_id=${DOC_C5_ID} _cj_title=${DOC_C5_TITLE} _cj_v=${DOC_C5_VERDICT} _cj_c=${DOC_C5_CONF} _cj_facts=${DOC_C5_FACTS} _cj_find=${DOC_C5_FIND} _cj_adv=${DOC_C5_ADVICE} ;;
	6) _cj_id=${DOC_C6_ID} _cj_title=${DOC_C6_TITLE} _cj_v=${DOC_C6_VERDICT} _cj_c=${DOC_C6_CONF} _cj_facts=${DOC_C6_FACTS} _cj_find=${DOC_C6_FIND} _cj_adv=${DOC_C6_ADVICE} ;;
	esac
	printf '{"id":"%s","title":"%s","verdict":"%s","status":"%s","confidence":"%s","facts":{%s},"findings":[%s],"advice":"%s"}' \
		"$(_doc_esc "$_cj_id")" "$(_doc_esc "$_cj_title")" "$_cj_v" \
		"$([ "$_cj_v" = "conflict" ] && printf fail || printf '%s' "$_cj_v")" \
		"$_cj_c" "${_cj_facts:-}" "${_cj_find:-}" "$(_doc_esc "${_cj_adv:-}")"
}

doc_json() {
	_dj_checks=""
	for _dj_i in $DOC_RUN_SET; do
		_dj_checks="${_dj_checks}${_dj_checks:+,}$(_doc_check_json "$_dj_i")"
	done
	printf '{"schema":%s,"tool":{"name":"isp-split","version":"%s"},"generated":%s,"generated_text":"%s","profile":"%s","host":{%s},"checks":[%s],"summary":{"ok":%s,"warn":%s,"conflict":%s,"unknown":%s,"worst":"%s","blocking":%s,"headline":"%s"},"gate":{"can_wire":%s,"reasons":[%s]},"probe_errors":[%s],"ms":%s}\n' \
		"$DOC_SCHEMA" "$(_doc_esc "${ISP_VERSION:-0.0.0}")" "$DOC_GEN" "$(_doc_esc "$DOC_GEN_TEXT")" \
		"$DOC_PROFILE" "$DOC_HOST_JSON" "$_dj_checks" \
		"$DOC_SUM_OK" "$DOC_SUM_WARN" "$DOC_SUM_CONFLICT" "$DOC_SUM_UNKNOWN" "$DOC_SUM_WORST" \
		"$(_doc_jbool "$([ "$DOC_SUM_WORST" = "conflict" ] && printf 1 || printf 0)")" \
		"$(_doc_esc "$DOC_SUM_HEADLINE")" "$(_doc_jbool "$DOC_GATE_CAN_WIRE")" "${DOC_GATE_REASONS:-}" \
		"${DOC_PROBE_ERR:-}" "$(( $(_doc_now_ms) - ${DOC_T0:-0} ))"
}

DOC_HOST_JSON=""
doc_host_json() {
	DOC_HOST_JSON="\"openwrt\":{\"id\":$(_doc_jstr "${DOC_FW_ID:-}"),\"release\":$(_doc_jstr "${DOC_FW_RELEASE:-}"),\"target\":$(_doc_jstr "${DOC_FW_TARGET:-}"),\"rev\":$(_doc_jstr "${DOC_FW_REV:-}")},\"kernel\":$(_doc_jstr "$(uname -r 2>/dev/null)"),\"arch\":$(_doc_jstr "${DOC_ARCH:-}"),\"nft\":$(_doc_jstr "${DOC_NFT_VERSION:-}"),\"pkgmgr\":$(_doc_jstr "$(_doc_have apk && printf apk || { _doc_have opkg && printf opkg || printf none; })"),\"mwan3\":{\"installed\":$(_doc_jbool "$(doc_mwan3_installed && printf 1 || printf 0)"),\"version\":$(_doc_jstr "$(doc_pkg_version mwan3)"),\"nft\":$(_doc_jbool "$(doc_mwan3_is_nft && printf 1 || printf 0)"),\"table\":$(_doc_jbool "${DOC_P4B:-0}"),\"mmx_mask\":$(_doc_jstr "${DOC_MMX_MASK:-}"),\"mmx_mask_source\":$(_doc_jstr "${DOC_MMX_SOURCE:-}")},\"mem\":{\"total_kb\":${DOC_MEM_TOTAL_KB:-0},\"avail_kb\":${DOC_MEM_AVAIL_KB:-0},\"verdict\":$(_doc_jstr "${DOC_MEM_VERDICT:-unknown}")},\"bins\":{${DOC_BINS_JSON:-}},\"root\":$(_doc_jbool "$([ "$(id -u 2>/dev/null)" = "0" ] && printf 1 || printf 0)")"
}

_doc_text_check() { # <n> <idx> <total>
	_dt_n=$1
	_dt_i=$2
	_dt_tot=$3
	case "$_dt_n" in
	1) _dt_v=${DOC_C1_VERDICT} _dt_t=${DOC_C1_TITLE} _dt_c=${DOC_C1_CONF} _dt_a=${DOC_C1_ADVICE} _dt_f=${DOC_C1_FIND} _dt_fa=${DOC_C1_FACTS} ;;
	2) _dt_v=${DOC_C2_VERDICT} _dt_t=${DOC_C2_TITLE} _dt_c=${DOC_C2_CONF} _dt_a=${DOC_C2_ADVICE} _dt_f=${DOC_C2_FIND} _dt_fa=${DOC_C2_FACTS} ;;
	3) _dt_v=${DOC_C3_VERDICT} _dt_t=${DOC_C3_TITLE} _dt_c=${DOC_C3_CONF} _dt_a=${DOC_C3_ADVICE} _dt_f=${DOC_C3_FIND} _dt_fa=${DOC_C3_FACTS} ;;
	4) _dt_v=${DOC_C4_VERDICT} _dt_t=${DOC_C4_TITLE} _dt_c=${DOC_C4_CONF} _dt_a=${DOC_C4_ADVICE} _dt_f=${DOC_C4_FIND} _dt_fa=${DOC_C4_FACTS} ;;
	5) _dt_v=${DOC_C5_VERDICT} _dt_t=${DOC_C5_TITLE} _dt_c=${DOC_C5_CONF} _dt_a=${DOC_C5_ADVICE} _dt_f=${DOC_C5_FIND} _dt_fa=${DOC_C5_FACTS} ;;
	6) _dt_v=${DOC_C6_VERDICT} _dt_t=${DOC_C6_TITLE} _dt_c=${DOC_C6_CONF} _dt_a=${DOC_C6_ADVICE} _dt_f=${DOC_C6_FIND} _dt_fa=${DOC_C6_FACTS} ;;
	esac
	printf '\n[%s/%s] %s\n' "$_dt_i" "$_dt_tot" "$_dt_t"
	printf '  状态: %s  置信度: %s\n' "$_dt_v" "$_dt_c"
	# detail 逐条（同一 check 的多条 finding 各一行）
	printf '%s\n' "$_dt_f" | sed 's/},{"code"/}\n{"code"/g' | while IFS= read -r _dt_line; do
		_dt_code=$(printf '%s' "$_dt_line" | sed -n 's/.*"code":"\([^"]*\)".*/\1/p')
		_dt_det=$(printf '%s' "$_dt_line" | sed -n 's/.*"detail":"\([^"]*\)".*/\1/p')
		[ -n "$_dt_det" ] || continue
		if [ -n "$_dt_code" ]; then
			printf '  · [%s] %s\n' "$_dt_code" "$_dt_det"
		else
			printf '  · %s\n' "$_dt_det"
		fi
	done
	printf '  建议: %s\n' "$_dt_a"
}

doc_text() {
	printf '== 环境体检（doctor）%s  %s\n' "$(_doc_esc "${ISP_VERSION:-0.0.0}")" "$DOC_GEN_TEXT"
	_dt_mv=$(doc_pkg_version mwan3)
	[ -n "${_dt_mv:-}" ] || _dt_mv=-
	printf '主机: %s %s %s  内核 %s  nft %s  mwan3 %s(%s)  mmx_mask %s(%s)\n' \
		"${DOC_FW_ID:-?}" "${DOC_FW_RELEASE:-?}" "${DOC_FW_TARGET:-?}" \
		"$(uname -r 2>/dev/null)" "${DOC_NFT_VERSION:-?}" \
		"$_dt_mv" \
		"$(doc_mwan3_is_nft && printf 'nft' || printf 'iptables/未知')" \
		"${DOC_MMX_MASK:-?}" "${DOC_MMX_SOURCE:-?}"
	printf '内存: 共 %s kB / 可用 %s kB（%s）\n' "${DOC_MEM_TOTAL_KB:-0}" "${DOC_MEM_AVAIL_KB:-0}" "${DOC_MEM_VERDICT:-unknown}"
	[ -n "${DOC_BINS_MISSING:-}" ] && printf '缺少必需命令: %s\n' "$DOC_BINS_MISSING"
	_dt_i=0
	for _dt_n in $DOC_RUN_SET; do
		_dt_i=$((_dt_i + 1))
		_doc_text_check "$_dt_n" "$_dt_i" "$DOC_RUN_COUNT"
	done
	printf '\n== 汇总: ok %s  warn %s  conflict %s  unknown %s（最差: %s）\n' \
		"$DOC_SUM_OK" "$DOC_SUM_WARN" "$DOC_SUM_CONFLICT" "$DOC_SUM_UNKNOWN" "$DOC_SUM_WORST"
	printf '  结论: %s\n' "$DOC_SUM_HEADLINE"
	if [ "$DOC_GATE_CAN_WIRE" = "1" ]; then
		printf '  wire/apply 门: 可以继续\n'
	else
		printf '  wire/apply 门: 阻断（%s）\n' "${DOC_GATE_REASONS_TEXT:-}"
	fi
	[ -n "${DOC_PROBE_ERR:-}" ] && printf '  探针降级: %s\n' "$DOC_PROBE_ERR"
}

# ---------------------------------------------------------------- 入口

doc_main() {
	DOC_T0=$(_doc_now_ms)
	DOC_GEN=$(date +%s 2>/dev/null || printf '0')
	DOC_GEN_TEXT=$(_doc_ts_text)
	DOC_PROBES=""
	DOC_PROBE_ERR=""
	DOC_PROFILE=full
	DOC_JSON_MODE=0
	DOC_STRICT=0
	while [ $# -gt 0 ]; do
		case "$1" in
		--json) DOC_JSON_MODE=1 ;;
		--strict) DOC_STRICT=1 ;;
		--deep) DOC_PROFILE=deep ;;
		--profile=*)
			case "${1#--profile=}" in
			page | full | deep) DOC_PROFILE=${1#--profile=} ;;
			*) printf '未知 profile: %s（可用 page|full|deep）\n' "${1#--profile=}" >&2 ;;
			esac
			;;
		-h | --help)
			cat <<'DOCHELP'
用法: isp-split doctor [--json] [--profile=page|full|deep] [--strict]
  只读环境体检：六项兼容矩阵 + 主机前提。不产生业务流量、不改任何配置。
  --json           stdout 只有一份 JSON（人类可读的提示走 stderr）
  --profile=page   只跑检查 1/4/6，汇总也只统计这 3 项（供页面快照；
                   C1/C4 仍需读一次规则表，不是零成本）
  --profile=deep   预留：满载时降级为 full。1s 采样（计数冻结 / TUN 流量）
                   尚未实现，当前与 full 等价
  --strict         unknown 也算"不能继续用"（退出码 1）
退出码: 0 可以继续 / 1 有保留(warn) / 2 有东西会静默失效(conflict)
DOCHELP
			return 0
			;;
		*)
			printf '未知参数: %s（用法: isp-split doctor [--json] [--profile=...] [--strict]）\n' "$1" >&2
			# 用法错误必须非 0：以前返回 0 会让 `doctor --typo` 静默"成功"且一项没跑。
			return 2
			;;
		esac
		shift
	done

	case "$DOC_PROFILE" in
	page) DOC_RUN_SET="1 4 6" ;;
	*) DOC_RUN_SET="1 2 3 4 5 6" ;;
	esac
	DOC_RUN_COUNT=0
	for _x in $DOC_RUN_SET; do DOC_RUN_COUNT=$((DOC_RUN_COUNT + 1)); done

	# deep 目前与 full 等价（1s 采样未实现）；满载时直接降级，避免体检本身把路由器压垮。
	if [ "$DOC_PROFILE" = "deep" ]; then
		_load=$(awk '{ print $1 }' /proc/loadavg 2>/dev/null || printf '0')
		_ncpu=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null) || true
		case "${_load:-}" in '' | *[!0-9.]*) _load=0 ;; esac
		case "${_ncpu:-}" in '' | *[!0-9]*) _ncpu=1 ;; esac
		_over=$(awk -v l="$_load" -v n="$_ncpu" 'BEGIN { print (l > n) ? 1 : 0 }')
		if [ "$_over" = "1" ]; then
			printf '负载 %.2f 高于 CPU 数 %s，deep 采样已跳过（降级为 full）\n' "$_load" "$_ncpu" >&2
			DOC_PROFILE=full
		fi
	fi

	# 主机前提（探针共享的缓存都在这之后才有值）
	doc_host_firmware || {
		DOC_FW_ID=""
	}
	doc_host_mem >/dev/null
	doc_nft_version || true
	doc_bins
	doc_p11_mask
	doc_p4b_table
	doc_p4_ruleset
	doc_p4_writers
	doc_p5_iprule
	doc_p6_route
	doc_p7_tun
	doc_p8_offload
	doc_p9_conntrack

	doc_check_dns53
	for _x in $DOC_RUN_SET; do
		case "$_x" in
		2) doc_check_tun ;;
		3) doc_check_mark ;;
		4) doc_check_offload ;;
		5) doc_check_writers ;;
		6) doc_check_whitelist ;;
		esac
	done
	# 检查三/五的依赖顺序：3 必须在 5 之前（5 继承 3 的结论），6 在最后。
	doc_host_json
	doc_summary

	if [ "$DOC_JSON_MODE" = "1" ]; then
		doc_json
	else
		doc_text
	fi

	# 退出码（C7 7.2）：0 可以继续 / 1 有保留 / 2 会静默失效
	if [ "$DOC_SUM_CONFLICT" -gt 0 ]; then
		return 2
	fi
	if [ "$DOC_SUM_WARN" -gt 0 ]; then
		return 1
	fi
	if [ "$DOC_STRICT" = "1" ] && [ "$DOC_SUM_UNKNOWN" -gt 0 ]; then
		return 1
	fi
	return 0
}
