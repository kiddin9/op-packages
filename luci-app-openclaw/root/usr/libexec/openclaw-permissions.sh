#!/bin/sh
# OpenClaw state permission helper.
# Keep runtime state writable by the openclaw user, while keeping plugin source
# directories root-owned for OpenClaw's official ownership checks.

oc_perm_state_dir() {
	if [ -n "${1:-}" ]; then
		printf '%s\n' "$1"
	elif [ -n "${OPENCLAW_STATE_DIR:-}" ]; then
		printf '%s\n' "$OPENCLAW_STATE_DIR"
	elif [ -n "${OC_DATA:-}" ]; then
		printf '%s/.openclaw\n' "$OC_DATA"
	else
		printf '/opt/openclaw/data/.openclaw\n'
	fi
}

oc_perm_data_dir_from_state() {
	local state_dir="$1"
	case "$state_dir" in
		*/.openclaw) printf '%s\n' "${state_dir%/.openclaw}" ;;
		*) printf '%s\n' "${OC_DATA:-/opt/openclaw/data}" ;;
	esac
}

oc_fix_npm_projects_permissions() {
	local state_dir npm_projects plugin_json plugin_dir
	state_dir="$(oc_perm_state_dir "${1:-}")"
	npm_projects="${state_dir}/npm/projects"
	[ -d "$npm_projects" ] || return 0

	# Gateway must be able to clean npm project generations.
	chown -R openclaw:openclaw "$npm_projects" 2>/dev/null || true
	chmod u+rwx,go+rx "$npm_projects" 2>/dev/null || true

	# Actual OpenClaw plugin roots must stay root-owned, otherwise OpenClaw refuses
	# to load them with "suspicious ownership".
	find "$npm_projects" -name openclaw.plugin.json -type f 2>/dev/null | while IFS= read -r plugin_json; do
		plugin_dir="${plugin_json%/openclaw.plugin.json}"
		case "$plugin_dir" in
			*__openclaw-generation__*)
				# Retained generation dirs are temporary and must remain removable by openclaw.
				;;
			"$npm_projects"/*/node_modules/*)
				chown -R root:root "$plugin_dir" 2>/dev/null || true
				chmod -R 755 "$plugin_dir" 2>/dev/null || true
				;;
		esac
	done

	# Compatibility for the WeChat plugin path even if its manifest scan fails.
	find "$npm_projects" -path '*/node_modules/@tencent-weixin/openclaw-weixin' -type d -prune \
		-exec chown -R root:root {} \; -exec chmod -R 755 {} \; 2>/dev/null || true
}

oc_fix_state_permissions() {
	local state_dir data_dir ext_dir archive_dir config_file agent_dir
	state_dir="$(oc_perm_state_dir "${1:-}")"
	data_dir="$(oc_perm_data_dir_from_state "$state_dir")"
	ext_dir="${state_dir}/extensions"
	archive_dir="${state_dir}/archived-extensions"
	config_file="${state_dir}/openclaw.json"

	[ -d "$data_dir" ] && chown openclaw:openclaw "$data_dir" 2>/dev/null || true
	[ -d "$state_dir" ] || mkdir -p "$state_dir" 2>/dev/null || true
	[ -d "$state_dir" ] && chown openclaw:openclaw "$state_dir" 2>/dev/null || true
	[ -d "$state_dir" ] && chmod 755 "$state_dir" 2>/dev/null || true

	if [ -d "$state_dir" ]; then
		find "$state_dir" -user root \
			! -path "${ext_dir}*" \
			! -path "${archive_dir}*" \
			! -path "${state_dir}/npm/projects*" \
			-exec chown openclaw:openclaw {} \; 2>/dev/null || true
	fi

	[ -f "$config_file" ] && chown openclaw:openclaw "$config_file" 2>/dev/null || true
	[ -f "${config_file}.bak" ] && chown openclaw:openclaw "${config_file}.bak" 2>/dev/null || true

	agent_dir="${state_dir}/agents/main/agent"
	if [ -d "$agent_dir" ]; then
		chown openclaw:openclaw "$agent_dir" 2>/dev/null || true
		chmod 755 "$agent_dir" 2>/dev/null || true
	fi

	if [ -d "$ext_dir" ]; then
		chown -R root:root "$ext_dir" 2>/dev/null || true
		chmod -R 755 "$ext_dir" 2>/dev/null || true
	fi
	if [ -d "$archive_dir" ]; then
		chown -R root:root "$archive_dir" 2>/dev/null || true
		chmod -R 700 "$archive_dir" 2>/dev/null || true
	fi

	oc_fix_npm_projects_permissions "$state_dir"
}

oc_prepare_openclaw_workdirs() {
	local data_dir state_dir npm_dir
	data_dir="${1:-${OC_DATA:-/opt/openclaw/data}}"
	state_dir="${data_dir}/.openclaw"
	npm_dir="${state_dir}/npm/projects"

	mkdir -p "${data_dir}/.npm" "${data_dir}/.tmp" "$npm_dir" "${state_dir}/extensions" 2>/dev/null || true
	chown -R openclaw:openclaw "${data_dir}/.npm" "${data_dir}/.tmp" 2>/dev/null || true
	chown openclaw:openclaw "$data_dir" "$state_dir" "${state_dir}/npm" "$npm_dir" 2>/dev/null || true
	chmod u+rwx,go+rx "${data_dir}/.npm" "${data_dir}/.tmp" "$state_dir" "${state_dir}/npm" "$npm_dir" 2>/dev/null || true

	# During install/upgrade, allow openclaw to update npm generations. Call
	# fix-state after the install to restore plugin roots to root:root.
	[ -d "$npm_dir" ] && chown -R openclaw:openclaw "$npm_dir" 2>/dev/null || true
}

if [ "${OPENCLAW_PERMISSIONS_SOURCED:-0}" = "1" ]; then
	return 0
fi

case "${1:-fix-state}" in
	fix-state)
		shift || true
		oc_fix_state_permissions "${1:-}"
		;;
	fix-npm-projects)
		shift || true
		oc_fix_npm_projects_permissions "${1:-}"
		;;
	prepare-workdirs)
		shift || true
		oc_prepare_openclaw_workdirs "${1:-}"
		;;
	*)
		echo "Usage: $0 {fix-state [state_dir]|fix-npm-projects [state_dir]|prepare-workdirs [data_dir]}" >&2
		exit 2
		;;
esac
