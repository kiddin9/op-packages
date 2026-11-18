/** @typedef {import('../../../share/ucode/hijpass/types/sections.uc').UciSection} UciSection */
/** @typedef {import('../../../share/ucode/hijpass/types/logging.uc').LogFrame} LogFrame */
import { read } from 'hijpass.uci.read';
import * as fs from 'fs';
import { logPath } from 'hijpass.config.paths';
import { findHijpassSection } from 'hijpass.config.sections';
import { mkdir, command } from 'hijpass.common';
import { run } from 'hijpass.command.runtime';

/**
 * 外部命令输出只保留有限诊断文本；URL 和常见凭据字段不进入主日志。
 * @param {string} message
 * @returns {string}
 */
function safeMessage(message) {
	message = replace(message, /https?:\/\/[^[:space:]<>"']+/gi, '[URL redacted]');
	message = replace(message, /((password|passwd|token|secret|authorization|uuid)["']?[ \t]*[:=][ \t]*)[^\n]+/gi, '$1[redacted]');
	message = replace(message, /[[:cntrl:]]/g, character => character == '\n' || character == '\t' ? character : '');
	return length(message) > 8192 ? substr(message, 0, 8192) + '\n[truncated]' : message;
}

/**
 * 仅 DEBUG 模式采集调用栈，跳过日志模块自身的包装层。
 * @returns {string|null}
 */
function callerLocation() {
	let ownFile = sourcepath();
	try { die('capture log location'); }
	catch (e) {
		/** @type {LogFrame[]} */
		let frames = e.stacktrace;
		for (let frame in frames) {
			if (frame.filename && frame.filename != ownFile) {
				return frame.line ? `${frame.filename}:${frame.line}` : frame.filename;
			}
		}
	}
	return null;
}

// Logger 返回一个 (level, message) 函数，保留应用日志级别与多行排版。
// 主日志位置由后端确定，global.log_level 为 DEBUG/INFO/WARN/ERROR。
/**
 * 根据配置创建主日志写入函数，并按日志级别过滤消息。
 * @param {UciSection[]} sections
 * @returns {function} 接受 (level, message) 的日志函数。
 */
export function logger(sections) {
	let global = findHijpassSection(sections), path = logPath({ '.type': 'hijpass' });
	const levels = { DEBUG: 1, INFO: 2, WARN: 3, ERROR: 4 };
	let debug = uc(global?.log_level || 'INFO') == 'DEBUG';
	return (level, message, source) => {
		level = uc(level) || 'INFO';
		if (!exists(levels, level)) level = 'INFO';
		if ((levels[level] || 2) < (levels[uc(global?.log_level || 'INFO')] || 2)) {
			return;
		}
		message = safeMessage(message);
		let location = '';
		if (debug) {
			source = source || callerLocation();
			// 为完整脚本路径保留固定宽度，并与正文保持间隔。
			location = sprintf('%-64s  ', source || '');
		}
		let file;
		try {
			mkdir(fs.dirname(path));
			file = fs.open(path, 'a');
			if (!file) die(`cannot open log ${path}`);
			let date = localtime(time());
			if (!date) die('cannot format log timestamp');
			let stamp = sprintf('%04d-%02d-%02d %02d:%02d:%02d', date.year, date.mon, date.mday, date.hour, date.min, date.sec);
			let prefix = sprintf('[%s]   %-8s%s', stamp, level, location);
			let indent = replace(prefix, /./g, ' ');
			let entry = prefix + replace(message, '\n', '\n' + indent) + '\n';
			if (file.write(entry) != length(entry) || !file.flush()) die('cannot write log');
			file.close();
		}
		catch (e) {
			if (file) file.close();
			// 不新增 ucode 模块依赖；只有文件日志故障时才调用系统 logger。
			try {
				let priority = { DEBUG: 'debug', INFO: 'info', WARN: 'warning', ERROR: 'err' };
				if (system(command(['logger', '-t', 'hijpass', '-p', `daemon.${priority[level]}`, '--', `${level} ${message}\nFile log unavailable: ${e.message}`]) + ' >/dev/null 2>&1', 1000) == 0) return;
			}
			catch (fallbackError) { }
			warn(`hijpass log unavailable: ${level} ${message}\n`);
		}
	};
};

/**
 * 读取日志级别；安装早期或配置损坏时仍使用默认级别记录错误。
 * @param {string|null} [configDirectory]
 * @returns {function}
 */
export function configuredLogger(configDirectory) {
	let config = [];
	try { config = read('hijpass', configDirectory); }
	catch (e) { }
	return logger(config);
};

/**
 * 在执行边界逐条规范化命令诊断；成功时的普通输出只写 DEBUG，保留警告和失败详情。
 * @param {function} log
 * @param {string} source
 * @param {string} phase
 * @param {string} output
 * @param {integer} code
 * @returns {null}
 */
function logCommandOutput(log, source, phase, output, code) {
	for (let line in split(output, '\n')) {
		if (!trim(line)) continue;
		let prefix = match(line, /^[ \t]*\[([IWE])\][ \t]*(.*)$/);
		let level = code ? 'ERROR' : 'DEBUG';
		if (prefix) {
			level = { I: code ? 'ERROR' : 'DEBUG', W: 'WARN', E: 'ERROR' }[prefix[1]];
			line = prefix[2];
		}
		else if (match(line, /^[ \t]*(warn|warning)[ :]/i)) level = 'WARN';
		log(level, `${phase}: ${line}`, source);
	}
	if (code) log('ERROR', `${phase} failed: exit=${code}`, source);
	else log('DEBUG', `${phase}: exit=0`, source);
}
/**
 * 裁剪过长日志，只保留最后 30000 行。
 * @param {string} path
 * @returns {null} 无业务返回值；文件打不开或未超限时跳过。
 */
function trimLog(path) {
	let file = fs.open(path, 'r');
	if (!file) {
		return;
	}
	let buffer = [], count = 0, line;
	// 环形缓冲只保留最后 30000 行，日志很大时也不会完整载入内存。
	while ((line = file.read('line')) != null) {
		buffer[count % 30000] = line;
		count++;
	}
	file.close();
	if (count <= 30000) {
		return;
	}
	file = fs.open(path, 'w');
	if (!file) {
		die(`cannot trim ${path}`);
	}
	for (let i = count - 30000; i < count; i++) file.write(buffer[i % 30000]);
	file.close();
}
/**
 * 清空指定日志，或裁剪当前服务的全部日志。
 * @param {UciSection[]} sections
 * @param {string} action
 * @param {string|null} [path]
 * @returns {null} 无业务返回值，直接更新日志文件。
 */
export function cleanLogs(sections, action, path) {
	if (action == 'clean') {
		if (type(path) != 'string') {
			die('missing log path');
		}
		if (fs.writefile(path, '') == null) {
			die(`cannot clear ${path}`);
		}
		return;
	}
	for (let s in sections) {
		let target = logPath(s, action == 'hijserver');
		if (target) {
			trimLog(target);
		}
	}
};

/**
 * 处理日志追加、清空和裁剪命令。
 * @returns {null} 正常执行不输出数据，错误通过 stderr 和退出码报告。
 */
export function main() { run(ARGV,
    /**
     * @param {string[]} args
     * @param {string|null} configDirectory
     */
    function(args, configDirectory) {
    let action = shift(args);
    if (action == 'append') {
        return configuredLogger(configDirectory)(args[0], join(' ', slice(args, 1)));
    }
    if (action == 'source') {
        return configuredLogger(configDirectory)(args[0], join(' ', slice(args, 2)), args[1]);
    }
    if (action == 'command') {
        let source = args[0] || '', phase = args[2] || '', code = int(args[1]);
        if (!phase || type(code) != 'int' || code < 0 || code > 255) die('invalid command log arguments');
        let file = fs.open(args[3], 'r');
        if (!file) die('cannot read command diagnostics');
        let output = file.read(8192) || '';
        if (file.read(1)) output += '\n[truncated]';
        file.close();
        return logCommandOutput(configuredLogger(configDirectory), source, phase, output, code);
    }
    if (action == 'clean') {
        return cleanLogs([], 'clean', args[0] || '');
    }
    if (action == 'hijpass' || action == 'hijserver') {
        return cleanLogs(read(action, configDirectory), action || '');
    }
    die('unknown log action');
});
};
