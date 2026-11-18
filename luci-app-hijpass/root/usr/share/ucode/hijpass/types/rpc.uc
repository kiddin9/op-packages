// 共享类型声明；仅用于编辑器，不创建或导出运行时对象。

/**
 * 日志 ID 为 package:section；只有 read 动作需要 lines。
 * @typedef {{
 *   id: string,
 *   action: string,
 *   lines: string|null
 * }} LogRequest
 */

/**
 * @typedef {{
 *   content: string
 * }} LogContent
 */

/**
 * @typedef {{
 *   id: string,
 *   kind: string,
 *   name: string
 * }} LogEntry
 */

/**
 * @typedef {{
 *   logs: LogEntry[]
 * }} LogList
 */

/** @typedef {(LogContent & {name: string|null})|{ok: boolean}} LogResponse */
