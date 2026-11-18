// CLI 数据边界：stdout 只返回数据，错误由 stderr/退出状态或既有 JSON 契约表达。
import * as fs from 'fs';
/**
 * 完整输出并检查缓冲刷新；输出被重定向到文件时也必须报告写入失败。
 * @param {string} output
 * @returns {null}
 */
export function writeOutput(output) {
    if (fs.stdout.write(output) != length(output) || !fs.stdout.flush()) die('cannot write command output');
};
/**
 * 统一处理命令参数、结果输出和异常退出。
 * @param {string[]} argv 解释器提供的参数；解析时使用副本。
 * @param {function} handler 接收 (args, configDirectory)，业务层显式传递配置目录。
 * @param {boolean} [jsonErrors]
 * @returns {null} handler 结果写入 stdout，字符串原样输出，其他值编码为 JSON。
 */
export function run(argv, handler, jsonErrors) {
    let args = [...argv], configDirectory;
    try {
        // 所有数据入口使用同一份可选配置目录，缺失参数在执行前失败。
        let position = index(args, '--configdir');
        if (position != null && position >= 0) {
            configDirectory = args[position + 1];
            if (!configDirectory) {
                die('missing --configdir');
            }
            splice(args, position, 2);
        }
        let result = handler(args, configDirectory);
        if (result != null) {
            let output = type(result) == 'string' ? result : sprintf('%J\n', result);
            // print() 可能只写入用户态缓冲；必须检查 flush 才能向 Shell 报告保存失败。
            writeOutput(output);
            if (type(result) == 'object' && result.success === false) {
                exit(result.exit_code || 1);
            }
        }
    }
    catch (e) {
        if (jsonErrors) {
            printf('%J\n', { success: false, error: e.message });
        }
        else {
            warn(`${e.message}\n`);
        }
        exit(1);
    }
};
