/** @typedef {import('../../../share/ucode/hijpass/types/network.uc').PingReport} PingReport */
/** @typedef {import('../../../share/ucode/hijpass/types/network.uc').ProbeRequest} ProbeRequest */
/** @typedef {import('../../../share/ucode/hijpass/types/network.uc').CurlReport} CurlReport */
/** @typedef {import('../../../share/ucode/hijpass/types/network.uc').CommandOutput} CommandOutput */
import * as fs from 'fs';
import { query } from 'resolv';
import { port } from 'hijpass.config.values';
import { run } from 'hijpass.command.runtime';
import { parseCIDR } from 'hijpass.ip';

// 地址解析返回 IP 字符串，不改动 TLS 的 server_name，代理链仍可验证原始域名证书。
/**
 * 将域名解析为 IP，优先使用 IPv4。
 * @param {string|null} host
 * @returns {string} IP 字符串；传入 IP 原样返回，解析失败时抛错。
 */
export function resolve(host) {
	if (type(host) != 'string') {
		die('invalid argument');
	}
	if (iptoarr(host)) {
		return host;
	}
	if (!match(host || '', /^[A-Za-z0-9.-]+$/)) {
		die('invalid argument');
	}
	let answer = query(host, { type: ['A', 'AAAA'], timeout: 5000 });
	let addresses = answer?.[host]?.A || answer?.A || [];
	if (!length(addresses)) {
		addresses = answer?.[host]?.AAAA || answer?.AAAA || [];
	}
	if (!length(addresses)) {
		die(`resolve failed: ${host}`);
	}
	let address = addresses[0];
	if (type(address) != 'string' || !iptoarr(address)) {
		die(`invalid DNS answer: ${host}`);
	}
	return address;
};
/**
 * 把 curl 输出和退出码整理成连接探测报告。
 * @param {CommandOutput} response Shell 提供的标准输出及真实退出状态。
 * @param {string} url 原始 URL，用于报告。
 * @returns {CurlReport} 含成功状态、退出码的报告；输出完整时附 HTTP、远端地址和耗时（毫秒）。
 */
export function curlReport(response, url) {
	let fields = split(response.stdout, '\n');
	let result = { url, success: response.code == 0, exit_code: response.code };
	if (length(fields) >= 8) {
		result.http_code = int(fields[0]); result.remote_ip = fields[1]; result.remote_port = int(fields[2]);
		for (let key, value in {
			dns_lookup_time_ms: +fields[3], tcp_connect_time_ms: +fields[4], tls_handshake_time_ms: +fields[5],
			server_processing_time_ms: +fields[6], total_time_ms: +fields[7], first_byte_time_ms: +fields[6],
		}) result[key] = int(value * 1000);
	}
	return result;
};

// ProbeRequest：url 是 HTTP(S) 地址，timeout 为秒，socks 为本地 SOCKS 端口或空。
/**
 * 校验 HTTP 探测地址、超时和本地代理参数。
 * @param {string|null} url
 * @param {string} [timeout]
 * @param {string} [socks]
 * @returns {ProbeRequest} {url, timeout, socks}；timeout 单位为秒，无代理时 socks 为空字符串。
 */
export function request(url, timeout, socks) {
    if (type(url) != 'string') {
        die('only http:// and https:// URLs are supported');
    }
    if (!match(url || '', /^https?:\/\//)) {
        die('only http:// and https:// URLs are supported');
    }
    if (!match(timeout || '5', /^[0-9]+$/)) {
        die('timeout must be an integer');
    }
    let seconds = int(timeout || '5');
    if (seconds < 1 || seconds > 120) {
        die('timeout must be between 1 and 120');
    }
    if (socks) {
        port(socks);
    }
    return { url, timeout: seconds, socks: socks || '' };
};
// Shell 提供 curl 原始输出及真实退出码；这里仅解析和计算测速数据。
/**
 * 从 curl 探测结果提取节点延迟。
 * @param {CommandOutput} response
 * @param {string} url
 * @returns {PingReport} {ms, total_ms}，单位为毫秒；失败时为 {error: "timeout"}，退出码 56 按现有规则保留结果。
 */
export function pingReport(response, url) {
    let result = curlReport(response, url);
    if (!result.success && result.exit_code != 56) {
        return { error: 'timeout' };
    }
    return { ms: result.first_byte_time_ms - result.dns_lookup_time_ms, total_ms: result.total_time_ms };
};
// IPv4/IPv6 CIDR 比较使用内建字节地址，不需要 Lua/luci.ip。
/**
 * 判断 IP 地址是否属于指定 CIDR 网段。
 * @param {string} address
 * @param {string} cidr
 * @returns {boolean} 属于时为 true；参数无效或地址族不同时为 false。
 */
export function contains(address, cidr) {
	let host = iptoarr(address), range = parseCIDR(cidr);
	if (!host || index(address, chr(0)) >= 0 || !range || length(host) != length(range.bytes)) {
		return false;
	}
	let bits = range.prefix;
	for (let i = 0; i < length(host) && bits > 0; i++, bits -= 8) {
		let mask = (0xff << (8 - min(bits, 8))) & 0xff;
		if ((host[i] & mask) != (range.bytes[i] & mask)) {
			return false;
		}
	}
	return true;
};

/**
 * 处理地址解析、端口检查和连接探测的数据请求。
 * @returns {null} 结果写入 stdout，失败时输出 JSON 错误并退出。
 */
export function main() { run(ARGV,
    /** @param {string[]} args */
    args => {
    let action = shift(args);
    if (action == 'iptype') {
        let range = parseCIDR(args[0]);
        if (!range) {
            exit(1);
        }
        return `${range.family}\n`;
    }
    if (action == 'request') {
        return request(args[0], args[1], args[2]);
    }
    if (action == 'report' || action == 'ping-report') {
        let response = { stdout: fs.stdin.read('all'), code: int(args[0]) };
        return action == 'report' ? curlReport(response, args[1] || '') : pingReport(response, args[1] || '');
    }
    die('unknown network data action');
}, true);
};
