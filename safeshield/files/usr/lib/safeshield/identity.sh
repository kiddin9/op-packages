# shellcheck shell=ash

SS_IDENTITY_DIR="${SS_IDENTITY_DIR:-/etc/safeshield}"
SS_IDENTITY_FILE="${SS_IDENTITY_FILE:-${SS_IDENTITY_DIR}/identity.env}"

SS_IDENTITY_VERSION="1"
SS_PHYSICAL_FINGERPRINT=""
SS_FINGERPRINT_VERSION="1"
SS_IDENTITY_PROVIDER=""
SS_IDENTITY_SOURCE=""
SS_IDENTITY_STRENGTH=""
SS_IDENTITY_PROFILE=""
SS_IDENTITY_VALUE_SHA256=""
SS_INSTALLATION_ID=""
SS_INSTALLATION_SECRET=""
SS_IDENTITY_CREATED_AT=""
SS_IDENTITY_UPDATED_AT=""
SS_DEVICE_CODE=""
SS_DEVICE_CODE_SOURCE="unknown"
SS_SMARTSAFEHUB_FIRMWARE_JSON="${SS_SMARTSAFEHUB_FIRMWARE_JSON:-/usr/share/smartsafehub/firmware.json}"

ss_identity_log_warn() {
	if command -v log_warn >/dev/null 2>&1; then
		log_warn "$1"
	else
		logger -t safeshield "$1" 2>/dev/null || true
	fi
}

ss_identity_log_info() {
	if command -v log_info >/dev/null 2>&1; then
		log_info "$1"
	else
		logger -t safeshield "$1" 2>/dev/null || true
	fi
}

ss_identity_command_exists() {
	command -v "$1" >/dev/null 2>&1
}

ss_identity_sha256() {
	local value="$1"

	if ! ss_identity_command_exists sha256sum; then
		ss_identity_log_warn "sha256sum is required for identity hashing"
		return 1
	fi

	printf '%s' "$value" | sha256sum | awk '{print $1}'
}

ss_identity_random_hex_32() {
	if [ -r /dev/urandom ] && ss_identity_command_exists hexdump; then
		hexdump -n 32 -e '32/1 "%02x"' /dev/urandom 2>/dev/null && return 0
	fi

	ss_identity_sha256 "fallback-random|$(date +%s)|$$|$(cat /proc/uptime 2>/dev/null)"
}

ss_identity_uuid() {
	local value=""

	value="$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '\r\n' || true)"
	if [ -n "$value" ]; then
		printf '%s' "$value"
		return 0
	fi

	value="$(ss_identity_random_hex_32)"
	printf '%s-%s-%s-%s-%s' \
		"$(printf '%s' "$value" | cut -c 1-8)" \
		"$(printf '%s' "$value" | cut -c 9-12)" \
		"$(printf '%s' "$value" | cut -c 13-16)" \
		"$(printf '%s' "$value" | cut -c 17-20)" \
		"$(printf '%s' "$value" | cut -c 21-32)"
}

ss_identity_read_file_one_line() {
	local path="$1"

	[ -r "$path" ] || return 1
	tr -d '\000\r\n' <"$path" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | head -c 256
}

ss_identity_normalize_mac() {
	printf '%s' "$1" |
		tr 'A-F' 'a-f' |
		sed -n 's/.*\([0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]\).*/\1/p' |
		head -n 1
}

ss_identity_valid_mac() {
	local mac="$1"

	case "$mac" in
		'' | 00:00:00:00:00:00 | ff:ff:ff:ff:ff:ff)
			return 1
			;;
	esac

	printf '%s' "$mac" | grep -Eq '^[0-9a-f]{2}(:[0-9a-f]{2}){5}$'
}

ss_identity_valid_sha256() {
	printf '%s' "$1" | grep -Eq '^[0-9a-f]{64}$'
}

ss_identity_board_name() {
	local value=""

	value="$(ss_identity_read_file_one_line /tmp/sysinfo/board_name 2>/dev/null || true)"
	[ -n "$value" ] || value="$(ubus call system board 2>/dev/null | jsonfilter -e '@.board_name' 2>/dev/null | head -n 1 || true)"
	[ -n "$value" ] || value="unknown"
	printf '%s' "$value"
}

ss_identity_valid_device_code() {
	printf '%s' "$1" | grep -Eq '^[a-z0-9][a-z0-9._-]{0,63}$'
}

ss_identity_device_code_from_firmware() {
	local firmware_json="${SS_SMARTSAFEHUB_FIRMWARE_JSON:-/usr/share/smartsafehub/firmware.json}"
	local device_code=""

	[ -r "$firmware_json" ] || return 1
	ss_identity_command_exists jsonfilter || return 1

	device_code="$(jsonfilter -i "$firmware_json" -e '@.device_code' 2>/dev/null | head -n 1 | tr -d '\r\n' || true)"
	ss_identity_valid_device_code "$device_code" || return 1

	printf '%s' "$device_code"
}

ss_identity_device_code_from_board() {
	local board="$1"

	case "$board" in
		iptime,ax3000sm)
			printf '%s' 'iptime-ax3000sm'
			;;
		glinet,gl-mt300n-v2 | gl.inet,gl-mt300n-v2)
			printf '%s' 'gl-mt300n-v2'
			;;
		xiaomi,mi-router-ax3000t | xiaomi,mi-router-ax3000t-ubootmod)
			printf '%s' 'xiaomi-ax3000t'
			;;
		*)
			return 1
			;;
	esac
}

ss_identity_refresh_device_code() {
	local device_code=""
	local board=""

	device_code="$(ss_identity_device_code_from_firmware 2>/dev/null || true)"
	if [ -n "$device_code" ]; then
		SS_DEVICE_CODE="$device_code"
		SS_DEVICE_CODE_SOURCE="smartsafehub_firmware"
		return 0
	fi

	board="$(ss_identity_board_name)"
	device_code="$(ss_identity_device_code_from_board "$board" 2>/dev/null || true)"
	if [ -n "$device_code" ]; then
		SS_DEVICE_CODE="$device_code"
		SS_DEVICE_CODE_SOURCE="board"
		return 0
	fi

	SS_DEVICE_CODE=""
	SS_DEVICE_CODE_SOURCE="unknown"
	return 0
}

ss_identity_profile_code() {
	local board="$1"
	local profile=""

	case "$board" in
		iptime,ax3000sm | *ax3000sm*)
			profile="iptime_ax3000sm"
			;;
		glinet,gl-mt300n-v2 | gl.inet,gl-mt300n-v2 | *gl-mt300n-v2*)
			profile="gl_mt300n_v2"
			;;
		smartsafehub,* | *smartsafehub*)
			profile="smartsafehub"
			;;
		*)
			profile="$(printf '%s' "$board" | tr 'A-Z,.-' 'a-z___' | sed 's/[^a-z0-9_]/_/g')"
			[ -n "$profile" ] || profile="unknown"
			;;
	esac

	printf '%s' "$profile"
}

ss_identity_mtd_device_by_name() {
	local name="$1"

	[ -r /proc/mtd ] || return 1
	awk -F: -v q="\"${name}\"" 'index($0, q) { print "/dev/" $1; exit }' /proc/mtd
}

ss_identity_hex_to_mac() {
	local hex="$1"

	printf '%s' "$hex" | sed 's/[^0-9a-fA-F]//g' | tr 'A-F' 'a-f' | sed 's/../&:/g; s/:$//'
}

ss_identity_mtd_get_mac_binary_fallback() {
	local part="$1"
	local offset="$2"
	local dev=""
	local hex=""

	dev="$(ss_identity_mtd_device_by_name "$part" 2>/dev/null || true)"
	[ -n "$dev" ] || return 1
	[ -r "$dev" ] || return 1
	ss_identity_command_exists dd || return 1
	ss_identity_command_exists hexdump || return 1

	# ash supports hexadecimal arithmetic, so offsets like 0x4 are accepted.
	hex="$(dd if="$dev" bs=1 skip=$((offset)) count=6 2>/dev/null | hexdump -v -e '1/1 "%02x"' 2>/dev/null)"
	[ "${#hex}" -eq 12 ] || return 1
	ss_identity_hex_to_mac "$hex"
}

ss_identity_mtd_get_mac() {
	local part="$1"
	local offset="$2"
	local mac=""

	if ss_identity_command_exists mtd_get_mac_binary; then
		mac="$(mtd_get_mac_binary "$part" "$offset" 2>/dev/null || true)"
		mac="$(ss_identity_normalize_mac "$mac")"
		if ss_identity_valid_mac "$mac"; then
			printf '%s' "$mac"
			return 0
		fi
	fi

	mac="$(ss_identity_mtd_get_mac_binary_fallback "$part" "$offset" 2>/dev/null || true)"
	mac="$(ss_identity_normalize_mac "$mac")"
	ss_identity_valid_mac "$mac" || return 1
	printf '%s' "$mac"
}

ss_identity_try_mtd_factory_mac() {
	local board="$1"
	local mac=""
	local offset=""

	case "$board" in
		iptime,ax3000sm | *ax3000sm*)
			mac="$(ss_identity_mtd_get_mac Factory 0x4 2>/dev/null || true)"
			if ss_identity_valid_mac "$mac"; then
				printf '%s|%s' "$mac" "mtd:Factory:0x4:mac"
				return 0
			fi

			mac="$(ss_identity_mtd_get_mac factory 0x4 2>/dev/null || true)"
			if ss_identity_valid_mac "$mac"; then
				printf '%s|%s' "$mac" "mtd:factory:0x4:mac"
				return 0
			fi
			;;

		glinet,gl-mt300n-v2 | gl.inet,gl-mt300n-v2 | *gl-mt300n-v2*)
			# Must be verified on the real GL-MT300N-V2 before production.
			for offset in 0x4 0x28 0x2e; do
				mac="$(ss_identity_mtd_get_mac factory "$offset" 2>/dev/null || true)"
				if ss_identity_valid_mac "$mac"; then
					printf '%s|%s' "$mac" "mtd:factory:${offset}:mac"
					return 0
				fi
			done
			;;
	esac

	return 1
}

ss_identity_try_factory_device_id() {
	local value=""
	local path=""

	# Future SmartSafeHub hardware can expose a factory-programmed device_id
	# through DTS/NVMEM, sysfs, or a small platform driver.
	for path in \
		/sys/firmware/smartsafehub/device_id \
		/sys/firmware/devicetree/base/smartsafehub,device-id \
		/proc/device-tree/smartsafehub,device-id; do
		value="$(ss_identity_read_file_one_line "$path" 2>/dev/null || true)"
		case "$value" in
			'' | *[!A-Za-z0-9._:-]*) ;;
			*)
				printf '%s|%s' "$value" "path:${path}"
				return 0
				;;
		esac
	done

	return 1
}

ss_identity_detect_primary_mac() {
	local iface=""
	local mac=""

	for iface in br-lan eth0 eth1 wan lan wlan0 wlan1; do
		mac="$(cat "/sys/class/net/${iface}/address" 2>/dev/null || true)"
		mac="$(ss_identity_normalize_mac "$mac")"
		if ss_identity_valid_mac "$mac"; then
			printf '%s' "$mac"
			return 0
		fi
	done

	if ss_identity_command_exists ip; then
		mac="$(ip link 2>/dev/null | awk '/link\/ether/ { print $2; exit }')"
		mac="$(ss_identity_normalize_mac "$mac")"
		if ss_identity_valid_mac "$mac"; then
			printf '%s' "$mac"
			return 0
		fi
	fi

	return 1
}

ss_identity_compute_physical() {
	local model="$1"
	local arch="$2"
	local board=""
	local profile=""
	local value=""
	local source=""
	local result=""
	local material=""

	board="$(ss_identity_board_name)"
	profile="$(ss_identity_profile_code "$board")"
	SS_IDENTITY_PROFILE="$profile"

	# SmartSafeHub 전용 기기는 factory-programmed device_id를 우선 사용
	case "$profile" in
		smartsafehub*)
			result="$(ss_identity_try_factory_device_id 2>/dev/null || true)"
			if [ -n "$result" ]; then
				value="${result%%|*}"
				source="${result#*|}"

				SS_IDENTITY_PROVIDER="factory_device_id"
				SS_IDENTITY_SOURCE="$source"
				SS_IDENTITY_STRENGTH="hardware_strong"
				SS_IDENTITY_VALUE_SHA256="$(ss_identity_sha256 "$value")" || return 1

				material="safeshield-physical-v1|provider=${SS_IDENTITY_PROVIDER}|source=${SS_IDENTITY_SOURCE}|profile=${profile}|value_sha256=${SS_IDENTITY_VALUE_SHA256}"
				SS_PHYSICAL_FINGERPRINT="$(ss_identity_sha256 "$material")" || return 1
				return 0
			fi
			;;
	esac

	# 기존 판매 공유기는 factory/ART/Factory 파티션 MAC을 우선 사용
	result="$(ss_identity_try_mtd_factory_mac "$board" 2>/dev/null || true)"
	if [ -n "$result" ]; then
		value="${result%%|*}"
		source="${result#*|}"

		SS_IDENTITY_PROVIDER="factory_mac"
		SS_IDENTITY_SOURCE="$source"
		SS_IDENTITY_STRENGTH="hardware_soft"
		SS_IDENTITY_VALUE_SHA256="$(ss_identity_sha256 "$value")" || return 1

		material="safeshield-physical-v1|provider=${SS_IDENTITY_PROVIDER}|source=${SS_IDENTITY_SOURCE}|profile=${profile}|mac_sha256=${SS_IDENTITY_VALUE_SHA256}"
		SS_PHYSICAL_FINGERPRINT="$(ss_identity_sha256 "$material")" || return 1
		return 0
	fi

	# Last hardware-derived fallback. This is not fully reinstall-stable if the
	# user changes MAC clone settings, but it is better than failing completely.
	value="$(ss_identity_detect_primary_mac 2>/dev/null || true)"
	if [ -n "$value" ]; then
		SS_IDENTITY_PROVIDER="interface_mac"
		SS_IDENTITY_SOURCE="sysfs:/sys/class/net/*/address"
		SS_IDENTITY_STRENGTH="hardware_soft_unverified"
		SS_IDENTITY_VALUE_SHA256="$(ss_identity_sha256 "$value")" || return 1
		material="safeshield-physical-v1|provider=${SS_IDENTITY_PROVIDER}|source=${SS_IDENTITY_SOURCE}|profile=${profile}|model=${model}|arch=${arch}|mac_sha256=${SS_IDENTITY_VALUE_SHA256}"
		SS_PHYSICAL_FINGERPRINT="$(ss_identity_sha256 "$material")" || return 1
		return 0
	fi

	return 1
}

ss_identity_load() {
	[ -r "$SS_IDENTITY_FILE" ] || return 1

	# shellcheck disable=SC1090
	. "$SS_IDENTITY_FILE"

	SS_IDENTITY_VERSION="${IDENTITY_VERSION:-}"
	SS_FINGERPRINT_VERSION="${FINGERPRINT_VERSION:-}"
	SS_PHYSICAL_FINGERPRINT="${PHYSICAL_FINGERPRINT:-}"
	SS_IDENTITY_PROVIDER="${IDENTITY_PROVIDER:-}"
	SS_IDENTITY_SOURCE="${IDENTITY_SOURCE:-}"
	SS_IDENTITY_STRENGTH="${IDENTITY_STRENGTH:-}"
	SS_IDENTITY_PROFILE="${IDENTITY_PROFILE:-}"
	SS_IDENTITY_VALUE_SHA256="${IDENTITY_VALUE_SHA256:-}"
	SS_INSTALLATION_ID="${INSTALLATION_ID:-}"
	SS_INSTALLATION_SECRET="${INSTALLATION_SECRET:-}"
	SS_IDENTITY_CREATED_AT="${CREATED_AT:-}"
	SS_IDENTITY_UPDATED_AT="${UPDATED_AT:-}"

	ss_identity_valid_sha256 "$SS_PHYSICAL_FINGERPRINT" || return 1
	[ -n "$SS_INSTALLATION_ID" ] || return 1
	[ -n "$SS_IDENTITY_PROVIDER" ] || return 1
	[ -n "$SS_IDENTITY_SOURCE" ] || return 1
	[ -n "$SS_IDENTITY_STRENGTH" ] || return 1
	[ -n "$SS_IDENTITY_PROFILE" ] || return 1

	return 0
}

ss_identity_write_env() {
	local tmp="${SS_IDENTITY_FILE}.tmp"

	mkdir -p "$SS_IDENTITY_DIR" || return 1
	chmod 700 "$SS_IDENTITY_DIR" 2>/dev/null || true

	cat >"$tmp" <<EOF_ENV
IDENTITY_VERSION='${SS_IDENTITY_VERSION}'
FINGERPRINT_VERSION='${SS_FINGERPRINT_VERSION}'
PHYSICAL_FINGERPRINT='${SS_PHYSICAL_FINGERPRINT}'
IDENTITY_PROVIDER='${SS_IDENTITY_PROVIDER}'
IDENTITY_SOURCE='${SS_IDENTITY_SOURCE}'
IDENTITY_STRENGTH='${SS_IDENTITY_STRENGTH}'
IDENTITY_PROFILE='${SS_IDENTITY_PROFILE}'
IDENTITY_VALUE_SHA256='${SS_IDENTITY_VALUE_SHA256}'
INSTALLATION_ID='${SS_INSTALLATION_ID}'
INSTALLATION_SECRET='${SS_INSTALLATION_SECRET}'
CREATED_AT='${SS_IDENTITY_CREATED_AT}'
UPDATED_AT='${SS_IDENTITY_UPDATED_AT}'
EOF_ENV

	chmod 600 "$tmp" 2>/dev/null || true
	mv -f "$tmp" "$SS_IDENTITY_FILE"
}

ss_identity_sync_uci() {
	uci -q batch <<EOF_UCI
set safeshield.identity=identity
set safeshield.identity.physical_fingerprint='${SS_PHYSICAL_FINGERPRINT}'
set safeshield.identity.fingerprint_version='${SS_FINGERPRINT_VERSION}'
set safeshield.identity.identity_provider='${SS_IDENTITY_PROVIDER}'
set safeshield.identity.identity_source='${SS_IDENTITY_SOURCE}'
set safeshield.identity.identity_strength='${SS_IDENTITY_STRENGTH}'
set safeshield.identity.identity_profile='${SS_IDENTITY_PROFILE}'
set safeshield.identity.device_code='${SS_DEVICE_CODE}'
set safeshield.identity.device_code_source='${SS_DEVICE_CODE_SOURCE}'
set safeshield.identity.installation_id='${SS_INSTALLATION_ID}'
set safeshield.identity.created_at='${SS_IDENTITY_CREATED_AT}'
set safeshield.identity.updated_at='${SS_IDENTITY_UPDATED_AT}'
commit safeshield
EOF_UCI
}

ss_identity_status_set() {
	command -v ss_status_set >/dev/null 2>&1 || return 0

	ss_status_set physical_fingerprint "$SS_PHYSICAL_FINGERPRINT"
	ss_status_set fingerprint_version "$SS_FINGERPRINT_VERSION"
	ss_status_set identity_provider "$SS_IDENTITY_PROVIDER"
	ss_status_set identity_source "$SS_IDENTITY_SOURCE"
	ss_status_set identity_strength "$SS_IDENTITY_STRENGTH"
	ss_status_set identity_profile "$SS_IDENTITY_PROFILE"
	ss_status_set device_code "$SS_DEVICE_CODE"
	ss_status_set device_code_source "$SS_DEVICE_CODE_SOURCE"
	ss_status_set installation_id "$SS_INSTALLATION_ID"
}

ss_identity_create() {
	local model="$1"
	local arch="$2"
	local now=""
	local value=""

	now="$(date +%s)"
	SS_FINGERPRINT_VERSION="1"
	SS_INSTALLATION_ID="$(ss_identity_uuid)"
	SS_INSTALLATION_SECRET="$(ss_identity_random_hex_32)"
	SS_IDENTITY_CREATED_AT="$now"
	SS_IDENTITY_UPDATED_AT="$now"

	if ! ss_identity_compute_physical "$model" "$arch" || ! ss_identity_valid_sha256 "$SS_PHYSICAL_FINGERPRINT"; then
		# Final fallback only when no physical source exists. This preserves
		# basic operation but cannot survive full reinstall/factory reset.
		value="$(ss_identity_random_hex_32)"
		SS_IDENTITY_PROVIDER="installation_random"
		SS_IDENTITY_SOURCE="${SS_IDENTITY_FILE}"
		SS_IDENTITY_STRENGTH="fallback_random"
		SS_IDENTITY_PROFILE="$(ss_identity_profile_code "$(ss_identity_board_name)")"
		SS_IDENTITY_VALUE_SHA256="$(ss_identity_sha256 "$value")" || return 1
		SS_PHYSICAL_FINGERPRINT="$(ss_identity_sha256 "safeshield-physical-v1|provider=installation_random|profile=${SS_IDENTITY_PROFILE}|value_sha256=${SS_IDENTITY_VALUE_SHA256}")" || return 1
		ss_identity_log_warn "No stable hardware identity source found; using installation-random physical_fingerprint"
	fi

	ss_identity_refresh_device_code
	ss_identity_write_env || return 1
	ss_identity_sync_uci || true
	ss_identity_status_set || true
	ss_identity_log_info "SafeShield identity initialized provider=${SS_IDENTITY_PROVIDER} source=${SS_IDENTITY_SOURCE}"
}

ss_identity_ensure() {
	local model="${1:-}"
	local arch="${2:-}"

	if ss_identity_load; then
		ss_identity_refresh_device_code
		ss_identity_sync_uci || true
		ss_identity_status_set || true
		return 0
	fi

	ss_identity_create "$model" "$arch"
}
