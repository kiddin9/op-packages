/** @typedef {import('../../../share/ucode/hijpass/types/release.uc').AssetPlan} AssetPlan */
/** @typedef {import('../../../share/ucode/hijpass/types/release.uc').CoreRelease} CoreRelease */
import * as fs from 'fs';
import { run } from 'hijpass.command.runtime';
// CoreRelease：tag_name 为官方版本，assets 含 name/state/browser_download_url/digest。
// 此处只校验发布元数据，归档和可执行文件的验证由 Shell 执行。
const repos = { 'sing-box': 'SagerNet/sing-box', xray: 'XTLS/Xray-core' };
/**
 * 根据核心和 CPU 架构确定下载包的平台名称。
 * @param {string} core
 * @param {string|null} machine
 * @returns {string} linux-<架构> 平台名称；不支持时抛错。
 */
export function architecture(core, machine) {
	const suffixes = {
		'sing-box': { x86_64: 'amd64', aarch64: 'arm64', arm64: 'arm64', armv7l: 'armv7', armv6l: 'armv6', mips: 'mips-softfloat', mipsle: 'mipsle-softfloat', mips64: 'mips64', mips64le: 'mips64le' },
		xray: { x86_64: '64', aarch64: 'arm64-v8a', arm64: 'arm64-v8a', armv7l: 'arm32-v7a', armv6l: 'arm32-v6', mips: 'mips32', mipsle: 'mips32le', mips64: 'mips64', mips64le: 'mips64le' },
	};
	let suffix = suffixes[core]?.[machine];
	if (!suffix) {
		die(`unsupported architecture: ${machine}`);
	}
	return 'linux-' + suffix;
};
/**
 * 解析并校验核心的官方发布信息。
 * @param {string} core
 * @param {string} response
 * @returns {CoreRelease} 发布对象，保留 tag_name 和原始 assets 列表。
 */
export function release(core, response) {
	if (!repos[core]) {
		die('unknown core');
	}
	try {
		let info = json(response);
		if (type(info) != 'object') {
			die('release response must be an object');
		}
		if (!match(info.tag_name || '', /^v?[0-9]+[.][0-9]+[.][0-9]+[A-Za-z0-9.+-]*$/)) {
			die('invalid release version');
		}
		return info;
	}
	catch (e) { die(`invalid ${core} release response: ${e.message}`); }
};
/**
 * 从发布资源中选出安装包，并校验下载地址和校验和。
 * @param {string} core
 * @param {string|null} machine
 * @param {CoreRelease} info
 * @returns {AssetPlan} 安装计划，含版本、下载地址、SHA-256、安装位置和归档格式。
 */
export function assetPlan(core, machine, info) {
	let arch = architecture(core, machine), number = replace(info.tag_name, /^v/, '');
	let candidates = core == 'xray' ? [`Xray-${arch}.zip`] : [`sing-box-${number}-${arch}-musl.tar.gz`, `sing-box-${number}-${arch}.tar.gz`];
	let asset;
	for (let name in candidates) {
		asset = filter(info.assets || [], a => a.name == name && a.state == 'uploaded')[0];
		if (asset) {
			break;
		}
	}
	if (!asset || !match(asset.digest || '', /^sha256:[a-fA-F0-9]{64}$/)) {
		die('release asset or checksum is missing');
	}
	let expectedURL = `https://github.com/${repos[core]}/releases/download/${info.tag_name}/${asset.name}`;
	if (asset.browser_download_url != expectedURL) {
		die('unexpected release asset URL');
	}

    let digest = asset.digest;
    if (type(digest) != 'string') {
        die('release checksum is missing');
    }
    return { core, version: info.tag_name, number, name: asset.name, url: expectedURL,
        digest: lc(substr(digest, 7)), destination: `/usr/bin/${core}`, archive: core == 'xray' ? 'zip' : 'tar' };
};
// AssetPlan：core/version/number/name/url/digest/destination/archive，均来自已校验的发布数据。
// Shell 根据这些业务字段下载和安装，不接收拼接好的命令字符串。
/**
 * 处理核心更新脚本的版本查询、资源选择等数据请求。
 * @returns {null} 结果写入 stdout，失败时输出 JSON 错误并退出。
 */
export function main() { run(ARGV,
    /** @param {string[]} args */
    args => {
    let action = shift(args), core = shift(args);
    if (!core || !repos[core]) {
        die('core action and name are required');
    }
    if (action == 'source') {
        return `https://api.github.com/repos/${repos[core]}/releases/latest\n`;
    }
    if (action == 'member') {
        let member = filter(split(fs.stdin.read('all'), '\n'), entry => match(entry, /^sing-box-[A-Za-z0-9.+-]+\/sing-box$/))[0];
        if (!member) {
            die('binary not found in archive');
        }
        return member + '\n';
    }
    if (action == 'version') {
        let output = fs.stdin.read('all'), m = match(output, core == 'xray' ? /Xray ([0-9]+[.][0-9]+[.][0-9]+[^ \n]*)/ : /sing-box version ([0-9]+[.][0-9]+[.][0-9]+[^ \n]*)/);
        return { core, version: m ? m[1] : 'unknown' };
    }
    if (action == 'latest' || action == 'plan') {
        let info = release(core, fs.stdin.read('all'));
        return action == 'latest' ? { core, version: info.tag_name } : assetPlan(core, args[0], info);
    }
    if (action == 'error') {
        return { success: false, error: args[0] || 'core update failed' };
    }
    if (action == 'result') {
        return { success: true, version: args[0] };
    }
    die('unknown core data action');
}, true);
};
