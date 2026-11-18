#!/usr/bin/ucode -S
/** @typedef {import('../../share/ucode/hijpass/types/network.uc').CommandResult} CommandResult */
import * as fs from 'fs';
import { text } from 'hijpass.common';
import { run } from 'hijpass.command.runtime';

/**
 * 读取 Shell 保存的输出文件，组装统一命令结果。
 * @param {string} directory Shell 采集的输出目录。
 * @param {integer} code 命令退出码。
 * @returns {CommandResult} {code, stdout, stderr}；保留真实退出码，输出只移除末尾换行。
 */
function commandOutput(directory, code) {
    // 保持原 Shell 命令替换的行为：只移除末尾换行，不修剪其它空白。
    return {
        code,
        stdout: rtrim(text(directory + '/stdout'), '\n'),
        stderr: rtrim(text(directory + '/stderr'), '\n'),
    };
}

// Shell 只传目录、退出码或短错误；大文本由 ucode 直接读取并编码为 JSON。
run(ARGV,
    /** @param {string[]} args */
    args => {
    let action = shift(args);
    if (action == 'error' || action == 'error-file') {
        let message = action == 'error-file' ? rtrim(text(args[0]), '\n') : args[0];
        return { success: false, error: message || 'operation failed' };
    }
    if (action == 'output' || action == 'job') {
        let directory = args[0];
        if (type(directory) != 'string') {
            die('missing result directory');
        }
        if (action == 'job' && !fs.stat(directory + '/exit')) {
            let progress;
            try { progress = json(fs.readfile(directory + '/progress') || '{}'); }
            catch (e) { progress = {}; }
            if (type(progress) != 'object') progress = {};
            let bytes = progress.phase == 'download' && progress.file ? fs.stat(progress.file)?.size : null;
            return { running: true, progress: { phase: progress.phase || 'prepare',
                resource: progress.resource || '', attempt: progress.attempt || 0, bytes } };
        }
        let code = int(action == 'job' ? text(directory + '/exit') : args[1]);
        if (type(code) != 'int' || code < 0 || code > 255) {
            die('invalid command exit code');
        }
        let output = commandOutput(directory, code);
        return action == 'job' ? { running: false, ...output } : output;
    }
    die('unknown result action');
}, true);
