/** @typedef {import('./types/network.uc').CIDRRange} CIDRRange */
/**
 * 使用原生地址解析校验 IP 或 CIDR，仅接受十进制前缀长度。
 * @param {string|null} value 裸 IP 或 IP/前缀；不包含空白、作用域或地址形式的掩码。
 * @returns {CIDRRange|null}
 * 地址字节、地址族 4/6 和前缀长度；裸 IP 使用完整位数，无效输入返回 null。
 */
export function parseCIDR(value) {
	// 原生地址和正则解析在空字节处结束，必须先拒绝被截断的输入。
	if (type(value) != 'string' || index(value, chr(0)) >= 0) {
		return null;
	}
	let parts = split(value, '/');
	if (length(parts) != 1 && length(parts) != 2) {
		return null;
	}
	let bytes = iptoarr(parts[0] || '');
	if (!bytes) {
		return null;
	}
	let prefix = length(bytes) * 8;
	if (length(parts) == 2) {
		if (!match(parts[1], /^[0-9]+$/)) {
			return null;
		}
		prefix = int(parts[1], 10);
		if (type(prefix) != 'int' || prefix < 0 || prefix > length(bytes) * 8) {
			return null;
		}
	}
	return { bytes, family: length(bytes) == 4 ? 4 : 6, prefix };
};
