import * as fs from 'fs';

/**
 * 使用指定参数渲染 ucode 模板，并补充模板错误位置。
 * @param {string} path 模板文件的绝对路径。
 * @param {object} scope 通用模板命名空间；字段由具体模板决定，调用方只传入已校验值。
 * @returns {string} 渲染后的文本；失败时抛出带模板路径的错误。
 */
export function renderTemplate(path, scope) {
	try {
		let output = render(path, scope);
		if (type(output) != 'string') {
			die('template did not return text');
		}
		return output;
	}
	catch (e) { die(`template "${path}": ${e.message}`); }
};

/**
 * 将一个参数转义成安全的 Shell 单引号形式。
 * @returns {string} 带外围单引号的参数字符串。
 */
export function quote(value) { return "'" + replace(`${value}`, "'", "'\\''") + "'"; };
/**
 * 将参数数组逐项转义，拼成 Shell 命令文本。
 * @param {array} args 作为独立 argv 引用的参数数组。
 * @returns {string} 命令字符串；此处不执行命令。
 */
export function command(args) { return join(' ', map(args, quote)); };
/**
 * 将规则文本拆成有效行，去掉空行和注释。
 * @param {string|null} text
 * @returns {string[]} 修剪首尾空白的行数组，保持原顺序。
 */
export function lines(text) {
	let result = [];
	for (let line in split(text || '', '\n')) {
		line = trim(line);
		if (line && substr(line, 0, 1) != '#' && substr(line, 0, 1) != '!') {
			push(result, line);
		}
	}
	return result;
};
/**
 * 创建目录及缺失的父目录。
 * @param {string|null} path 路径解析失败返回 null；拒绝无效目录。
 * @param {integer} [mode]
 * @returns {null} 无业务返回值；路径无效或创建失败时抛错。
 */
export function mkdir(path, mode) {
	if (type(path) != 'string' || !length(path)) {
		die('directory path is empty or invalid');
	}
	if (fs.stat(path)?.type == 'directory') {
		return;
	}
	let parent = fs.dirname(path);
	if (parent != path && parent != '.') {
		mkdir(parent, mode);
	}
	if (!fs.mkdir(path, mode || 0o755) && fs.stat(path)?.type != 'directory') {
		die(`cannot create ${path}: ${fs.error()}`);
	}
};
let serial = 0;
/**
 * 生成目标文件旁的唯一暂存路径。
 * @param {string} path
 * @returns {string} 包含当前 PID 和递增序号的路径；不创建文件。
 */
export function temporary(path) { return `${path}.new-${fs.readlink('/proc/self')}-${++serial}`; };
/**
 * 先完整写入临时文件，再原子替换目标文件。
 * @param {string} path
 * @param {string} data
 * @param {integer} [mode]
 * @returns {null} 无业务返回值；失败时清理临时文件并抛错。
 */
export function atomic(path, data, mode) {
	mkdir(fs.dirname(path));
	let temp = temporary(path), file = fs.open(temp, 'wx');
	if (!file) {
		die(`cannot create ${temp}: ${fs.error()}`);
	}
	try {
		if (!fs.chmod(temp, mode || 0o600)) {
			die(`cannot chmod ${temp}`);
		}
		if (file.write(data) != length(data) || !file.flush()) {
			die(`cannot write ${temp}`);
		}
		file.close();
		if (!fs.rename(temp, path)) {
			die(`cannot replace ${path}: ${fs.error()}`);
		}
	}
	catch (e) { file.close(); fs.unlink(temp); die(e.message); }
};

/**
 * 读取完整文件文本，读取失败时报告错误。
 * @param {string|null} path
 * @returns {string} 原始文本，保留空白和换行。
 */
export function text(path) {
    if (type(path) != 'string') {
        die('missing input path');
    }
    let data = fs.readfile(path);
    if (type(data) != 'string') {
        die(`cannot read ${path}`);
    }
    return data;
};
