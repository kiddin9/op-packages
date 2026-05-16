#!/bin/sh
# luci-app-openclaw 统一路径解析工具
#
# 为什么单独抽出来:
#   OpenClaw 的安装根目录会被 init、openclaw-env、Web PTY、LuCI 控制器等多处使用。
#   如果每处都自己拼路径，用户输入 /mnt/data/openclaw 时就容易得到
#   /mnt/data/openclaw/openclaw 这种错误路径，后续权限修复和卸载也会变得危险。

oc_normalize_install_path() {
	local raw="${1:-}"

	# 空值统一回到 /opt，保持历史兼容。
	[ -n "$raw" ] || raw="/opt"

	# 去掉首尾空白和末尾斜杠。OpenWrt busybox sed 支持基础表达式。
	raw=$(printf '%s' "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s:/*$::')
	[ -n "$raw" ] || raw="/"

	case "$raw" in
		/*) ;;
		*) return 1 ;;
	esac

	case "$raw" in
		*[\ \	]*|*\'*|*\"*|*\`*|*\$*|*\;*|*\&*|*\|*|*\<*|*\>*|*\(*|*\)*)
			return 1
			;;
	esac

	case "$raw" in
		/|/proc|/proc/*|/sys|/sys/*|/dev|/dev/*|/tmp|/tmp/*|/var|/var/*|/etc|/etc/*|/usr|/usr/*|/bin|/bin/*|/sbin|/sbin/*|/lib|/lib/*|/rom|/rom/*|/overlay|/overlay/*)
			return 1
			;;
	esac

	# 用户如果填写的是实际运行目录 /xxx/openclaw，这里回退到根目录 /xxx。
	case "$raw" in
		*/openclaw)
			raw=${raw%/openclaw}
			[ -n "$raw" ] || raw="/"
			;;
	esac

	printf '%s\n' "$raw"
}

oc_quote() {
	# POSIX 单引号转义，用于拼接少量必须经 shell 执行的命令。
	printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

oc_load_paths() {
	local input="${1:-}"
	local normalized

	normalized=$(oc_normalize_install_path "$input") || return 1

	OPENCLAW_INSTALL_PATH="$normalized"
	if [ "$OPENCLAW_INSTALL_PATH" = "/" ]; then
		OC_ROOT="/openclaw"
	else
		OC_ROOT="${OPENCLAW_INSTALL_PATH}/openclaw"
	fi
	NODE_BASE="${OC_ROOT}/node"
	OC_GLOBAL="${OC_ROOT}/global"
	OC_DATA="${OC_ROOT}/data"
	CONFIG_FILE="${OC_DATA}/.openclaw/openclaw.json"

	export OPENCLAW_INSTALL_PATH OC_ROOT NODE_BASE OC_GLOBAL OC_DATA CONFIG_FILE
}

oc_find_existing_path() {
	local path="$1"
	while [ -n "$path" ] && [ "$path" != "/" ]; do
		[ -e "$path" ] && { printf '%s\n' "$path"; return 0; }
		path=${path%/*}
	done
	printf '/\n'
}

oc_probe_writable_root() {
	local base="$1"
	local probe_parent
	local probe_dir

	probe_parent=$(oc_find_existing_path "$base")
	[ -d "$probe_parent" ] || return 1
	[ -w "$probe_parent" ] || return 1

	probe_dir="${probe_parent}/.openclaw-write-test-$$"
	if mkdir "$probe_dir" 2>/dev/null; then
		rmdir "$probe_dir" 2>/dev/null || true
		return 0
	fi

	return 1
}

oc_safe_openclaw_root() {
	local root="${1:-}"
	case "$root" in
		*/openclaw) ;;
		*) return 1 ;;
	esac
	case "$root" in
		/openclaw|/opt/openclaw|/mnt/*/openclaw|/media/*/openclaw|/srv/*/openclaw|/overlay/upper/opt/openclaw)
			return 0
			;;
	esac
	return 1
}
