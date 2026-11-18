/** @typedef {import('../types/sections.uc').UciSection} UciSection */
import { cursor } from 'uci';

// 使用原生 libuci 读取配置；解析、匿名 section 和 list 都由原生模块处理。
// 返回 .name/.type/.index 元数据及原始字符串/list，业务转换交给 config 模块。
/**
 * 通过原生 UCI 库读取配置，并保留 section 顺序。
 * @param {string} [packageName] UCI 包名，默认 hijpass。
 * @param {string} [directory] 配置目录，默认 /etc/config。
 * @returns {UciSection[]} 原始 section 数组，含 .name/.type/.index 元数据。
 */
export function read(packageName, directory) {
	packageName ||= 'hijpass';
	let ctx = cursor(directory);
	if (!ctx) {
		die('cannot create UCI cursor');
	}
	let sections = [];
	if (!ctx.load(packageName)) {
		die(`cannot load UCI ${packageName}: ${ctx.error()}`);
	}
	ctx.foreach(packageName, null, section => push(sections, section));
	return sections;
};
