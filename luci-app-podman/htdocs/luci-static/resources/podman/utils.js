'use strict';

'require baseclass';

const UtilIpv6 = baseclass.extend({
	/**
	 * Derive ULA IPv6 subnet and gateway from IPv4 subnet.
	 * Uses IPv4 octets 3-4 as subnet ID for consistent IPv4/IPv6 mapping.
	 * @param {string} ipv4 - IPv4 subnet in CIDR (e.g., "192.168.20.0/24")
	 * @param {string} ula_prefix - ULA prefix (e.g., "fd52:425:78eb::/48")
	 * @returns {{ipv6subnet: string, ipv6gateway: string}} IPv6 config with subnet/gateway
	 */
	deriveUlaFromIpv4(ipv4, ula_prefix) {
		const ipv4Address = ipv4.split('/')[0];
		const octets = ipv4Address.split('.').map(Number);
		const subnetIdHex = ((octets[2] << 8) | octets[3]).toString(16).padStart(4, '0');
		const ulaAddress = ula_prefix.split('/')[0];
		const ulaParts = ulaAddress.split('::');

		let hextets = ulaParts[0].split(':');
		if (hextets.length === 1 && hextets[0] === "") {
			hextets = [];
		}

		while (hextets.length < 3) {
			hextets.push('0');
		}

		const ipv6SubnetAddress = `${hextets.slice(0, 3).join(':')}:${subnetIdHex}::`;

		return {
			ipv6subnet: `${ipv6SubnetAddress}/64`,
			ipv6gateway: `${ipv6SubnetAddress}1`
		};
	},
});

const UtilIpv4 = baseclass.extend({
	// >>> 0 forces unsigned 32-bit interpretation (JS bitwise ops are signed)
	_ipToInt(octets) {
		return ((octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3]) >>> 0;
	},

	_intToIp(n) {
		return [(n >>> 24) & 0xFF, (n >>> 16) & 0xFF, (n >>> 8) & 0xFF, n & 0xFF].join('.');
	},

	/**
	 * Convert a CIDR string to a start/end IP range.
	 * Works for both network addresses (10.89.0.0/24) and host addresses
	 * within a subnet (10.89.0.5/24) - the mask normalises either to the
	 * full network range.
	 * @param {string} cidr - CIDR notation (e.g., "10.89.0.128/25")
	 * @returns {{start_ip: string, end_ip: string}|null} Range or null if invalid
	 */
	cidrToRange(cidr) {
		if (!cidr || typeof cidr !== 'string') return null;

		const parts = cidr.split('/');
		if (parts.length !== 2) return null;

		const octets = parts[0].split('.').map(Number);
		const prefixLen = parseInt(parts[1], 10);

		if (octets.length !== 4 || octets.some(o => isNaN(o) || o < 0 || o > 255)) return null;
		if (isNaN(prefixLen) || prefixLen < 0 || prefixLen > 32) return null;

		const ipInt = this._ipToInt(octets);
		const mask  = prefixLen === 0 ? 0 : (0xFFFFFFFF << (32 - prefixLen)) >>> 0;

		return {
			start_ip: this._intToIp((ipInt & mask) >>> 0),
			end_ip:   this._intToIp((ipInt | (~mask >>> 0)) >>> 0),
		};
	},

	/**
	 * Return the first usable host address in a subnet (network address + 1).
	 * Conventionally used as the gateway address.
	 * @param {string} cidr - CIDR notation (e.g., "10.89.0.0/24")
	 * @returns {string|null} First host IP (e.g., "10.89.0.1") or null if invalid
	 */
	firstHost(cidr) {
		const range = this.cidrToRange(cidr);
		if (!range) return null;

		const octets = range.start_ip.split('.').map(Number);
		const next   = (this._ipToInt(octets) + 1) >>> 0;

		return this._intToIp(next);
	},
});

const UtilFormat = baseclass.extend({
	__name__: 'Podman.Util.Format',

	/**
	 * Format bytes to human-readable size
	 */
	bytes(bytes, decimals) {
		if (!bytes) return '0 B';

		decimals = decimals ?? 2;
		const k = 1024;
		const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
		const i = Math.floor(Math.log(bytes) / Math.log(k));

		return parseFloat((bytes / k ** i).toFixed(decimals)) + ' ' + sizes[i];
	},

	/**
	 * Format timestamp to locale string with leading zeros
	 */
	date(timestamp) {
		if (!timestamp) {
			return _('Never');
		}

		let date;

		if (typeof timestamp === 'string') {
			if (timestamp === '0001-01-01T00:00:00Z' || timestamp.startsWith('0001-')) {
				return _('Never');
			}
			date = new Date(timestamp);
		} else {
			date = new Date(timestamp * 1000);
		}

		if (isNaN(date.getTime())) {
			return _('Unknown');
		}

		if (date.getFullYear() < 1970) {
			return _('Never');
		}

		const day = ('0' + date.getDate()).slice(-2);
		const month = ('0' + (date.getMonth() + 1)).slice(-2);
		const year = date.getFullYear();
		const hours = ('0' + date.getHours()).slice(-2);
		const minutes = ('0' + date.getMinutes()).slice(-2);
		const seconds = ('0' + date.getSeconds()).slice(-2);

		return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
	},

	/**
	 * Parse memory string to bytes
	 * Supports formats: 512m, 1g, 2gb, 1024, etc.
	 * @param {string} memStr - Memory string (e.g., "512m", "1g", "2gb")
	 * @returns {number} Size in bytes
	 */
	parseMemory(memStr) {
		if (!memStr) return 0;

		const match = memStr.match(/^(\d+(?:\.\d+)?)\s*([kmgt]?b?)?$/i);
		if (!match) return 0;

		const value = parseFloat(match[1]);
		const unit = (match[2] || 'b').toLowerCase();

		const multipliers = {
			b: 1,
			k: 1024,
			kb: 1024,
			m: 1024 * 1024,
			mb: 1024 * 1024,
			g: 1024 * 1024 * 1024,
			gb: 1024 * 1024 * 1024,
			t: 1024 * 1024 * 1024 * 1024,
			tb: 1024 * 1024 * 1024 * 1024
		};

		return Math.floor(value * (multipliers[unit] || 1));
	},

	/**
	 * Parse duration string to nanoseconds (Podman format)
	 * Supports formats: 30s, 1m, 1h, 500ms, etc.
	 * @param {string} duration - Duration string (e.g., "30s", "1m", "1h")
	 * @returns {number} Duration in nanoseconds, or 0 if invalid
	 */
	parseDuration(duration) {
		if (!duration) return 0;

		const match = duration.match(/^(\d+(?:\.\d+)?)\s*(ns|us|ms|s|m|h)$/);
		if (!match) return 0;

		const value = parseFloat(match[1]);
		const unit = match[2];

		const multipliers = {
			ns: 1,
			us: 1000,
			ms: 1000000,
			s: 1000000000,
			m: 60000000000,
			h: 3600000000000
		};

		return Math.floor(value * (multipliers[unit] || 0));
	},
});

/**
 * Shared utility functions.
 */
return baseclass.extend({
	ipv4: new UtilIpv4(),

	ipv6: new UtilIpv6(),

	format: new UtilFormat(),

	truncate(str, maxLength) {
		if (!str || str.length <= maxLength) {
			return str;
		}

		return str.substring(0, maxLength) + '...';
	},

	moveArrayItem(arr, fromIndex, toIndex) {
		const [item] = arr.splice(fromIndex, 1);
		arr.splice(toIndex, 0, item);
		return arr;
	},

	_p(stringPlural) {
		return this._n(2, '', stringPlural);
	},

	_n(length, stringSingular, stringPlural) {
		return parseInt(length) === 1 ?
			stringSingular : stringPlural;
	},
});
