# shellcheck shell=ash

readonly SS_MIN_DNSMASQ_VERSION='2.93'
_ss_dnsmasq_check_error=''

ss_dnsmasq_check_error() {
	printf '%s\n' "${_ss_dnsmasq_check_error}"
}

ss_dnsmasq_version() {
	dnsmasq --version 2>/dev/null | awk '
		NR == 1 && $1 == "Dnsmasq" && $2 == "version" {
			version = $3
			sub(/[^0-9.].*$/, "", version)
			print version
			exit
		}
	'
}

ss_dnsmasq_safeshield_block_supported() {
	dnsmasq --test --conf-file=/dev/null --safeshield-block=/safeshield.invalid/ >/dev/null 2>&1
}

ss_require_supported_dnsmasq() {
	local current_version

	_ss_dnsmasq_check_error=''
	ss_status_set dnsmasq_min_version "${SS_MIN_DNSMASQ_VERSION}"

	if ! check_dnsmasq_binary; then
		_ss_dnsmasq_check_error='dnsmasq_binary_not_found'
		ss_status_set dnsmasq_version ''
		ss_status_set health_dnsmasq_binary '0'
		ss_status_set health_dnsmasq_version '0'
		ss_status_set health_dnsmasq_features '0'
		log_error 'dnsmasq binary not found'
		return 1
	fi
	ss_status_set health_dnsmasq_binary '1'

	current_version="$(ss_dnsmasq_version)"
	ss_status_set dnsmasq_version "${current_version}"

	if [ -z "${current_version}" ]; then
		_ss_dnsmasq_check_error='dnsmasq_version_unknown'
		ss_status_set health_dnsmasq_version '0'
		ss_status_set health_dnsmasq_features '0'
		log_error 'Unable to determine dnsmasq version'
		return 1
	fi

	if ! is_greater_equal "${current_version}" "${SS_MIN_DNSMASQ_VERSION}"; then
		_ss_dnsmasq_check_error='dnsmasq_version_unsupported'
		ss_status_set health_dnsmasq_version '0'
		ss_status_set health_dnsmasq_features '0'
		log_error "Unsupported dnsmasq version ${current_version}; SafeShield requires ${SS_MIN_DNSMASQ_VERSION} or later"
		return 1
	fi

	ss_status_set health_dnsmasq_version '1'
	if ss_dnsmasq_safeshield_block_supported; then
		ss_status_set health_dnsmasq_features '1'
	else
		# The SafeShield dnsmasq patch is optional for basic DNS blocking. Keep
		# protection available with legacy address=/domain/# rules, while the
		# statistics runtime disables itself because cumulative counters are absent.
		ss_status_set health_dnsmasq_features '0'
	fi

	return 0
}

ss_mkdirs() {
	mkdir -p "${SS_TMP_DIR}" "${SS_DNSMASQ_DIR}" "${SS_STATISTICS_DIR}"
}

ss_clean_tmp() {
	rm -f \
		"${SS_TMP_DIR}"/*.txt \
		"${SS_TMP_DIR}"/*.raw \
		"${SS_TMP_DIR}"/*.filtered \
		"${SS_TMP_DIR}"/*.domains \
		"${SS_TMP_DIR}"/*.json \
		"${SS_RESOLVED_SOURCES}" \
		"${SS_ARTIFACT_CACHE_STATE}" \
		"${SS_RUNTIME_OUT}" \
		2>/dev/null
}

ss_check_dnsmasq_confdir() {
	local confdir

	confdir="$(uci -q get dhcp.@dnsmasq[0].confdir 2>/dev/null)"
	[ "$confdir" = "${SS_DNSMASQ_DIR}" ]
}

check_dnsmasq_binary() {
	command_exists dnsmasq
}

check_dnsmasq_process() {
	pidof dnsmasq >/dev/null 2>&1
}

check_dns_runtime() {
	local domain i

	check_dnsmasq_process || return 1

	for domain in google.com cloudflare.com microsoft.com; do
		for i in 1 2 3 4 5 6 7 8 9 10; do
			ss_should_stop && return 130

			if nslookup "$domain" 127.0.0.1 >"${SS_RUNTIME_OUT}" 2>/dev/null; then
				if ! grep -Eq '^Address: *(0\.0\.0\.0|::)$' "${SS_RUNTIME_OUT}"; then
					rm -f "${SS_RUNTIME_OUT}"
					return 0
				fi
			fi

			ss_should_stop && return 130
			sleep 1
		done
	done

	rm -f "${SS_RUNTIME_OUT}"
	return 1
}

dnsmasq_restart() {
	local i

	log_info "Restarting dnsmasq"
	/etc/init.d/dnsmasq restart >/dev/null 2>&1 || return 1

	# shellcheck disable=SC2034
	for i in 1 2 3 4 5 6 7 8 9 10 \
		11 12 13 14 15 16 17 18 19 20 \
		21 22 23 24 25 26 27 28 29 30; do
		ss_should_stop && return 130

		if check_dnsmasq_process && nslookup localhost 127.0.0.1 >/dev/null 2>&1; then
			log_ok "dnsmasq restart done"
			return 0
		fi

		sleep 1
	done

	log_error "dnsmasq did not become ready after restart"
	return 1
}
