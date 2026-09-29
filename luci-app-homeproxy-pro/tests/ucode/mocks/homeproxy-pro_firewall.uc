/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Test double for root/etc/homeproxy-pro/scripts/homeproxy-pro.uc, scoped to
 * what firewall_pre.uc imports: isEmpty, RUN_DIR, validation.
 *
 * RUN_DIR is read from the HP_FW_RUN_DIR global so the test can
 * point the script at a scratch dir; firewall_pre.uc writes
 * fw4_forward.nft / fw4_input.nft into RUN_DIR, and the test must
 * not clobber /var/run/homeproxy-pro on a host that happens to have it.
 *
 * validation() is the same pure-ucode stand-in the parser tests use
 * (the production one shells out to /sbin/validate_data, which does
 * not exist off-target). Keep it in sync with mocks/homeproxy-pro.uc.
 */

export function isEmpty(res) {
	return !res || res === 'nil' || (type(res) in ['array', 'object'] && length(res) === 0);
};

export const RUN_DIR = global.HP_FW_RUN_DIR;

/* Pure-ucode stand-in for /sbin/validate_data (port / ip4 / ip6 / hostname). */
export function validation(datatype, data) {
	if (!datatype || !data)
		return null;

	switch (datatype) {
	case 'port':
		return match(data, /^\d+$/) != null && int(data) >= 0 && int(data) <= 65535;
	case 'ip4addr':
		if (match(data, /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) == null)
			return false;
		for (let octet in split(data, '.'))
			if (int(octet) > 255)
				return false;
		return true;
	case 'ip6addr':
		return match(data, /^[0-9a-fA-F:]+$/) != null && match(data, /::.*::/) == null;
	case 'hostname':
		return match(data, /^[A-Za-z0-9_][A-Za-z0-9_%-.]*[A-Za-z0-9]$/) != null ||
			match(data, /^[A-Za-z0-9_]$/) != null;
	case 'host':
		return validation('ip4addr', data) === true ||
			validation('ip6addr', data) === true ||
			validation('hostname', data) === true;
	default:
		return null;
	}
};