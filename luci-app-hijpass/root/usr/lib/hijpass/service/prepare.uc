/** @typedef {import('../../../share/ucode/hijpass/types/service.uc').ServiceSettings} ServiceSettings */
/** @typedef {import('../../../share/ucode/hijpass/types/service.uc').ConfigFile} ConfigFile */
/** @typedef {import('../../../share/ucode/hijpass/types/core.uc').GeneratedConfigs} GeneratedConfigs */
/** @typedef {import('../../../share/ucode/hijpass/types/service.uc').ServiceInstance} ServiceInstance */
/** @typedef {import('../../../share/ucode/hijpass/types/sections.uc').UciSection} UciSection */
/** @typedef {import('../../../share/ucode/hijpass/types/sections.uc').HijpassSection} HijpassSection */
/** @typedef {import('../../../share/ucode/hijpass/types/sections.uc').HijserverSection} HijserverSection */
/** @typedef {import('../../../share/ucode/hijpass/types/proxy-sections.uc').ProxyNodeSection} ProxyNodeSection */
/** @typedef {import('../../../share/ucode/hijpass/types/sections.uc').ShuntSection} ShuntSection */
import { read } from 'hijpass.uci.read';
import * as fs from 'fs';
import { FILES, nodeConfig, logPath } from 'hijpass.config.paths';
import { findHijpassSection, findHijserverSection, findShuntSection, filterProxyNodeSections, filterServerNodeSections } from 'hijpass.config.sections';
import { list } from 'hijpass.config.values';
import { generate } from 'hijpass.config.generate';
import { generate as generateServers, options as serverOptions } from 'hijpass.server.generate';
import { CORE, core, CONFIG_TYPE, configType } from 'hijpass.config.protocol.proxy';
import { resolve } from '../network/network.uc';
import { atomic, command, temporary, renderTemplate } from 'hijpass.common';
import { run } from 'hijpass.command.runtime';
import { prepare as prepareDNS } from './dns.uc';
import { logger, configuredLogger } from '../maintenance/logs.uc';

// 裸占位符和完整的单/双引号占位符统一引用一次；周围语法仍由 Shell 解析。
function configCommand(source, path) {
    return replace(source, /'\{conf_path\}'|"\{conf_path\}"|\{conf_path\}/g, () => command([path]));
}

/** @typedef {import('../../../share/ucode/hijpass/types/service.uc').ServicePlan} ServicePlan */
// Instance 为 procd 的输入：id/name（标识），command（argv），env（KEY=VALUE 数组），
// user（进程用户），log（文件路径或空），shunt（是否设置核心/no-file 资源限制）。
// ServicePlan 为 {instances:[Instance]}；所有业务准备完成后才交给 Shell procd 桥接层。
/**
 * 整理客户端节点和分流服务的 procd 启动计划。
 * @param {UciSection[]} sections
 * @returns {ServicePlan} {instances}；服务禁用时 instances 为空数组。
 */
export function plan(sections) {
	let global = findHijpassSection(sections), instances = [];
	if (!global || global.enabled != '1') {
		return { instances };
	}
	/**
	 * 组装单个服务实例的命令、环境和日志设置。
	 * @param {ProxyNodeSection|ShuntSection} section
	 * @param {string} name
	 * @param {string[]} args
	 * @param {boolean|null} shunt
	 * @param {string[]|null} check 标准核心的配置检查命令；自定义命令不检查。
	 * @returns {ServiceInstance} procd 实例对象，含 command、env、user、log 等字段。
	 */
	function instance(section, name, args, shunt, check) {
		let env = list(section.procd_env);
		for (let entry in env) {
			if (!match(entry, /^[A-Za-z_][A-Za-z0-9_]*=/)) {
				die('invalid procd_env');
			}
		}
		if (shunt) {
			push(env, 'XRAY_LOCATION_ASSET=/usr/share/v2ray');
		}
		return {
			id: section['.name'], name, command: args, check: check || [], env, shunt: !!shunt,
			user: section.nest_proxy == '1' ? 'root' : 'hijpass', log: logPath(section),
		};
	}
	for (let section in filterProxyNodeSections(sections)) {
		if (section.enabled != '1') {
			continue;
		}
		let name = section.name || section['.name'];
		let path = nodeConfig(section);
		let args, check = [];
		if (configType(section.config_type) == CONFIG_TYPE.custom) {
			if (!trim(section.command || '')) {
				die(`custom node "${name}" has no command`);
			}
			// 自定义节点的 command 本身是用户填写的 Shell 命令；配置路径仍进行引用。
			args = ['/bin/sh', '-c', configCommand(section.command, path)];
		}
		else {
			let engine = core(section.core);
			if (engine == CORE.xray) {
				args = ['xray', '-c', path];
				check = ['xray', 'run', '-test', '-c', path];
			}
			else if (engine == CORE.singbox) {
				args = ['sing-box', '-c', path, 'run'];
				check = ['sing-box', 'check', '-c', path];
			}
			else {
				die(`unsupported core "${engine}"`);
			}
		}
		push(instances, instance(section, name, args, false, check));
	}
	let shunt = findShuntSection(sections);
	if (shunt && shunt.enabled != '0' && shunt.type) {
		let engine = core(shunt.type), path = FILES.shunt_conf;
		if (engine != CORE.xray && engine != CORE.singbox) {
			die('unsupported shunt core');
		}
		push(instances, instance(shunt, 'shunt', engine == CORE.xray ? ['xray', '-c', path] : ['sing-box', 'run', '-c', path], true,
            engine == CORE.xray ? ['xray', 'run', '-test', '-c', path] : ['sing-box', 'check', '-c', path]));
	}
	return { instances };
};

// ConfigFile：path 为目标路径，data 为已完整生成和解析上游域名的 JSON 文本。
/**
 * 解析链式代理的上游域名，生成待写入的文件内容；不修改 generated 或写文件。
 * @param {UciSection[]} sections
 * @param {GeneratedConfigs} generated
 * @returns {ConfigFile[]} 待写入的 {path, data} 数组；域名解析或转换失败时抛错。
 */
export function prepareConfigFiles(sections, generated) {
	let files = [];
	for (let section in filterProxyNodeSections(sections)) {
		let config = generated.nodes[section['.name']];
		if (!config) {
			continue;
		}
		if (section.upstream_proxy_node && section.server && !iptoarr(section.server)) {
			let outbounds = [...config.outbounds];
			let address = resolve(section.server), outbound = { ...outbounds[0] };
			if (outbound.server) {
				outbound.server = address;
			}
			else if (outbound.settings?.address) {
				outbound.settings = { ...outbound.settings, address };
			}
			else {
				die('unsupported proxy server field');
			}
			outbounds[0] = outbound;
			config = { ...config, outbounds };
		}
		push(files, { path: nodeConfig(section), data: sprintf('%.2J\n', config) });
	}
	if (generated.shunt) {
		push(files, { path: FILES.shunt_conf, data: sprintf('%.2J\n', generated.shunt) });
	}
	return files;
};

/**
 * 将全部已准备的文件先暂存，再替换目标文件；后续提交失败时恢复已替换文件。
 * @param {ConfigFile[]} files prepareConfigFiles() 返回的 {path, data} 数组。
 * @returns {ConfigFile[]} 已写入的文件数组。
 */
export function writeConfigs(files) {
	let staged = [], committed = [];
	try {
		for (let file in files) {
			let temp = temporary(file.path), original = fs.readfile(file.path), mode = fs.stat(file.path)?.mode;
			atomic(temp, file.data);
			push(staged, { path: file.path, temp, original, mode });
		}
		for (let file in staged) {
			if (!fs.rename(file.temp, file.path)) {
				die(`cannot replace ${file.path}`);
			}
			push(committed, file);
		}
	}
	catch (e) {
		let rollbackErrors = [];
		for (let file in reverse(committed)) {
			try {
				if (file.original == null) {
					if (!fs.unlink(file.path)) die(`cannot remove ${file.path}`);
				}
				else atomic(file.path, file.original, file.mode);
			}
			catch (rollbackError) { push(rollbackErrors, rollbackError.message); }
		}
		for (let file in staged) fs.unlink(file.temp);
		die(e.message + (length(rollbackErrors) ? '; rollback incomplete: ' + join('; ', rollbackErrors) : '; previous files restored'));
	}
	return files;
};

/**
 * 服务启动时读取已提交配置，记录生成和文件写入结果。
 * @param {UciSection[]} sections
 * @returns {GeneratedConfigs}
 */
export function generateAndWriteConfigs(sections) {
	let log = logger(sections), started = time();
	log('INFO', 'Generating proxy configurations');
	try {
		let generated = generate(sections), files = prepareConfigFiles(sections, generated);
		writeConfigs(files);
		for (let file in files) log('DEBUG', `Written ${file.path}`);
		log('INFO', `Wrote ${length(files)} proxy core JSON configuration files in ${time() - started}s`);
		return generated;
	}
	catch (e) {
		log('ERROR', `Proxy configuration generation or write failed: ${e.message}`);
		die(e.message);
	}
};
/** @typedef {import('../../../share/ucode/hijpass/types/service.uc').ServerPlan} ServerPlan */
/**
 * 整理标准核心启动参数及各协议需要开放的端口。
 * @param {UciSection[]} sections
 * @returns {ServerPlan}
 */
export function serverPlan(sections) {
    let instances = [], ports = { tcp: [], udp: [] };
    if (findHijserverSection(sections)?.enabled != '1') return { instances, ports };
    for (let section in filterServerNodeSections(sections)) {
        if (section.enabled != '1') continue;
        let node = serverOptions(section), path = nodeConfig(section, true);
        push(instances, {
            id: section['.name'], name: node.name,
            command: node.core == 'xray' ? ['xray', 'run', '-c', path] : ['sing-box', 'run', '-c', path],
            check: node.core == 'xray' ? ['xray', 'run', '-test', '-c', path] : ['sing-box', 'check', '-c', path],
            env: [], user: 'root', shunt: false, log: logPath(section, true),
        });
        if (section.allow_firewall == '1') {
            if (node.type != 'hysteria2') push(ports.tcp, node.listen_port);
            if (node.type != 'vless') push(ports.udp, node.listen_port);
        }
    }
    return { instances, ports: { tcp: uniq(ports.tcp), udp: uniq(ports.udp) } };
};
/**
 * 生成服务端端口放行规则，没有端口时删除旧规则文件。
 * @param {UciSection[]} sections
 * @param {string} tablePath nft 表规则文件路径。
 * @param {string} chainPath WAN 输入链引用文件路径。
 * @returns {null} 无业务返回值，只更新 nft include 文件。
 */
function writeServerRules(sections, tablePath, chainPath) {
	let output = serverPlan(sections);
	// 只开放明确选中的端口；没有端口时删除旧 include，避免旧服务端仍对 WAN 开放。
	if (length(output.ports.tcp) || length(output.ports.udp)) {
		atomic(tablePath, renderTemplate('/usr/lib/hijpass/service/server.ut', { ports: output.ports }), 0o644);
		atomic(chainPath, 'jump hijserver comment "hijserver rule"\n', 0o644);
	}
	else {
		for (let path in [tablePath, chainPath]) {
			if (fs.lstat(path) && !fs.unlink(path)) die(`cannot remove ${path}`);
		}
	}
};

// ServiceSettings 是执行层需要的业务值；不包含可执行的通用动作列表。
// enabled 控制配置准备，geo_convert 控制 Geo 准备，log_paths 为需要准备目录的日志位置。
/**
 * 为 Shell 执行脚本整理服务开关和维护参数。
 * @param {UciSection[]} config
 * @param {boolean} server
 * @returns {ServiceSettings} 含 enabled、geo_convert 及 log_paths 的对象。
 */
function settings(config, server) {
    /** @type {HijpassSection|HijserverSection|null} */
    let global = server ? findHijserverSection(config) : findHijpassSection(config);
    let shunt = findShuntSection(config);
    let convert = false;
    if (!server && shunt) {
        convert = shunt.enabled != '0' && core(shunt.type) == CORE.singbox && shunt.ruleset_convert == '1';
    }
    return { enabled: global?.enabled == '1',
        geo_convert: convert,
        log_paths: filter(map(config, item => logPath(item, server)), path => !!path) };
};
/**
 * 为服务准备配置、进程参数和端口规则。
 * @returns {null} 查询结果写入 stdout；写入类动作直接更新对应文件。
 */
export function main() { run(ARGV,
    /**
     * @param {string[]} args
     * @param {string|null} configDirectory
     */
    function(args, configDirectory) {
    let server = args[0] == 'server';
    if (server) {
        shift(args);
    }
    let config = read(server ? 'hijserver' : 'hijpass', configDirectory), action = shift(args);
    if (action == 'settings') {
        return settings(config, server);
    }
    if (action == 'configs') {
        if (server) {
            let files = generateServers(config);
            writeConfigs(files);
            configuredLogger(configDirectory)('INFO', `Wrote ${length(files)} hijserver core JSON configuration files`);
        }
        else if (findHijpassSection(config)?.enabled == '1') {
            // 先生成进程描述，确认自定义命令、环境变量和文件名有效，再替换配置。
            plan(config);
            generateAndWriteConfigs(config);
        }
        return;
    }
    if (action == 'plan') {
        return server ? serverPlan(config) : plan(config);
    }
    if (action == 'prepare') {
        if (server) {
            let result = serverPlan(config);
            configuredLogger(configDirectory)('INFO', `Prepared ${length(result.instances)} hijserver process instance(s)`);
            return result;
        }
        let result = plan(config);
        if (findHijpassSection(config)?.enabled == '1') {
            let dns = prepareDNS(config, configDirectory);
            if (dns) {
                push(result.instances, dns);
            }
        }
        logger(config)('INFO', `Prepared ${length(result.instances)} hijpass process instance(s)`);
        return result;
    }
    if (action == 'server-files') {
        if (length(args) != 2 || !args[0] || !args[1]) die('server-files requires table and chain paths');
        return writeServerRules(config, args[0], args[1]);
    }
    die('unknown service data action');
});
};
