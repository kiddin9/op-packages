#!/bin/sh
# 卸载清理的唯一实现（F-14）
#
# 背景：卸载有三条路径，以前各写各的清单：
#   1. isp-split uninstall（cmd_uninstall）——摘规则、删策略、删数据目录，
#      但不删命名计数器 isp_fallback，也不删 /usr/sbin/isp-split 等文件
#   2. scripts/install.sh --uninstall——只删 LuCI 资源，脚本与配置全留着
#   3. 包 postrm——删 cron/计数器/confdir，包文件则由包管理器删
# 结果：Hermes 动态复现 install.sh --uninstall rc=0，而
# /usr/sbin/isp-split、/etc/init.d/isp-split、/usr/lib/isp-split/、
# /etc/isp-split.conf、isp_fallback 计数器、.conf.bak.* 全留着。
#
# 现在三条路径都走这里，清单只有一份：
#   isp-split uninstall             -> 先摘 mwan3 规则（要 rules-splice.awk），再 all
#   scripts/install.sh --uninstall  -> 先调 isp-split uninstall（若在），再 all
#   包 postrm                       -> 二进制还在就调本脚本 runtime；包文件已被删时
#                                      才走内联兜底（清单锚点由 selftest 第 21 节双向核对）
#
# 用法：
#   sh teardown.sh all        # mwan3 段 + runtime 残留 + 文件
#   sh teardown.sh mwan3      # 只删 mwan3 里 isp_split=1 的 ipset/policy/member
#   sh teardown.sh runtime    # cron 行 / isp_fallback 计数器 / dnsmasq confdir 与片段 / LuCI 缓存
#   sh teardown.sh files      # 本工具安装的文件（含 /etc/isp-split 数据目录）
#   sh teardown.sh --list     # 打印清单（selftest 与 postrm 漂移断言用），不动作
# 选项：
#   --keep-conf-bak           # 保留 /etc/isp-split.conf.bak.*（默认删除并逐条打印）
#
# 为什么默认删 .conf.bak.*：它们是安装脚本每次覆盖安装都会新生成的副本，
# 不是用户手写的备份。留着等于"卸载"留下一批与工具同名同前缀的孤儿文件，
# 重装时再叠一层；删除前会逐条打印路径，想留档可以照路径先 cp 走。要长期
# 留档就显式 --keep-conf-bak，行为可选且可见。
#
# 环境变量（与 isp-split 同名同义；自检/打包用）：
#   ISP_SPLIT_DESTDIR   根前缀（默认空）。设置后所有绝对路径都加上它，
#                       用于在沙箱里演练卸载，不碰宿主 /usr /etc
#   ISP_SPLIT_BASE      /etc/isp-split
#   ISP_SPLIT_CONF      /etc/isp-split.conf
#   ISP_SPLIT_CRONTAB   /etc/crontabs/root
#   ISP_SPLIT_LIB       /usr/lib/isp-split
#   DNSDIR              旧版片段目录（默认 <BASE>/dnsmasq.d）
#   DNSMASQ_DEFAULT_DIR dnsmasq 默认 conf-dir（默认 /tmp/dnsmasq.d）
#   DNSMASQ_CONF_GLOB   运行配置 glob（默认 /var/etc/dnsmasq.conf.*）
#   MWAN3_SERVICE / CRON_SERVICE / RPCD_SERVICE  服务脚本（自检可换 stub）
set -u

DESTDIR=${ISP_SPLIT_DESTDIR:-}
case "$DESTDIR" in
"" | "/") DESTDIR="" ;;
/*) DESTDIR=${DESTDIR%/} ;;
*)
	echo "ISP_SPLIT_DESTDIR 必须是绝对路径: '$DESTDIR'" >&2
	exit 1
	;;
esac

BASE=${ISP_SPLIT_BASE:-$DESTDIR/etc/isp-split}
CONF=${ISP_SPLIT_CONF:-$DESTDIR/etc/isp-split.conf}
CRONTAB=${ISP_SPLIT_CRONTAB:-$DESTDIR/etc/crontabs/root}
LIB=${ISP_SPLIT_LIB:-$DESTDIR/usr/lib/isp-split}
DNSDIR=${DNSDIR:-$BASE/dnsmasq.d}
DNSMASQ_DEFAULT_DIR=${DNSMASQ_DEFAULT_DIR:-$DESTDIR/tmp/dnsmasq.d}
DNSMASQ_CONF_GLOB=${DNSMASQ_CONF_GLOB:-$DESTDIR/var/etc/dnsmasq.conf.*}
STATE_DIR=$BASE/state
# B-5：状态文件名与语义对齐——它记的是"迁移后写进 UCI 的清理值"，不是原值。
STATE_NEW=$STATE_DIR/dnsmasq.confdir.migrated
STATE_OLD=$STATE_DIR/dnsmasq.confdir.orig
MWAN3_SERVICE=${MWAN3_SERVICE:-$DESTDIR/etc/init.d/mwan3}
CRON_SERVICE=${CRON_SERVICE:-$DESTDIR/etc/init.d/cron}
RPCD_SERVICE=${RPCD_SERVICE:-$DESTDIR/etc/init.d/rpcd}

KEEP_CONF_BAK=0
SCOPE=""

say() { printf '[teardown] %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# 只有真实根（DESTDIR 为空）才动服务：沙箱演练里重启服务既没意义，也会误伤宿主。
svc_restart() {
	[ -z "$DESTDIR" ] || return 0
	[ -x "$1" ] || return 0
	"$1" restart >/dev/null 2>&1 || true
	return 0
}

# ---------------------------------------------------------------- 清单

# 文件/目录清单（相对 DESTDIR）。--list 与 files 段共用，杜绝两处漂移。
files_list() {
	cat <<'EOF'
path usr/sbin/isp-split
path etc/init.d/isp-split
dir usr/lib/isp-split
path etc/isp-split.conf
glob etc/isp-split.conf.bak.*
dir etc/isp-split
path etc/uci-defaults/99-isp-split
dir www/luci-static/resources/view/isp-split
dir www/luci-static/resources/isp-split
path usr/share/luci/menu.d/luci-app-isp-split.json
# lc:begin
# 体检页的 menu 节点只在完整版里存在；0 版（FEATURE_LINECHECK=0）连这一行
# 都不该留在卸载清单里（strip-linecheck.sh 的零残留断言会抓，19b.2 覆盖）。
path usr/share/luci/menu.d/luci-app-isp-split-linecheck.json
# lc:end
path usr/share/rpcd/acl.d/luci-app-isp-split.json
EOF
}

# runtime 的锚点：每一条都必须能在 Makefile postrm 的内联兜底里找到
# （selftest 第 21 节双向核对，防"三条路径又各写一份"）。
runtime_anchors() {
	cat <<'EOF'
anchor nft delete counter inet mwan3 isp_fallback
anchor /etc/isp-split/state/dnsmasq.confdir.migrated
anchor /etc/isp-split/state/dnsmasq.confdir.orig
anchor conf-dir=
anchor /tmp/dnsmasq.d/isp-split.conf
anchor /etc/isp-split/dnsmasq.d/isp-split.conf
anchor .isp-split-cron.XXXXXX
anchor rm -rf /etc/isp-split
EOF
}

print_list() {
	echo "== 卸载清单（唯一实现：teardown.sh）=="
	echo "-- mwan3（UCI 段 + 服务重载）--"
	echo "  带 isp_split=1 标记的 ipset 段（含改名/删除的孤儿段）"
	echo "  带 isp_split=1 标记的 policy 段"
	echo "  带 isp_split=1 标记的 member 段（仍被其它策略引用的保留）"
	echo "  nft 规则块由 isp-split uninstall 的 rules-splice 摘除"
	echo "-- runtime 残留 --"
	echo "  crontab 里的 isp-split 行"
	echo "  nft 命名计数器 isp_fallback"
	echo "  dnsmasq confdir 状态文件（恢复 UCI 后删除）"
	echo "  dnsmasq 片段 isp-split.conf（探测目录 + 默认目录 + 旧版目录）"
	echo "  LuCI 缓存目录"
	echo "-- 文件 --"
	files_list | while read -r _k _v; do
		case "$_k" in
		path) echo "  $_v" ;;
		dir) echo "  $_v/（目录）" ;;
		glob) echo "  $_v（历史备份，默认删除；--keep-conf-bak 保留）" ;;
		esac
	done
	echo "-- 机器可读 --"
	files_list
	runtime_anchors
}

# ---------------------------------------------------------------- mwan3

# 按 isp_split=1 标记删，而不是按"当前 ISP_TABLE 的名字"删：改名/删除的
# 旧段会漏掉，永远清不掉（B-4）。无标记的段一律不碰。
cmd_mwan3() {
	if ! have uci; then
		say "没有 uci，跳过 mwan3 段清理"
		return 0
	fi
	_mw_n=0
	for _mw_sec in $(uci -q show mwan3 2>/dev/null |
		sed -n 's/^mwan3\.\([^=]*\)=ipset$/\1/p'); do
		[ "$(uci -q get "mwan3.$_mw_sec.isp_split" 2>/dev/null)" = "1" ] || continue
		uci -q delete "mwan3.$_mw_sec" 2>/dev/null && _mw_n=$((_mw_n + 1))
	done

	_mw_np=0
	for _mw_sec in $(uci -q show mwan3 2>/dev/null |
		sed -n 's/^mwan3\.\([^=]*\)=policy$/\1/p'); do
		[ "$(uci -q get "mwan3.$_mw_sec.isp_split" 2>/dev/null)" = "1" ] || continue
		uci -q delete "mwan3.$_mw_sec" 2>/dev/null && _mw_np=$((_mw_np + 1))
	done

	# member 段：仍被任何策略引用的不能删（删了 mwan3 会渲染失败）
	_mw_refs=" "
	for _mw_psec in $(uci -q show mwan3 2>/dev/null |
		sed -n 's/^mwan3\.\([^=]*\)=policy$/\1/p'); do
		for _mw_x in $(uci -q get "mwan3.$_mw_psec.use_member" 2>/dev/null); do
			_mw_refs="$_mw_refs$_mw_x "
		done
	done
	_mw_nm=0
	for _mw_sec in $(uci -q show mwan3 2>/dev/null |
		sed -n 's/^mwan3\.\([^=]*\)=member$/\1/p'); do
		[ "$(uci -q get "mwan3.$_mw_sec.isp_split" 2>/dev/null)" = "1" ] || continue
		case "$_mw_refs" in
		*" $_mw_sec "*)
			say "警告：成员段 $_mw_sec 仍被其它策略引用，保留"
			continue
			;;
		esac
		uci -q delete "mwan3.$_mw_sec" 2>/dev/null && _mw_nm=$((_mw_nm + 1))
	done
	uci -q commit mwan3 2>/dev/null || true

	[ "$_mw_n" -gt 0 ] &&
		say "已删除 $_mw_n 个带 isp_split 标记的 ipset 段（含改名/删除的孤儿段）"
	[ "$_mw_np" -gt 0 ] || [ "$_mw_nm" -gt 0 ] &&
		say "已删除 $_mw_np 个带 isp_split 标记的策略段、$_mw_nm 个成员段"

	# 规则已由 rules-splice 摘掉，这里 reload 让集合/策略随之消失。
	if [ -x "$MWAN3_SERVICE" ]; then
		"$MWAN3_SERVICE" reload >/dev/null 2>&1 || true
	fi
	return 0
}

# ---------------------------------------------------------------- runtime

# B-5：旧名里存的是"迁移后的清理值"，名字与语义不符（PROPOSAL-0.2.2 §B-5）。
# 升级上来的设备可能还留着旧名：迁到新名，之后只认新名。迁移失败也不阻断，
# 因为读取侧两个名字都认。
_state_adopt() {
	[ -f "$STATE_NEW" ] && return 0
	[ -f "$STATE_OLD" ] || return 0
	if mv -f "$STATE_OLD" "$STATE_NEW" 2>/dev/null; then
		say "旧状态文件 dnsmasq.confdir.orig 已迁移为 dnsmasq.confdir.migrated（B-5）"
	else
		cp -f "$STATE_OLD" "$STATE_NEW" 2>/dev/null && rm -f "$STATE_OLD"
	fi
	return 0
}

_state_read() {
	if [ -f "$STATE_NEW" ]; then
		head -1 "$STATE_NEW" 2>/dev/null | tr -d '\r'
	elif [ -f "$STATE_OLD" ]; then
		head -1 "$STATE_OLD" 2>/dev/null | tr -d '\r'
	fi
	return 0
}

# 片段可能残留的目录：运行配置里的 conf-dir=（权威源）+ UCI 当前值 +
# 状态文件记录值 + 默认目录 + 旧版目录，去重后逐行输出。
_frag_dirs() {
	{
		for _fd_f in $DNSMASQ_CONF_GLOB; do
			[ -f "$_fd_f" ] || continue
			sed -n 's/^[[:space:]]*conf-dir=//p' "$_fd_f" 2>/dev/null
		done
		printf '%s\n' "${_frag_uci:-}" "${_frag_state:-}" \
			"$DNSMASQ_DEFAULT_DIR" "$DNSDIR"
	} | tr ' ' '\n' |
		sed -e 's/,.*$//' -e 's/^"//' -e 's/"$//' -e 's:/*$::' |
		awk 'NF && !seen[$0]++'
}

cmd_runtime() {
	_state_adopt
	_orig=$(_state_read)
	_frag_state=$_orig
	_frag_uci=""
	have uci && _frag_uci=$(uci -q get dhcp.@dnsmasq[0].confdir 2>/dev/null || true)

	# 1) 恢复 UCI confdir：只有真的改过（有状态文件）才碰 UCI。
	if [ -f "$STATE_NEW" ] || [ -f "$STATE_OLD" ]; then
		if [ -n "$_orig" ]; then
			if [ "$_frag_uci" != "$_orig" ]; then
				if uci -q set "dhcp.@dnsmasq[0].confdir=$_orig" 2>/dev/null &&
					uci -q commit dhcp 2>/dev/null; then
					say "已恢复 dnsmasq confdir=$_orig"
				fi
			fi
		elif [ -n "$_frag_uci" ]; then
			if uci -q delete dhcp.@dnsmasq[0].confdir 2>/dev/null &&
				uci -q commit dhcp 2>/dev/null; then
				say "已恢复 dnsmasq confdir（回落到默认 $DNSMASQ_DEFAULT_DIR）"
			fi
		fi
	fi
	rm -f "$STATE_NEW" "$STATE_OLD" 2>/dev/null || true

	# 2) 清片段。探测来源优先，但不依赖探测是否成功——目录列表是并集。
	_n=0
	for _d in $(_frag_dirs); do
		[ -f "$_d/isp-split.conf" ] || continue
		rm -f "$_d/isp-split.conf" 2>/dev/null && _n=$((_n + 1))
	done
	[ "$_n" -gt 0 ] && say "已清理 $_n 处 dnsmasq 片段 isp-split.conf"

	# 3) 命名计数器（旧版只有包 postrm 删它，脚本卸载路径漏了）
	if have nft && nft list table inet mwan3 >/dev/null 2>&1; then
		if nft list counter inet mwan3 isp_fallback >/dev/null 2>&1; then
			nft delete counter inet mwan3 isp_fallback >/dev/null 2>&1 &&
				say "已删除 nft 计数器 inet mwan3 isp_fallback"
		fi
	fi

	# 4) crontab 行。mktemp 而不是固定 /tmp 名：/tmp 世界可写，符号链接能抢占（SEC-1）。
	if [ -f "$CRONTAB" ] && grep -q 'isp-split' "$CRONTAB" 2>/dev/null; then
		_cron_dir=$(dirname "$CRONTAB")
		_cron_tmp=$(mktemp "$_cron_dir/.isp-split-cron.XXXXXX" 2>/dev/null) ||
			_cron_tmp=$(mktemp "$CRONTAB.XXXXXX" 2>/dev/null) || _cron_tmp=""
		if [ -n "$_cron_tmp" ]; then
			grep -v 'isp-split' "$CRONTAB" > "$_cron_tmp" 2>/dev/null || true
			if mv -f "$_cron_tmp" "$CRONTAB"; then
				say "已移除 crontab 里的 isp-split 行"
				svc_restart "$CRON_SERVICE"
			else
				rm -f "$_cron_tmp"
			fi
		fi
	fi

	# 5) LuCI 缓存（页面文件在 files 段删）
	rm -rf "$DESTDIR"/tmp/luci-indexcache* "$DESTDIR"/tmp/luci-modulecache* 2>/dev/null || true
	return 0
}

# ---------------------------------------------------------------- files

cmd_files() {
	_del=0
	_err=0
	while read -r _k _p; do
		case "$_k" in
		path)
			[ -e "$DESTDIR/$_p" ] || [ -L "$DESTDIR/$_p" ] || continue
			if rm -f "$DESTDIR/$_p"; then
				_del=$((_del + 1))
			else
				say "错误：删不掉 $DESTDIR/$_p"
				_err=1
			fi
			;;
		dir)
			[ -d "$DESTDIR/$_p" ] || continue
			if rm -rf "$DESTDIR/$_p"; then
				_del=$((_del + 1))
			else
				say "错误：删不掉 $DESTDIR/$_p"
				_err=1
			fi
			;;
		glob)
			# 这里必须真的做通配：把目录与文件名分开，目录加引号（容忍空格），
			# 文件名部分不加引号交给 shell 展开。整段引号会把 `*` 当成字面量，
			# 结果一个 .bak 都删不掉（自检 21.2/21.4 抓到的第一版 bug）。
			_gdir=$(dirname "$DESTDIR/$_p")
			_gbase=$(basename "$_p")
			for _g in "$_gdir"/$_gbase; do
				[ -f "$_g" ] || continue
				if [ "$KEEP_CONF_BAK" = "1" ]; then
					say "保留历史配置备份: $_g（--keep-conf-bak）"
					continue
				fi
				# 删除前逐条打印：想留档可以在同一台机器上先照路径 cp 走。
				say "删除历史配置备份: $_g"
				if rm -f "$_g"; then
					_del=$((_del + 1))
				else
					say "错误：删不掉 $_g"
					_err=1
				fi
			done
			;;
		esac
	done <<EOF
$(files_list)
EOF

	# BASE 可被 ISP_SPLIT_BASE 改名（自检沙箱），清单里的是默认路径，这里补上
	# 真实值。ISP_SPLIT_LIB 故意不参与删除：它只用于离线自检，可能指到源码树，
	# 删它会把仓库自己的 usr/lib/isp-split 抹掉。
	if [ "$BASE" != "$DESTDIR/etc/isp-split" ] && [ -d "$BASE" ]; then
		if rm -rf "$BASE"; then
			_del=$((_del + 1))
		else
			say "错误：删不掉 $BASE"
			_err=1
		fi
	fi

	if [ "$_del" -gt 0 ]; then
		say "已删除 $_del 项文件/目录"
	else
		say "没有需要删除的文件"
	fi
	if [ "$_err" -ne 0 ]; then
		say "有文件删不掉（只读挂载或权限问题），卸载不完整"
		return 1
	fi
	return 0
}

# ---------------------------------------------------------------- main

while [ $# -gt 0 ]; do
	case "$1" in
	--keep-conf-bak) KEEP_CONF_BAK=1 ;;
	--list) SCOPE=list ;;
	all | mwan3 | runtime | files) SCOPE=$1 ;;
	-h | --help)
		sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		echo "未知参数: $1（可用：all|mwan3|runtime|files|--list|--keep-conf-bak）" >&2
		exit 2
		;;
	esac
	shift
done

if [ -z "$SCOPE" ]; then
	echo "用法: sh teardown.sh all|mwan3|runtime|files|--list [--keep-conf-bak]" >&2
	exit 2
fi

case "$SCOPE" in
list) print_list ;;
mwan3) cmd_mwan3 ;;
runtime) cmd_runtime ;;
files) cmd_files ;;
all)
	cmd_mwan3
	cmd_runtime
	svc_restart "$RPCD_SERVICE"
	cmd_files
	;;
esac
