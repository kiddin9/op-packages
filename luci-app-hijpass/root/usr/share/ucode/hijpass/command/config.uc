import * as fs from 'fs';
import { read } from '../uci/read.uc';
import { generate, validate } from '../config/generate.uc';
import { writeOutput } from './runtime.uc';

// RPC Request：sections 为可选的 JSON 快照字符串，target 为可选的 proxy_node 或 shunt section ID。
// 未给 sections 时直接读取 /etc/config/hijpass，支持脱离 LuCI 的命令行运行。
// RPC Response：render 返回 {nodes, shunt?} 或 {config}；validate 返回 {ok:true}；
// 错误统一为 {error}，供 LuCI 展示；CLI 错误输出到 stderr 并返回非零状态。
/**
 * 读取配置命令的标准输入，并限制输入大小。
 * @returns {string} 原始文本，最多 4 MiB；读取失败或超限时抛错。
 */
function stdinText() {
	// 多读一个字节即可判断超限，避免先把任意大小的输入全部载入内存。
	let limit = 4 * 1024 * 1024, data = fs.stdin.read(limit + 1);
	if (type(data) != 'string') {
		die(`cannot read input: ${fs.error()}`);
	}
	if (length(data) > limit) {
		die('input exceeds 4 MiB');
	}
	return data;
}
/**
 * 处理配置生成和校验请求，兼容 CLI 与 RPC 调用。
 * @param {string[]} args 命令行参数；由解释器 ARGV 提供。
 * @returns {null} 结果写入 stdout；RPC 输出错误对象，CLI 错误写 stderr 并退出。
 */
export function main(args) {
	if (args[0] == 'list') {
		writeOutput(sprintf('%J\n', { render: { sections: '', target: '' }, validate: { sections: '' } }));
		return;
	}
	let rpc = args[0] == 'call';
	try {
		let method = rpc ? args[1] : args[0];
		if (method != 'render' && method != 'validate') {
			die(`unknown ${rpc ? 'method' : 'command'} "${method}"`);
		}
		let sections, target = '';
		if (rpc) {
			// 读取、解析及使用外部 JSON 都处于同一个错误边界内。
			let request = json(stdinText());
			if (type(request) != 'object') {
				die('request must be an object');
			}
			if (request.sections != null && type(request.sections) != 'string') {
				die('sections must be a string');
			}
			if (request.target != null && type(request.target) != 'string') {
				die('target must be a string');
			}
			sections = request.sections != null ? json(request.sections) : read();
			target = request.target || '';
		}
		else {
			let useStdin = false, directory;
			for (let i = 1; i < length(args); i++) {
				if (args[i] == '--stdin') {
					useStdin = true;
				}
				else if (args[i] == '--target' && args[i + 1]) {
					target = args[++i];
				}
				else if (args[i] == '--configdir' && args[i + 1]) {
					directory = args[++i];
				}
				else {
					die(`unknown argument "${args[i]}"`);
				}
			}
			sections = useStdin ? json(stdinText()) : read('hijpass', directory);
		}
		let result = method == 'validate' ? validate(sections) : generate(sections, target);
		writeOutput(sprintf('%.2J\n', rpc && target && method == 'render' ? { config: result } : result));
	}
	catch (e) {
		if (rpc) {
			writeOutput(sprintf('%J\n', { error: e.message }));
		}
		else {
			fs.stderr.write(`${e.message}\n`);
			exit(1);
		}
	}
};
