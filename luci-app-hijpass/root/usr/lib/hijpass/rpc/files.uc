/** @typedef {import('../../../share/ucode/hijpass/types/rpc.uc').LogList} LogList */
/** @typedef {import('../../../share/ucode/hijpass/types/rpc.uc').LogResponse} LogResponse */
/** @typedef {import('../../../share/ucode/hijpass/types/rpc.uc').LogRequest} LogRequest */
import * as fs from 'fs';
import { read } from 'hijpass.uci.read';
import { logPath } from 'hijpass.config.paths';

/**
 * 校验前端传入的 UCI section ID，拒绝非法字符。
 * @param {string|null} value
 * @returns {string} 有效的 section ID；无效时抛错。
 */
function identifier(value) {
    if (type(value) != 'string') {
        die('invalid section ID');
    }
    if (!match(value, /^[A-Za-z0-9_-]+$/)) {
        die('invalid section ID');
    }
    return value;
}
// Log：id 为 package:section 的业务标识；客户端不能提交任意日志路径。
/**
 * 列出可供前端查看的日志，不暴露文件路径。
 * @returns {LogList} {logs}，每项含 id、kind 和显示名称 name。
 */
export function logs() {
    let result = [];
    for (let packageName in ['hijpass', 'hijserver']) {
        for (let section in read(packageName)) {
            if (!logPath(section, packageName == 'hijserver')) {
                continue;
            }
        let kind = 'main';
        if (section['.type'] == 'proxy_node') {
            kind = 'proxy';
        }
        else if (section['.type'] == 'server_node') {
            kind = 'server';
        }
        else if (section['.type'] == 'shunt') {
            kind = 'shunt';
        }
            push(result, { id: `${packageName}:${section['.name']}`, kind, name: section.name || section['.name'] });
        }
    }
    return { logs: result };
};
/**
 * 按日志 ID 读取尾部内容、下载全文或清空文件。
 * @param {LogRequest} request
 * @returns {LogResponse} 读取返回 {content}，下载返回 {content, name}，清空返回 {ok: true}。
 */
export function log(request) {
    let parts = split(request.id, ':'), packageName = parts[0];
    if (length(parts) != 2 || index(['hijpass', 'hijserver'], packageName) < 0) {
        die('invalid log ID');
    }
    let id = identifier(parts[1]), section = filter(read(packageName), item => item['.name'] == id)[0];
    let path = section ? logPath(section, packageName == 'hijserver') : '';
    if (!path) {
        die('logging is disabled');
    }
    if (request.action == 'clear') {
        if (fs.writefile(path, '') == null) {
            die('cannot clear log');
        }
        return { ok: true };
    }
    let count = 0;
    if (request.action == 'read') {
        if (type(request.lines) != 'string' || !match(request.lines, /^[0-9]+$/)) {
            die('invalid log request');
        }
        count = int(request.lines);
        if (count < 1 || count > 1000) {
            die('log line count must be between 1 and 1000');
        }
    }
    else if (request.action != 'download') {
        die('invalid log request');
    }
    let info = fs.stat(path);
    if (!info) {
        let error = fs.error();
        // 节点尚未启动时没有日志文件；其他打开失败仍返回错误。
        if (request.action == 'read' && error == 'No such file or directory') return { content: '' };
        die(`cannot open log: ${error}`);
    }
    if (info.type != 'file') die('log is not a regular file');
    let file = fs.open(path, 'r');
    if (!file) die('cannot open log');
    try {
        if (request.action == 'download') {
            let content = file.read('all') || ''; file.close();
            return { content, name: fs.basename(path) };
        }
        // 环形缓冲只保留尾部所需的行数，避免为预览加载整份日志。
        let buffer = [], total = 0, line;
        while ((line = file.read('line')) != null) buffer[total++ % count] = line;
        let content = '';
        for (let i = max(0, total - count); i < total; i++) content += buffer[i % count];
        file.close();
        return { content };
    }
    catch (e) { file.close(); die(e.message); }
};
