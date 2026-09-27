# shellcheck shell=ash

# Paths are defined by core.sh before these helpers are called.
# shellcheck disable=SC2154

SS_STATISTICS_POLL_COMMAND="${SS_STATISTICS_POLL_COMMAND:-/usr/libexec/safeshield-stats-poll}"
SS_STATISTICS_REBASELINE_FILE="${SS_STATISTICS_REBASELINE_FILE:-${SS_STATISTICS_DIR:-/tmp/safeshield/statistics}/rebaseline}"

ss_statistics_profile_code() {
	local board=""
	local profile=""

	if command -v ss_identity_board_name >/dev/null 2>&1 && command -v ss_identity_profile_code >/dev/null 2>&1; then
		board="$(ss_identity_board_name 2>/dev/null || true)"
		if [ -n "$board" ]; then
			profile="$(ss_identity_profile_code "$board" 2>/dev/null || true)"
		fi
	fi

	case "$profile" in
		'' | unknown)
			[ -n "${SS_IDENTITY_PROFILE:-}" ] && profile="${SS_IDENTITY_PROFILE}"
			;;
	esac
	[ -n "$profile" ] || profile="unknown"
	printf '%s\n' "$profile"
}

ss_statistics_effective_snapshot_interval() {
	local configured="${1:-60}"

	if [ "$configured" = "60" ] && [ "$(ss_statistics_profile_code)" = "gl_mt300n_v2" ]; then
		printf '%s\n' '300'
		return 0
	fi
	printf '%s\n' "$configured"
}

ss_statistics_persistence_enabled() {
	case "$(ss_statistics_profile_code)" in
		gl_mt300n_v2)
			return 1
			;;
		*)
			return 0
			;;
	esac
}

ss_statistics_cleanup_legacy_dnsmasq_logging() {
	if [ -f "${SS_STATISTICS_DNSMASQ_CONF}" ]; then
		rm -f "${SS_STATISTICS_DNSMASQ_CONF}" || return 1
		printf '%s\n' '1'
	else
		printf '%s\n' '0'
	fi
}

# Kept as an internal compatibility wrapper for the init script. Statistics no
# longer enables dnsmasq query logging; this only removes a pre-0.3.20-r2 file.
ss_statistics_configure_dnsmasq() {
	ss_statistics_cleanup_legacy_dnsmasq_logging
}

ss_statistics_source_available() {
	[ -x "$SS_STATISTICS_POLL_COMMAND" ] || return 1
	"$SS_STATISTICS_POLL_COMMAND" >/dev/null 2>&1
}

ss_statistics_request_rebaseline() {
	mkdir -p "${SS_STATISTICS_REBASELINE_FILE%/*}" || return 1
	: >"${SS_STATISTICS_REBASELINE_FILE}" || return 1
}

ss_statistics_disable_if_dnsmasq_unpatched() {
	[ "${ss_enabled}" = "1" ] || return 0
	[ "${ss_statistics_enabled}" = "1" ] || return 0
	ss_dnsmasq_safeshield_block_supported && return 0

	log_warn 'Disabling SafeShield statistics at runtime because dnsmasq does not provide the SafeShield extension'
	ss_status_set health_dnsmasq_features '0'
	ss_status_add_warning 'statistics_disabled_dnsmasq_safeshield_patch_unavailable'

	# Keep the configured preference intact. A later firmware upgrade that adds
	# the dnsmasq extension can therefore restore statistics automatically.
	ss_statistics_enabled='0'
	return 0
}

ss_statistics_add_procd_instance() {
	procd_open_instance statistics
	procd_set_param command /usr/libexec/safeshield-statsd
	procd_set_param respawn 3600 5 5
	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_set_param file /etc/config/safeshield
	procd_set_param data service safeshield-statistics
	procd_close_instance
}

ss_statistics_add_upload_procd_instance() {
	procd_open_instance statistics-upload
	procd_set_param command /usr/libexec/safeshield-statistics-uploader
	procd_set_param respawn 3600 5 5
	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_set_param file /etc/config/safeshield
	procd_set_param data service safeshield-statistics-upload
	procd_close_instance
}

ss_statistics_reconcile_runtime() {
	local legacy_dnsmasq_changed=0

	if [ "${ss_enabled}" = "1" ] && [ "${ss_statistics_enabled}" = "1" ]; then
		ss_require_supported_dnsmasq || {
			log_error "Failed dnsmasq compatibility check while enabling statistics"
			return 1
		}

		ss_statistics_disable_if_dnsmasq_unpatched || return 1
	fi

	if [ "${ss_enabled}" != "1" ] || [ "${ss_statistics_enabled}" != "1" ]; then
		procd_kill "${PKG_NAME}" statistics >/dev/null 2>&1 || true
		procd_kill "${PKG_NAME}" statistics-upload >/dev/null 2>&1 || true
		ss_statistics_request_rebaseline || {
			log_error "Failed to mark statistics for rebaseline while statistics are inactive"
			return 1
		}

		legacy_dnsmasq_changed="$(ss_statistics_cleanup_legacy_dnsmasq_logging)" || {
			log_error "Failed to remove legacy dnsmasq statistics logging"
			return 1
		}

		if [ "$legacy_dnsmasq_changed" = "1" ]; then
			dnsmasq_restart || {
				log_error "Failed to restart dnsmasq after removing legacy statistics logging"
				return 1
			}
		fi

		return 0
	fi

	legacy_dnsmasq_changed="$(ss_statistics_cleanup_legacy_dnsmasq_logging)" || {
		log_error "Failed to remove legacy dnsmasq statistics logging"
		return 1
	}

	if [ "$legacy_dnsmasq_changed" = "1" ]; then
		dnsmasq_restart || {
			log_error "Failed to restart dnsmasq after removing legacy statistics logging"
			return 1
		}
	fi

	ss_statistics_source_available || {
		log_error "dnsmasq SafeShield statistics UBus source is unavailable"
		return 1
	}

	procd_open_service "${PKG_NAME}"
	ss_statistics_add_procd_instance
	ss_statistics_add_upload_procd_instance
	procd_close_service add
}

ss_statistics_upload_credentials_path() {
	printf '%s\n' "${SS_STATISTICS_UPLOAD_CREDENTIALS_FILE:-${SS_STATISTICS_DIR:-/tmp/safeshield/statistics}/upload.credentials}"
}

ss_statistics_upload_entitlement_path() {
	printf '%s\n' "${SS_STATISTICS_UPLOAD_ENTITLEMENT_FILE:-${SS_STATISTICS_DIR:-/tmp/safeshield/statistics}/upload.entitlement}"
}

ss_statistics_set_upload_entitlement() {
	local state="$1"
	local path tmp old_umask checked_at

	case "$state" in
		allowed | denied) ;;
		unknown)
			rm -f "$(ss_statistics_upload_entitlement_path)"
			return 0
			;;
		*) return 1 ;;
	esac

	checked_at="$(date +%s 2>/dev/null || printf '0')"
	is_valid_integer "$checked_at" || checked_at=0
	path="$(ss_statistics_upload_entitlement_path)"
	tmp="${path}.tmp.$$"
	mkdir -p "${path%/*}" || return 1
	old_umask="$(umask)"
	umask 077
	printf '%s\n%s\n' "$state" "$checked_at" >"$tmp" || {
		umask "$old_umask"
		rm -f "$tmp"
		return 1
	}
	mv -f "$tmp" "$path" || {
		umask "$old_umask"
		rm -f "$tmp"
		return 1
	}
	umask "$old_umask"
}

ss_statistics_upload_entitlement() {
	local state

	state="$(sed -n '1p' "$(ss_statistics_upload_entitlement_path)" 2>/dev/null)"
	case "$state" in
		allowed | denied) printf '%s\n' "$state" ;;
		*) printf '%s\n' 'unknown' ;;
	esac
}

ss_statistics_upload_denied() {
	[ "$(ss_statistics_upload_entitlement)" = 'denied' ]
}

ss_statistics_upload_denied_recheck_due() {
	local interval_s="${1:-43200}"
	local checked_at now elapsed

	ss_statistics_upload_denied || return 1
	is_valid_integer "$interval_s" || interval_s=43200
	[ "$interval_s" -ge 60 ] 2>/dev/null || interval_s=43200

	checked_at="$(sed -n '2p' "$(ss_statistics_upload_entitlement_path)" 2>/dev/null)"
	is_valid_integer "$checked_at" || return 0
	[ "$checked_at" -gt 0 ] 2>/dev/null || return 0

	now="$(date +%s 2>/dev/null || printf '0')"
	is_valid_integer "$now" || return 0
	[ "$now" -gt 0 ] 2>/dev/null || return 0

	# A backward wall-clock correction must not postpone entitlement recovery.
	[ "$now" -lt "$checked_at" ] 2>/dev/null && return 0
	elapsed=$((now - checked_at))
	[ "$elapsed" -ge "$interval_s" ]
}

ss_statistics_clear_upload_credentials() {
	rm -f "$(ss_statistics_upload_credentials_path)"
	SS_STATISTICS_UPLOAD_URL=''
	SS_STATISTICS_UPLOAD_TOKEN=''
	SS_STATISTICS_UPLOAD_TOKEN_EXPIRES_IN_S='0'
}

ss_statistics_disable_cloud_upload() {
	ss_statistics_clear_upload_credentials
	rm -f \
		"${SS_STATISTICS_UPLOAD_PENDING_FILE:-${SS_STATISTICS_DIR:-/tmp/safeshield/statistics}/upload.pending.json}" \
		"${SS_STATISTICS_UPLOAD_PENDING_META_FILE:-${SS_STATISTICS_DIR:-/tmp/safeshield/statistics}/upload.pending.meta}" \
		"${SS_STATISTICS_UPLOAD_STATE_FILE:-${SS_STATISTICS_DIR:-/tmp/safeshield/statistics}/upload.state}"
	ss_statistics_set_upload_entitlement denied
}

ss_statistics_store_upload_credentials() {
	local response="$1"
	local path tmp url token expires_in old_umask

	[ -s "$response" ] || return 1
	url="$(ss_json_get_file "$response" '@.statistics.upload_url')"
	token="$(ss_json_get_file "$response" '@.statistics.token')"
	expires_in="$(ss_json_get_file "$response" '@.statistics.token_expires_in_s')"

	case "$url" in
		https://www.smartsafehub.com/api/v1/statistics | https://www.smartsafehub.com/api/v1/statistics/) ;;
		*)
			return 1
			;;
	esac
	[ -n "$token" ] || return 1
	[ "${#token}" -le 4096 ] 2>/dev/null || return 1
	if printf '%s' "$token" | grep -q '[[:space:]]'; then
		return 1
	fi
	is_valid_integer "$expires_in" || expires_in='0'

	path="$(ss_statistics_upload_credentials_path)"
	tmp="${path}.tmp.$$"
	mkdir -p "${path%/*}" || return 1
	old_umask="$(umask)"
	umask 077
	printf '%s\n%s\n%s\n' "$url" "$token" "$expires_in" >"$tmp" || {
		umask "$old_umask"
		rm -f "$tmp"
		return 1
	}
	chmod 600 "$tmp" 2>/dev/null || true
	mv -f "$tmp" "$path" || {
		umask "$old_umask"
		rm -f "$tmp"
		return 1
	}
	umask "$old_umask"
	ss_statistics_set_upload_entitlement allowed || true
	return 0
}

ss_statistics_sync_upload_entitlement() {
	local response="$1"
	local url token

	[ -s "$response" ] || return 1
	url="$(ss_json_get_file "$response" '@.statistics.upload_url')"
	token="$(ss_json_get_file "$response" '@.statistics.token')"

	if [ -z "$url" ] && [ -z "$token" ]; then
		ss_statistics_disable_cloud_upload || return 1
		return 2
	fi

	if [ -z "$url" ] || [ -z "$token" ]; then
		ss_statistics_clear_upload_credentials
		ss_statistics_set_upload_entitlement unknown || true
		return 1
	fi

	ss_statistics_store_upload_credentials "$response"
}

ss_statistics_load_upload_credentials() {
	local path

	path="$(ss_statistics_upload_credentials_path)"
	SS_STATISTICS_UPLOAD_URL=''
	SS_STATISTICS_UPLOAD_TOKEN=''
	SS_STATISTICS_UPLOAD_TOKEN_EXPIRES_IN_S='0'
	ss_statistics_upload_denied && {
		ss_statistics_clear_upload_credentials
		return 1
	}
	[ -s "$path" ] || return 1

	SS_STATISTICS_UPLOAD_URL="$(sed -n '1p' "$path" 2>/dev/null)"
	SS_STATISTICS_UPLOAD_TOKEN="$(sed -n '2p' "$path" 2>/dev/null)"
	SS_STATISTICS_UPLOAD_TOKEN_EXPIRES_IN_S="$(sed -n '3p' "$path" 2>/dev/null)"

	case "$SS_STATISTICS_UPLOAD_URL" in
		https://www.smartsafehub.com/api/v1/statistics | https://www.smartsafehub.com/api/v1/statistics/) ;;
		*)
			ss_statistics_clear_upload_credentials
			return 1
			;;
	esac
	[ -n "$SS_STATISTICS_UPLOAD_TOKEN" ] || {
		ss_statistics_clear_upload_credentials
		return 1
	}
	is_valid_integer "$SS_STATISTICS_UPLOAD_TOKEN_EXPIRES_IN_S" || SS_STATISTICS_UPLOAD_TOKEN_EXPIRES_IN_S='0'
	return 0
}

ss_statistics_refresh_upload_credentials() {
	local request response resolve_url retries rc=1

	resolve_url='https://www.smartsafehub.com/api/v1/licenses/resolve'
	request="${SS_STATISTICS_DIR:-/tmp/safeshield/statistics}/upload-resolve-request.json"
	response="${SS_STATISTICS_DIR:-/tmp/safeshield/statistics}/upload-resolve-response.json"

	ss_load_config || return 1
	mkdir -p "${request%/*}" || return 1
	ss_refresh_lock_open_wait "${ss_download_timeout:-10}" || return $?

	if ! ss_write_resolve_payload "$request"; then
		ss_refresh_lock_close
		return 1
	fi

	retries=1
	while [ "$retries" -le "${ss_download_retry:-3}" ]; do
		ss_should_stop && {
			rc=130
			break
		}
		if ss_http_post_json "$resolve_url" "$request" "$response" && [ -s "$response" ]; then
			rc=0
			ss_statistics_sync_upload_entitlement "$response" || rc=$?
			break
		fi
		if [ "${SS_HTTP_STATUS:-}" = '426' ]; then
			log_error 'Hub requires a newer SafeShield version before statistics can be uploaded'
			break
		fi
		retries=$((retries + 1))
		[ "$retries" -le "${ss_download_retry:-3}" ] && sleep 1
	done

	rm -f "$request" "$response" "${response}.uclient.txt"
	ss_refresh_lock_close
	return "$rc"
}
