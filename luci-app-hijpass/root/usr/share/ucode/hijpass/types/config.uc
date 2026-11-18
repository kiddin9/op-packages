// 共享字段视图与转换声明；完整原始 section 的父子类型位于 sections.uc。

/**
 * 节点文件标识：.name 为 UCI section ID，name 为可选的节点名称。
 * @typedef {{
 *   '.name': string,
 *   name: string|null
 * }} NodeIdentity
 */

/**
 * 日志配置：.type 为 UCI section 类型，log_enabled 为可选的日志开关。
 * 节点日志必须提供 .name，可选 name；主日志和分流日志不需要节点标识。
 * @typedef {{
 *   '.type': string,
 *   '.name': string|null,
 *   name: string|null,
 *   log_enabled: string|null
 * }} LogSource
 */

/**
 * 字段声明依次为转换种类、缺失值默认值、可选整数上限；duration 的结果仍是字符串。
 * @typedef {[string, string|string[]|integer|double|boolean|null, integer?]} FieldDeclaration
 */

/**
 * @typedef {{
 *   [field: string]: FieldDeclaration
 * }} FieldDeclarations
 */

/**
 * @typedef {{
 *   [field: string]: string|string[]|integer|double|boolean|null
 * }} DecodedValues
 */
