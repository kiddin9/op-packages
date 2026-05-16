#!/bin/sh
# OpenClaw Node.js 版本校验工具。

oc_normalize_node_version() {
	local raw="${1:-}"
	raw=${raw#v}
	case "$raw" in
		[0-9]*.[0-9]*.[0-9]*) printf '%s\n' "$raw"; return 0 ;;
	esac
	return 1
}

oc_read_node_version() {
	local node_bin="$1"
	local raw
	[ -x "$node_bin" ] || return 1
	raw=$("$node_bin" --version 2>/dev/null) || return 1
	oc_normalize_node_version "$raw"
}

oc_node_version_ge() {
	local current required
	current=$(oc_normalize_node_version "$1") || return 1
	required=$(oc_normalize_node_version "$2") || return 1

	awk -v a="$current" -v b="$required" '
		BEGIN {
			split(a, av, "."); split(b, bv, ".");
			for (i = 1; i <= 3; i++) {
				ai = av[i] + 0; bi = bv[i] + 0;
				if (ai > bi) exit 0;
				if (ai < bi) exit 1;
			}
			exit 0;
		}
	'
}

oc_assert_node_min_version() {
	local node_bin="$1"
	local required="$2"
	local current

	current=$(oc_read_node_version "$node_bin") || {
		echo "  [✗] Node.js 不可执行或无法读取版本: $node_bin"
		return 1
	}

	if ! oc_node_version_ge "$current" "$required"; then
		echo "  [✗] Node.js v${current} 低于 OpenClaw 要求 v${required}"
		echo "  [!] 请重新运行 openclaw-env node 或 openclaw-env setup 更新运行时"
		return 1
	fi

	echo "  [✓] Node.js v${current} 满足要求 (>= v${required})"
	return 0
}
