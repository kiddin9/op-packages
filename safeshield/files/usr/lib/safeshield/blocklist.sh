# shellcheck shell=ash

# Variables below are populated by sourced helpers and ss_load_config()
# shellcheck disable=SC2154

SS_HTTP_STATUS=''
SS_RESOLVE_ERROR_CODE=''
SS_ARTIFACT_DOWNLOAD_ERROR_CODE=''

ss_resolve_error_code() {
	printf '%s' "${SS_RESOLVE_ERROR_CODE:-api_resolve_failed}"
}

ss_artifact_download_error_code() {
	printf '%s' "${SS_ARTIFACT_DOWNLOAD_ERROR_CODE:-artifact_download_failed}"
}

ss_normalize_domains() {
	sed \
		-e 'y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/' \
		-e 's/\r$//' \
		-e 's/^[[:space:]]*//' \
		-e 's/[[:space:]]*$//' \
		-e '/^$/d' \
		-e '/^!/d' \
		-e '/^#/d' \
		-e 's/^0\.0\.0\.0[[:space:]][[:space:]]*//' \
		-e 's/^127\.0\.0\.1[[:space:]][[:space:]]*//' \
		-e 's#^local=/##' \
		-e 's#^address=/##' \
		-e 's#^safeshield-block=/##' \
		-e 's#/0\.0\.0\.0$##' \
		-e 's#/::$##' \
		-e 's|/#$||' \
		-e 's#/$##' \
		-e 's#^/##'
}

ss_filter_valid_domains() {
	grep -E '^[a-z0-9._-]+$'
}

ss_json_escape() {
	printf '%s' "$1" | tr -d '\r\n' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

ss_json_value() {
	printf '"%s"' "$(ss_json_escape "$1")"
}

ss_json_get_file() {
	local file="$1"
	local expr="$2"

	jsonfilter -i "$file" -e "$expr" 2>/dev/null | head -n 1
}

ss_detect_device_model() {
	local value

	[ -n "$ss_device_model" ] && {
		printf '%s' "$ss_device_model"
		return 0
	}

	value="$(ubus call system board 2>/dev/null | jsonfilter -e '@.model' 2>/dev/null | head -n 1)"
	[ -n "$value" ] || value="$(cat /tmp/sysinfo/model 2>/dev/null)"
	[ -n "$value" ] || value="OpenWrt"

	printf '%s' "$value"
}

ss_detect_device_vendor() {
	local model="$1"
	local value

	[ -n "$ss_device_vendor" ] && {
		printf '%s' "$ss_device_vendor"
		return 0
	}

	value="$(printf '%s\n' "$model" | awk '{print $1}')"
	[ -n "$value" ] || value="OpenWrt"

	printf '%s' "$value"
}

ss_detect_device_arch() {
	local value

	[ -n "$ss_device_arch" ] && {
		printf '%s' "$ss_device_arch"
		return 0
	}

	if [ -r /etc/openwrt_release ]; then
		# shellcheck disable=SC1091
		. /etc/openwrt_release
		value="${DISTRIB_ARCH:-}"
	fi

	[ -n "$value" ] || value="$(uname -m 2>/dev/null)"
	[ -n "$value" ] || value="unknown"

	printf '%s' "$value"
}

ss_detect_device_memory_mb() {
	local value

	[ -n "$ss_device_memory_mb" ] && {
		printf '%s' "$ss_device_memory_mb"
		return 0
	}

	value="$(awk '/MemTotal:/ { printf "%d", ($2 + 1023) / 1024 }' /proc/meminfo 2>/dev/null)"
	[ -n "$value" ] || value="0"

	printf '%s' "$value"
}

ss_config_fill_if_empty() {
	local option="$1"
	local value="$2"
	local current=""

	[ -n "$option" ] || return 1
	[ -n "$value" ] || return 1

	current="$(uci -q get "safeshield.config.${option}" 2>/dev/null || true)"
	[ -n "$current" ] && return 1

	uci -q set "safeshield.config.${option}=${value}" || return 1
	return 0
}

ss_sync_detected_device_config() {
	local model vendor arch memory changed=0

	model="$(ss_detect_device_model)"
	vendor="$(ss_detect_device_vendor "$model")"
	arch="$(ss_detect_device_arch)"
	memory="$(ss_detect_device_memory_mb)"

	is_valid_integer "$memory" || memory=""

	ss_config_fill_if_empty device_vendor "$vendor" && changed=1
	ss_config_fill_if_empty device_model "$model" && changed=1
	ss_config_fill_if_empty device_arch "$arch" && changed=1
	ss_config_fill_if_empty device_memory_mb "$memory" && changed=1

	if [ "$changed" -eq 1 ]; then
		uci -q commit safeshield || return 1
		log_info "Detected device metadata saved to UCI config"
	fi

	return 0
}

ss_get_or_create_physical_fingerprint() {
	local model="$1"
	local arch="$2"

	ss_identity_ensure "$model" "$arch" || return 1
	printf '%s' "$SS_PHYSICAL_FINGERPRINT"
}

ss_read_installed_version() {
	local version_file="${SS_VERSION_FILE:-/usr/lib/safeshield/version}"
	local version=""

	if [ -r "$version_file" ]; then
		version="$(head -n 1 "$version_file" 2>/dev/null | tr -d '\r\n')"
	fi

	[ -n "$version" ] || version='unknown'
	printf '%s' "$version"
}

ss_write_resolve_payload() {
	local out="$1"
	local model vendor arch memory physical_fingerprint safeshield_version

	model="$(ss_detect_device_model)"
	vendor="$(ss_detect_device_vendor "$model")"
	arch="$(ss_detect_device_arch)"
	memory="$(ss_detect_device_memory_mb)"
	physical_fingerprint="$(ss_get_or_create_physical_fingerprint "$model" "$arch")" || return 1
	safeshield_version="$(ss_read_installed_version)"

	is_valid_integer "$memory" || memory="0"

	ss_status_set physical_fingerprint "$SS_PHYSICAL_FINGERPRINT"
	ss_status_set fingerprint_version "$SS_FINGERPRINT_VERSION"
	ss_status_set identity_provider "$SS_IDENTITY_PROVIDER"
	ss_status_set identity_source "$SS_IDENTITY_SOURCE"
	ss_status_set identity_strength "$SS_IDENTITY_STRENGTH"
	ss_status_set identity_profile "$SS_IDENTITY_PROFILE"
	ss_status_set device_code "$SS_DEVICE_CODE"
	ss_status_set device_code_source "$SS_DEVICE_CODE_SOURCE"
	ss_status_set installation_id "$SS_INSTALLATION_ID"

	cat >"$out" <<__SAFESHIELD_JSON__
{
  "license_key": $(ss_json_value "$ss_license_key"),
  "device": {
    "physical_fingerprint": $(ss_json_value "$physical_fingerprint"),
    "fingerprint_version": ${SS_FINGERPRINT_VERSION:-1},
    "identity_provider": $(ss_json_value "$SS_IDENTITY_PROVIDER"),
    "identity_source": $(ss_json_value "$SS_IDENTITY_SOURCE"),
    "identity_strength": $(ss_json_value "$SS_IDENTITY_STRENGTH"),
    "identity_profile": $(ss_json_value "$SS_IDENTITY_PROFILE"),
    "device_code": $(ss_json_value "$SS_DEVICE_CODE"),
    "device_code_source": $(ss_json_value "$SS_DEVICE_CODE_SOURCE"),
    "installation_id": $(ss_json_value "$SS_INSTALLATION_ID"),
    "vendor": $(ss_json_value "$vendor"),
    "model": $(ss_json_value "$model"),
    "arch": $(ss_json_value "$arch"),
    "memory_mb": ${memory},
    "safeshield_version": $(ss_json_value "$safeshield_version")
  }
}
__SAFESHIELD_JSON__
}

ss_uclient_supports() {
	uclient-fetch --help 2>&1 | grep -q -- "$1"
}

ss_http_status_from_uclient_log() {
	local log_file="$1"

	sed -n 's/^HTTP error \([0-9][0-9][0-9]\)$/\1/p' "$log_file" | tail -n 1
}

ss_http_finish_uclient_request() {
	local log_file="$1"
	local rc="$2"

	SS_HTTP_STATUS="$(ss_http_status_from_uclient_log "$log_file")"
	if [ -s "$log_file" ]; then
		cat "$log_file" >&2
	fi
	rm -f "$log_file"

	return "$rc"
}

ss_http_post_json() {
	local url="$1"
	local payload="$2"
	local out="$3"
	local authorization="${4:-}"
	local data rc log_file

	SS_HTTP_STATUS=''

	if command_exists curl; then
		if [ -n "$authorization" ]; then
			SS_HTTP_STATUS="$(curl -sS \
				--connect-timeout "$ss_download_timeout" \
				--max-time "$ss_download_timeout" \
				-H 'Content-Type: application/json' \
				-H 'Accept: application/json' \
				-H "Authorization: ${authorization}" \
				--data-binary "@${payload}" \
				-o "$out" \
				-w '%{http_code}' \
				"$url")" || return $?
		else
			SS_HTTP_STATUS="$(curl -sS \
				--connect-timeout "$ss_download_timeout" \
				--max-time "$ss_download_timeout" \
				-H 'Content-Type: application/json' \
				-H 'Accept: application/json' \
				--data-binary "@${payload}" \
				-o "$out" \
				-w '%{http_code}' \
				"$url")" || return $?
		fi

		case "$SS_HTTP_STATUS" in
			2[0-9][0-9])
				return 0
				;;
			*)
				return 1
				;;
		esac
	fi

	command_exists uclient-fetch || return 1
	log_file="${out}.uclient.txt"
	rm -f "$log_file"

	if ss_uclient_supports '--post-file' && ss_uclient_supports '--header'; then
		if [ -n "$authorization" ]; then
			if uclient-fetch "$url" -O "$out" --timeout="${ss_download_timeout}" \
				--header='Content-Type: application/json' \
				--header='Accept: application/json' \
				--header="Authorization: ${authorization}" \
				--post-file="$payload" 2>"$log_file"; then
				rc=0
			else
				rc=$?
			fi
		else
			if uclient-fetch "$url" -O "$out" --timeout="${ss_download_timeout}" \
				--header='Content-Type: application/json' \
				--header='Accept: application/json' \
				--post-file="$payload" 2>"$log_file"; then
				rc=0
			else
				rc=$?
			fi
		fi
		ss_http_finish_uclient_request "$log_file" "$rc"
		return $?
	fi

	# Authenticated requests require explicit header support. Falling back to a
	# headerless uclient request would leak a statistics payload without proving
	# device identity and can only result in a 401 response.
	[ -z "$authorization" ] || {
		rm -f "$log_file"
		return 1
	}

	if ss_uclient_supports '--post-file'; then
		if uclient-fetch "$url" -O "$out" --timeout="${ss_download_timeout}" --post-file="$payload" 2>"$log_file"; then
			rc=0
		else
			rc=$?
		fi
		ss_http_finish_uclient_request "$log_file" "$rc"
		return $?
	fi

	if ss_uclient_supports '--post-data'; then
		data="$(cat "$payload")"
		if ss_uclient_supports '--header'; then
			if uclient-fetch "$url" -O "$out" --timeout="${ss_download_timeout}" \
				--header='Content-Type: application/json' \
				--header='Accept: application/json' \
				--post-data="$data" 2>"$log_file"; then
				rc=0
			else
				rc=$?
			fi
		else
			if uclient-fetch "$url" -O "$out" --timeout="${ss_download_timeout}" --post-data="$data" 2>"$log_file"; then
				rc=0
			else
				rc=$?
			fi
		fi
		ss_http_finish_uclient_request "$log_file" "$rc"
		return $?
	fi

	rm -f "$log_file"
	return 1
}

ss_http_get_file() {
	local url="$1"
	local out="$2"
	local rc log_file

	SS_HTTP_STATUS=''

	if command_exists curl; then
		SS_HTTP_STATUS="$(curl -LSs \
			--connect-timeout "$ss_download_timeout" \
			--max-time "$ss_download_timeout" \
			-o "$out" \
			-w '%{http_code}' \
			"$url")" || return $?

		case "$SS_HTTP_STATUS" in
			2[0-9][0-9])
				return 0
				;;
			*)
				return 1
				;;
		esac
	fi

	command_exists uclient-fetch || return 1
	log_file="${out}.uclient.txt"
	rm -f "$log_file"
	if uclient-fetch "$url" -O "$out" --timeout="${ss_download_timeout}" 2>"$log_file"; then
		rc=0
	else
		rc=$?
	fi
	ss_http_finish_uclient_request "$log_file" "$rc"
}

ss_artifact_source_action() {
	local action

	action="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
	case "$action" in
		block | allow)
			printf '%s' "$action"
			return 0
			;;
	esac

	return 1
}

ss_artifact_source_id() {
	local id="$1"
	local fallback="$2"

	id="$(printf '%s' "$id" | tr -c 'A-Za-z0-9._-' '_')"
	[ -n "$id" ] || id="$fallback"
	printf '%s' "$id"
}

ss_resolve_artifact_sources() {
	local response="$1"
	local index=0
	local max_sources="${SS_MAX_ARTIFACT_SOURCES:-16}"
	local source_count=0
	local block_count=0
	local allow_count=0
	local source_id action url sha256
	local legacy_url legacy_sha256

	: >"${SS_RESOLVED_SOURCES}" || return 1

	while [ "$index" -lt "$max_sources" ]; do
		url="$(ss_json_get_file "$response" "@.artifact.sources[${index}].download_url")"
		[ -n "$url" ] || break

		action="$(ss_json_get_file "$response" "@.artifact.sources[${index}].action")"
		[ -n "$action" ] || action='block'
		action="$(ss_artifact_source_action "$action")" || {
			log_error "Hub API artifact source ${index} has unsupported action"
			ss_status_add_error "api_response_invalid_artifact_action"
			return 1
		}

		source_id="$(ss_json_get_file "$response" "@.artifact.sources[${index}].id")"
		source_id="$(ss_artifact_source_id "$source_id" "source-${index}")"
		sha256="$(ss_json_get_file "$response" "@.artifact.sources[${index}].sha256")"

		printf '%s|%s|%s|%s|%s\n' \
			"$index" "$action" "$source_id" "$url" "$sha256" >>"${SS_RESOLVED_SOURCES}" || return 1

		source_count=$((source_count + 1))
		case "$action" in
			block) block_count=$((block_count + 1)) ;;
			allow) allow_count=$((allow_count + 1)) ;;
		esac
		index=$((index + 1))
	done

	if [ "$source_count" -eq "$max_sources" ] && [ -n "$(ss_json_get_file "$response" "@.artifact.sources[${max_sources}].download_url")" ]; then
		log_error "Hub API returned more than ${max_sources} artifact sources"
		ss_status_add_error "api_response_too_many_artifact_sources"
		return 1
	fi

	if [ "$source_count" -eq 0 ]; then
		legacy_url="$(ss_json_get_file "$response" '@.artifact.download_url')"
		legacy_sha256="$(ss_json_get_file "$response" '@.artifact.sha256')"

		if [ -z "$legacy_url" ]; then
			log_error "Hub API response did not include artifact.download_url or artifact.sources"
			ss_status_add_error "api_response_missing_download_url"
			return 1
		fi

		printf '0|block|legacy|%s|%s\n' "$legacy_url" "$legacy_sha256" >"${SS_RESOLVED_SOURCES}" || return 1
		source_count=1
		block_count=1
	fi

	if [ "$block_count" -eq 0 ]; then
		log_error "Hub API response did not include a block artifact source"
		ss_status_add_error "api_response_missing_block_source"
		return 1
	fi

	ss_status_set artifact_source_count "$source_count"
	ss_status_set artifact_block_source_count "$block_count"
	ss_status_set artifact_allow_source_count "$allow_count"
	return 0
}

ss_resolve_artifact() {
	local url response payload retries ok statistics_entitlement_rc

	SS_RESOLVE_ERROR_CODE='api_resolve_failed'
	url='https://www.smartsafehub.com/api/v1/licenses/resolve'
	payload="$SS_API_PAYLOAD"
	response="$SS_API_RESPONSE"

	ss_status_set artifact_download_url_present "0"

	if [ -z "$ss_license_key" ]; then
		log_info "license_key is empty; resolving SafeShield artifact as unlicensed/free device"
		ss_status_set license_plan "free"
		ss_status_set license_status "unlicensed"
	fi

	ss_write_resolve_payload "$payload" || return 1

	retries=1
	ok=0
	while [ "$retries" -le "$ss_download_retry" ]; do
		ss_should_stop && return 130
		log_info "Resolving SafeShield artifact via Hub API (try ${retries}/${ss_download_retry})"

		if ss_http_post_json "$url" "$payload" "$response" && [ -s "$response" ]; then
			ok=1
			break
		fi

		if [ "$SS_HTTP_STATUS" = "426" ]; then
			log_error "Hub API requires a newer SafeShield version (HTTP 426)"
			SS_RESOLVE_ERROR_CODE='safeshield_upgrade_required'
			ss_status_set health_api_resolve "0"
			return 1
		fi

		ss_should_stop && return 130
		retries=$((retries + 1))
		sleep 1
	done

	if [ "$ok" != "1" ]; then
		log_error "Hub API resolve failed"
		ss_status_set health_api_resolve "0"
		ss_status_add_error "api_resolve_failed"
		return 1
	fi

	ss_resolved_artifact_sha256="$(ss_json_get_file "$response" '@.artifact.sha256')"
	ss_resolved_artifact_tier="$(ss_json_get_file "$response" '@.artifact.tier')"
	ss_resolved_artifact_version="$(ss_json_get_file "$response" '@.artifact.version')"
	ss_resolved_artifact_unique_domains="$(ss_json_get_file "$response" '@.artifact.unique_domains')"
	ss_resolved_artifact_rules="$(ss_json_get_file "$response" '@.artifact.rules')"
	ss_resolved_license_plan="$(ss_json_get_file "$response" '@.license.plan')"
	ss_resolved_license_status="$(ss_json_get_file "$response" '@.license.status')"
	ss_resolved_device_profile="$(ss_json_get_file "$response" '@.device.profile')"

	if command -v ss_statistics_sync_upload_entitlement >/dev/null 2>&1; then
		statistics_entitlement_rc=0
		ss_statistics_sync_upload_entitlement "$response" || statistics_entitlement_rc=$?
		case "$statistics_entitlement_rc" in
			0) ;;
			2) log_info "Cloud statistics upload is not enabled for the current license" ;;
			*) log_warn "Hub API response did not include usable statistics upload credentials" ;;
		esac
	fi

	ss_resolve_artifact_sources "$response" || {
		ss_status_set health_api_resolve "0"
		return 1
	}

	ss_status_set health_api_resolve "1"
	ss_status_set artifact_download_url_present "1"
	ss_status_set artifact_sha256 "$ss_resolved_artifact_sha256"
	ss_status_set artifact_tier "$ss_resolved_artifact_tier"
	ss_status_set artifact_version "$ss_resolved_artifact_version"
	ss_status_set artifact_unique_domains "${ss_resolved_artifact_unique_domains:-0}"
	ss_status_set artifact_rules "${ss_resolved_artifact_rules:-0}"
	ss_status_set license_plan "${ss_resolved_license_plan:-free}"
	ss_status_set license_status "${ss_resolved_license_status:-unlicensed}"
	ss_status_set device_profile "$ss_resolved_device_profile"
	SS_RESOLVE_ERROR_CODE=''

	log_ok "Resolved ${ss_resolved_artifact_tier:-unknown}/${ss_resolved_artifact_version:-unknown} artifact sources for plan ${ss_resolved_license_plan:-free}"
}

ss_verify_artifact_sha256() {
	local file="$1"
	local expected="$2"
	local actual

	case "$expected" in
		'' | '...')
			return 0
			;;
	esac

	command_exists sha256sum || {
		log_error "sha256sum not found; artifact checksum verification cannot continue"
		ss_status_set health_artifact_sha256 "0"
		ss_status_add_error "sha256sum_not_found"
		return 1
	}

	actual="$(sha256sum "$file" 2>/dev/null | awk '{print $1}')"
	if [ "$actual" != "$expected" ]; then
		log_error "Artifact sha256 mismatch"
		ss_status_set health_artifact_sha256 "0"
		ss_status_add_error "artifact_sha256_mismatch"
		return 1
	fi

	return 0
}

ss_clear_cached_api_sources() {
	rm -f \
		"${SS_TMP_DIR}"/api.*.block.txt \
		"${SS_TMP_DIR}"/api.*.allow.txt \
		"${SS_ARTIFACT_CACHE_STATE}" \
		"${SS_ARTIFACT_CACHE_STATE}.tmp."* \
		2>/dev/null
}

ss_cached_api_sources_available() {
	local index action
	local expected=0
	local actual=0

	[ -s "${SS_ARTIFACT_CACHE_STATE}" ] || return 1

	while IFS='|' read -r index action _; do
		[ -n "$index" ] || continue
		expected=$((expected + 1))
		[ -f "${SS_TMP_DIR}/api.${index}.${action}.txt" ] || return 1
		actual=$((actual + 1))
	done <"${SS_ARTIFACT_CACHE_STATE}"

	[ "$expected" -gt 0 ] && [ "$actual" -eq "$expected" ]
}

ss_download_api_artifacts() {
	local index action source_id source_url source_sha256
	local output normalized raw_size_kb line_count retries ok
	local downloaded=0
	local checksum_count=0
	local cache_state_tmp="${SS_ARTIFACT_CACHE_STATE}.tmp.$$"

	SS_ARTIFACT_DOWNLOAD_ERROR_CODE='artifact_download_failed'

	[ -s "${SS_RESOLVED_SOURCES}" ] || {
		log_error "Resolved artifact source list is unavailable"
		ss_status_set health_artifact_download "0"
		ss_status_add_error "artifact_sources_unavailable"
		return 1
	}

	ss_clear_cached_api_sources
	: >"$cache_state_tmp" || return 1

	while IFS='|' read -r index action source_id source_url source_sha256; do
		[ -n "$source_url" ] || continue

		ss_should_stop && {
			rm -f "$cache_state_tmp"
			ss_clear_cached_api_sources
			return 130
		}

		output="${SS_TMP_DIR}/artifact.${index}.${action}.raw"
		normalized="${SS_TMP_DIR}/api.${index}.${action}.txt"
		retries=1
		ok=0

		while [ "$retries" -le "$ss_download_retry" ]; do
			ss_should_stop && {
				rm -f "$output" "$cache_state_tmp"
				ss_clear_cached_api_sources
				return 130
			}

			log_info "Downloading artifact source ${source_id} (${action}, try ${retries}/${ss_download_retry})"

			if ss_http_get_file "$source_url" "$output" && [ -s "$output" ]; then
				ok=1
				break
			fi

			if [ "$SS_HTTP_STATUS" = "426" ]; then
				log_error "Artifact download requires a newer SafeShield version (HTTP 426)"
				SS_ARTIFACT_DOWNLOAD_ERROR_CODE='safeshield_upgrade_required'
				ss_status_set health_artifact_download "0"
				rm -f "$output" "$cache_state_tmp"
				ss_clear_cached_api_sources
				return 1
			fi

			retries=$((retries + 1))
			sleep 1
		done

		if [ "$ok" != "1" ]; then
			log_error "Artifact source ${source_id} download failed"
			ss_status_set health_artifact_download "0"
			ss_status_add_error "artifact_download_failed"
			rm -f "$output" "$cache_state_tmp"
			ss_clear_cached_api_sources
			return 1
		fi

		raw_size_kb="$(du -k "$output" 2>/dev/null | awk '{print $1}')"
		[ -n "$raw_size_kb" ] || raw_size_kb=0

		if [ "$raw_size_kb" -gt "$ss_max_blocklist_file_size_kb" ]; then
			log_error "Artifact source ${source_id} is too large (${raw_size_kb} KB > ${ss_max_blocklist_file_size_kb} KB)"
			ss_status_set health_artifact_download "0"
			ss_status_add_error "artifact_too_large"
			rm -f "$output" "$cache_state_tmp"
			ss_clear_cached_api_sources
			return 1
		fi

		case "$source_sha256" in
			'' | '...') ;;
			*) checksum_count=$((checksum_count + 1)) ;;
		esac

		ss_verify_artifact_sha256 "$output" "$source_sha256" || {
			log_error "Artifact source ${source_id} checksum verification failed"
			rm -f "$output" "$cache_state_tmp"
			ss_clear_cached_api_sources
			return 1
		}

		ss_normalize_domains <"$output" |
			ss_filter_valid_domains |
			sort -u >"$normalized" || {
			rm -f "$output" "$normalized" "$cache_state_tmp"
			ss_clear_cached_api_sources
			return 1
		}
		rm -f "$output"

		line_count="$(grep -c . "$normalized" 2>/dev/null)"
		[ -n "$line_count" ] || line_count=0
		printf '%s|%s|%s\n' "$index" "$action" "$source_id" >>"$cache_state_tmp" || {
			rm -f "$normalized" "$cache_state_tmp"
			ss_clear_cached_api_sources
			return 1
		}

		downloaded=$((downloaded + 1))
		log_ok "Downloaded artifact source ${source_id} (${action}, ${line_count} unique domains, ${raw_size_kb} KB raw)"
	done <"${SS_RESOLVED_SOURCES}"

	if [ "$downloaded" -eq 0 ]; then
		log_error "No artifact sources were downloaded"
		ss_status_set health_artifact_download "0"
		ss_status_add_error "artifact_download_failed"
		rm -f "$cache_state_tmp"
		ss_clear_cached_api_sources
		return 1
	fi

	mv -f "$cache_state_tmp" "${SS_ARTIFACT_CACHE_STATE}" || {
		rm -f "$cache_state_tmp"
		ss_clear_cached_api_sources
		return 1
	}

	if [ "$checksum_count" -eq "$downloaded" ]; then
		ss_status_set health_artifact_sha256 "1"
	elif [ "$checksum_count" -eq 0 ]; then
		ss_status_set health_artifact_sha256 ""
	else
		ss_status_set health_artifact_sha256 ""
		ss_status_add_warning "artifact_sha256_partial"
	fi
	ss_status_set health_artifact_download "1"
	SS_ARTIFACT_DOWNLOAD_ERROR_CODE=''
	log_ok "Downloaded ${downloaded} SafeShield artifact source(s)"
}

ss_build_local_allowlist() {
	local out="${SS_TMP_DIR}/local.allow.txt"

	: >"$out"

	if [ -f "${SS_LOCAL_ALLOWLIST_FILE}" ]; then
		ss_normalize_domains <"${SS_LOCAL_ALLOWLIST_FILE}" |
			ss_filter_valid_domains |
			sort -u >>"$out"
	fi
}

ss_build_local_blocklist() {
	local out="${SS_TMP_DIR}/local.block.txt"

	: >"$out"

	if [ -f "${SS_LOCAL_BLOCKLIST_FILE}" ]; then
		ss_normalize_domains <"${SS_LOCAL_BLOCKLIST_FILE}" |
			ss_filter_valid_domains |
			sort -u >>"$out"
	fi
}

ss_filter_domains_shadowed_by_ancestors() {
	local shadow_file="$1"
	local input_file="$2"
	local output_file="$3"

	[ -f "$input_file" ] || {
		: >"$output_file"
		return 0
	}

	if [ ! -s "$shadow_file" ]; then
		cp "$input_file" "$output_file"
		return $?
	fi

	awk '
        FNR == NR {
            shadow[$0] = 1
            next
        }

        /^[a-z0-9._-]+$/ {
            if (shadow[$0]) {
                next
            }

            n = split($0, arr, ".")
            cur = arr[n]

            for (i = n - 1; i >= 1; i--) {
                cur = arr[i] "." cur
                if (shadow[cur]) {
                    next
                }
            }

            print
        }
    ' "$shadow_file" "$input_file" >"$output_file"
}

ss_merge_sorted_api_sources() {
	local action="$1"
	local out="$2"
	local f

	set --
	for f in "${SS_TMP_DIR}"/api.*."${action}".txt; do
		[ -f "$f" ] || continue
		set -- "$@" "$f"
	done

	if [ "$#" -eq 0 ]; then
		: >"$out"
		return 0
	fi

	# Every API shard is normalized with sort -u when downloaded, so merge the
	# already-sorted streams instead of sorting their combined contents again.
	sort -m -u "$@" >"$out"
}

ss_merge_lists() {
	local final
	local api_blocks="${SS_TMP_DIR}/api-blocks.domains"
	local api_allows="${SS_TMP_DIR}/api-allows.domains"
	local local_blocks="${SS_TMP_DIR}/local.block.txt"
	local local_allows="${SS_TMP_DIR}/local.allow.txt"
	local effective_local_blocks="${SS_TMP_DIR}/effective-local-blocks.domains"
	local effective_api_allows="${SS_TMP_DIR}/effective-api-allows.domains"
	local effective_allows="${SS_TMP_DIR}/effective-allows.domains"
	local effective_api_blocks="${SS_TMP_DIR}/effective-api-blocks.domains"
	local final_blocks="${SS_TMP_DIR}/final-blocks.domains"
	local final_size_kb
	local valid_count

	final="$(ss_blocklist_tmp_path)" || return 1
	: >"$final" || return 1
	: >"$api_blocks" || return 1
	: >"$api_allows" || return 1

	ss_merge_sorted_api_sources block "$api_blocks" || {
		rm -f "$final"
		return 1
	}

	ss_merge_sorted_api_sources allow "$api_allows" || {
		rm -f "$final"
		return 1
	}

	ss_should_stop && {
		rm -f "$final"
		return 130
	}

	# Precedence is intentionally explicit:
	# local allow > local block > Hub allow > Hub block.
	# A more-specific dnsmasq server/address rule handles descendant exceptions;
	# ancestor/equal conflicts are removed here before the final config is built.
	ss_filter_domains_shadowed_by_ancestors "$local_allows" "$local_blocks" "$effective_local_blocks" || {
		rm -f "$final"
		return 1
	}
	ss_filter_domains_shadowed_by_ancestors "$effective_local_blocks" "$api_allows" "$effective_api_allows" || {
		rm -f "$final"
		return 1
	}
	{
		[ -f "$local_allows" ] && cat "$local_allows"
		[ -f "$effective_api_allows" ] && cat "$effective_api_allows"
	} | sort -u >"$effective_allows" || {
		rm -f "$final"
		return 1
	}
	ss_filter_domains_shadowed_by_ancestors "$effective_allows" "$api_blocks" "$effective_api_blocks" || {
		rm -f "$final"
		return 1
	}
	{
		[ -f "$effective_local_blocks" ] && cat "$effective_local_blocks"
		[ -f "$effective_api_blocks" ] && cat "$effective_api_blocks"
	} | sort -u >"$final_blocks" || {
		rm -f "$final"
		return 1
	}

	ss_should_stop && {
		rm -f "$final"
		return 130
	}

	if [ -s "$final_blocks" ]; then
		if ss_dnsmasq_safeshield_block_supported; then
			awk '{ print "safeshield-block=/" $0 "/" }' "$final_blocks" >"$final" || {
				rm -f "$final"
				return 1
			}
		else
			# Stock dnsmasq does not understand the SafeShield extension. Preserve
			# protection with the standard address rule and leave statistics off.
			awk '{ print "address=/" $0 "/#" }' "$final_blocks" >"$final" || {
				rm -f "$final"
				return 1
			}
		fi
	fi

	if [ -s "$effective_allows" ]; then
		awk '{ print "server=/" $0 "/#" }' "$effective_allows" >>"$final" || {
			rm -f "$final"
			return 1
		}
	fi

	ss_should_stop && {
		rm -f "$final"
		return 130
	}

	valid_count="$(grep -c . "$final" 2>/dev/null)"
	[ -n "$valid_count" ] || valid_count=0
	ss_valid_line_count="$valid_count"
	ss_status_set valid_line_count "$ss_valid_line_count"
	log_info "Final valid line count: ${ss_valid_line_count}"

	if [ "$ss_valid_line_count" -lt "$ss_min_valid_line_count" ]; then
		ss_status_set health_min_valid_line_count "0"
		log_error "valid line count below minimum: ${ss_valid_line_count} < ${ss_min_valid_line_count}"
		ss_status_add_error "valid_line_count_below_minimum"
		rm -f "$final"
		return 1
	fi
	ss_status_set health_min_valid_line_count "1"

	final_size_kb="$(du -k "$final" 2>/dev/null | awk '{print $1}')"
	[ -n "$final_size_kb" ] || final_size_kb=0
	ss_status_set blocklist_file_size_kb "$final_size_kb"

	if [ "$final_size_kb" -gt "$ss_max_blocklist_file_size_kb" ]; then
		ss_status_set health_max_file_size "0"
		log_error "final blocklist too large (${final_size_kb} KB > ${ss_max_blocklist_file_size_kb} KB)"
		ss_status_add_error "blocklist_too_large"
		rm -f "$final"
		return 1
	fi
	ss_status_set health_max_file_size "1"

	if [ "${ss_dnsmasq_sanity_check}" = "1" ]; then
		if ! dnsmasq --test --conf-file="$final" >/dev/null 2>&1; then
			log_error "dnsmasq --test failed"
			ss_status_add_error "dnsmasq_test_failed"
			rm -f "$final"
			return 1
		fi
	fi

	ss_should_stop && {
		rm -f "$final"
		return 130
	}

	ss_install_blocklist_atomic "$final" "${SS_BLOCKLIST_FILE}" || {
		rm -f "$final"
		return 1
	}

	ss_status_set blocklist_installed "1"
}

ss_reconcile_blocklist_file_for_dnsmasq() {
	local path="$1"
	local tmp="${path}.safeshield.$$"

	[ -f "$path" ] || return 0

	if ss_dnsmasq_safeshield_block_supported; then
		grep -Eq '^address=/[^/]+/(#|0\.0\.0\.0|::)$' "$path" || return 0

		awk -F'/' '
            $1 == "address=" && ($3 == "#" || $3 == "0.0.0.0" || $3 == "::") {
                print "safeshield-block=/" $2 "/"
                next
            }
            { print }
        ' "$path" >"$tmp" || {
			rm -f "$tmp"
			return 1
		}
	else
		grep -Eq '^safeshield-block=/[^/]+/$' "$path" || return 0

		awk -F'/' '
            $1 == "safeshield-block=" && $3 == "" {
                print "address=/" $2 "/#"
                next
            }
            { print }
        ' "$path" >"$tmp" || {
			rm -f "$tmp"
			return 1
		}
	fi

	mv -f "$tmp" "$path" || {
		rm -f "$tmp"
		return 1
	}
	return 0
}

ss_reconcile_installed_blocklists_for_dnsmasq() {
	ss_reconcile_blocklist_file_for_dnsmasq "${SS_BLOCKLIST_FILE}" || return 1
	ss_reconcile_blocklist_file_for_dnsmasq "${SS_INACTIVE_BLOCKLIST_FILE}" || return 1
}

ss_install_blocklist() {
	if [ "${ss_compress_blocklist}" = "1" ]; then
		log_warn "compress_blocklist=1 is not implemented in this revision, using uncompressed blocklist"
		ss_status_add_warning "compress_blocklist_not_implemented"
	fi

	[ -f "${SS_BLOCKLIST_FILE}" ] || return 1
}

find_test_domains() {
	local limit="${1:-5}"

	[ -f "${SS_BLOCKLIST_FILE}" ] || return 1
	[ "$limit" -gt 0 ] 2>/dev/null || return 0

	awk -F'/' -v limit="$limit" '
        ($1 == "safeshield-block=" && $3 == "") ||
        ($1 == "address=" && ($3 == "#" || $3 == "0.0.0.0" || $3 == "::")) {
            if (!seen[$2]++) {
                print $2
                found++
                if (found >= limit) {
                    exit
                }
            }
        }
    ' "${SS_BLOCKLIST_FILE}"
}

check_blocklist_rule_present() {
	local domain="$1"

	[ -n "$domain" ] || return 1
	[ -f "${SS_BLOCKLIST_FILE}" ] || return 1

	awk -F'/' -v d="$domain" '
        (($1 == "safeshield-block=" && $3 == "") ||
         ($1 == "address=" && ($3 == "#" || $3 == "0.0.0.0" || $3 == "::"))) && $2 == d {
            found = 1
            exit
        }
        END {
            exit(found ? 0 : 1)
        }
    ' "${SS_BLOCKLIST_FILE}"
}

check_domain_blocked() {
	local domain="$1"

	[ -n "$domain" ] || return 1

	nslookup "$domain" 127.0.0.1 2>&1 |
		grep -Eq '(^Address: *(0\.0\.0\.0|::)$|NXDOMAIN)'
}

check_blocklist_applied_for_domain() {
	local domain="$1"

	local rule_already_sampled="${2:-0}"

	if [ "$rule_already_sampled" != "1" ]; then
		check_blocklist_rule_present "$domain" || return 1
	fi
	check_domain_blocked "$domain" || return 1
}

check_blocklist_applied_multi_with_stats() {
	local limit="${1:-5}"
	local min_success="${2:-2}"
	local domain
	local tested=0
	local success=0
	local first_domain=""
	local domains=""

	while read -r domain; do
		[ -n "$domain" ] || continue

		ss_should_stop && return 130

		tested=$((tested + 1))

		if [ -z "$first_domain" ]; then
			first_domain="$domain"
		fi

		if [ -n "$domains" ]; then
			domains="${domains},${domain}"
		else
			domains="$domain"
		fi

		if check_blocklist_applied_for_domain "$domain" 1; then
			success=$((success + 1))
		fi
	done <<EOF
$(find_test_domains "$limit")
EOF

	ss_status_set blocklist_test_domain_sample_count "$tested"
	ss_status_set blocklist_test_domain_success_count "$success"
	ss_status_set blocklist_test_domains "$domains"

	if [ -n "$first_domain" ]; then
		ss_status_set blocklist_test_domain "$first_domain"
	fi

	[ "$tested" -gt 0 ] || return 1
	[ "$success" -ge "$min_success" ]
}
