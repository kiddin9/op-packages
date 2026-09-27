# shellcheck shell=busybox
# SPDX-License-Identifier: GPL-2.0-only
# Stand-in for /lib/functions.sh with the two calls thermal-guard makes. Reads
# the UCI file "$UCI_CONFIG_DIR/<package>" and fills CONFIG_<section>_<option>
# the way the original does: list values joined with a space, lists cleared
# before each load, plain options left alone.
# Like the original it is not safe under set -u: the load reads unset
# variables, and config_get expands its fourth argument for a missing option.

config_load() {
	local kw name val sect="" item
	if [ -z "$CONFIG_APPEND" ]; then
		for item in $CONFIG_LIST_STATE; do
			unset "CONFIG_$item"
		done
		CONFIG_LIST_STATE=""
	fi
	[ -r "$UCI_CONFIG_DIR/$1" ] || return 1
	while read -r kw name val; do
		val=${val#[\'\"]}; val=${val%[\'\"]}
		case "$kw" in
			config) sect=$val; continue ;;
			option|list) ;;
			*) continue ;;
		esac
		case "$sect$name" in
			''|*[!A-Za-z0-9_]*) continue ;;
		esac
		if [ "$kw" = option ]; then
			eval "CONFIG_${sect}_$name=\$val"
			continue
		fi
		case " $CONFIG_LIST_STATE " in
			*" ${sect}_$name "*)
				eval "CONFIG_${sect}_$name=\"\$CONFIG_${sect}_$name \$val\"" ;;
			*)
				CONFIG_LIST_STATE="$CONFIG_LIST_STATE ${sect}_$name"
				eval "CONFIG_${sect}_$name=\$val" ;;
		esac
	done < "$UCI_CONFIG_DIR/$1"
}

config_get() {
	case "$2$3" in
		*[!A-Za-z0-9_]*) return 0 ;;
	esac
	eval "$1=\${CONFIG_$2_$3:-\${4}}"
}
