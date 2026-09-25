# shellcheck shell=sh
#
# gitbackup -- device identity: gb_device_id, gb_expand.

gb_device_id() {
	_gb_strategy=$(gb_uci_get gitbackup.main.device_id hostname)
	case "$_gb_strategy" in
		hostname) _gb_device_by_hostname ;;
		custom)   _gb_device_by_custom ;;
		board)    _gb_device_by_board ;;
		*) gb_die 2 "gitbackup.main.device_id: unknown strategy '$_gb_strategy' (want hostname, custom or board)" ;;
	esac
}

# gb_expand <template> -- substitutes {device}; resolves the device only when
# the placeholder is present, so a plain template never fails on it.
gb_expand() {
	_gb_dev=''
	case "$1" in
		*'{device}'*) _gb_dev=$(gb_device_id) || exit $? ;;
	esac
	gb_subst_device "$1" "$_gb_dev"
}

# Refuses the stock 'OpenWrt' hostname: two routers left at the default
# would push to the same branch and overwrite each other.
_gb_device_by_hostname() {
	_gb_board=$(ubus call system board 2>/dev/null)
	_gb_h=$(printf '%s' "$_gb_board" | jsonfilter -e '@.hostname')
	[ -n "$_gb_h" ] ||
		gb_die 2 "gitbackup.main.device_id=hostname: 'ubus call system board' returned no hostname"
	[ "$_gb_h" != 'OpenWrt' ] ||
		gb_die 2 'gitbackup.main.device_id=hostname: two routers with the default hostname would overwrite each other, name this device'
	printf '%s\n' "$_gb_h"
}

_gb_device_by_custom() {
	_gb_d=$(gb_uci_get gitbackup.main.device)
	[ -n "$_gb_d" ] ||
		gb_die 2 'gitbackup.main.device: empty, required when device_id=custom'
	case "$_gb_d" in
		*[!A-Za-z0-9._-]*)
			gb_die 2 "gitbackup.main.device: '$_gb_d' must match [A-Za-z0-9._-]{1,64}" ;;
	esac
	[ "${#_gb_d}" -le 64 ] ||
		gb_die 2 "gitbackup.main.device: '$_gb_d' is longer than the 64 characters allowed"
	printf '%s\n' "$_gb_d"
}

# <model-slug>-<last 6 hex of first NIC MAC>: hardware-only, deterministic.
# GB_SYSFS_NET is a test seam.
_gb_device_by_board() {
	_gb_board=$(ubus call system board 2>/dev/null)
	_gb_model=$(printf '%s' "$_gb_board" | jsonfilter -e '@.model')
	[ -n "$_gb_model" ] ||
		gb_die 2 "gitbackup.main.device_id=board: 'ubus call system board' returned no model"

	_gb_net="${GB_SYSFS_NET:-/sys/class/net}"
	_gb_mac=''
	# shellcheck disable=SC2012  # find's -printf is not in busybox; ls output here is plain interface names
	for _gb_if in $(ls "$_gb_net" 2>/dev/null | sort); do
		[ "$_gb_if" = lo ] && continue
		[ -r "$_gb_net/$_gb_if/address" ] || continue
		_gb_candidate=$(cat "$_gb_net/$_gb_if/address")
		if [ -n "$_gb_candidate" ] && [ "$_gb_candidate" != '00:00:00:00:00:00' ]; then
			_gb_mac="$_gb_candidate"
			break
		fi
	done
	[ -n "$_gb_mac" ] ||
		gb_die 2 "gitbackup.main.device_id=board: no network interface with a MAC address was found under $_gb_net"

	_gb_tail=$(printf '%s' "$_gb_mac" | tr -d ':' | tr 'A-F' 'a-f')
	_gb_tail=$(printf '%s' "$_gb_tail" | sed 's/^.*\(......\)$/\1/')
	printf '%s-%s\n' "$(_gb_slugify "$_gb_model")" "$_gb_tail"
}

_gb_slugify() {
	# shellcheck disable=SC2018,SC2019  # ASCII on purpose: device names must match [A-Za-z0-9._-]
	printf '%s' "$1" | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9]/-/g'
}
