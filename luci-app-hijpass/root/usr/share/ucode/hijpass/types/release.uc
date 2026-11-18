// 共享类型声明；仅用于编辑器，不创建或导出运行时对象。

/**
 * 官方发布元数据的资源；assetPlan 会拒绝缺失或非法的 SHA-256 digest。
 * @typedef {{
 *   name: string,
 *   state: string,
 *   browser_download_url: string,
 *   digest: string|null
 * }} ReleaseAsset
 */

/**
 * @typedef {{
 *   tag_name: string,
 *   assets: ReleaseAsset[]|null
 * }} CoreRelease
 */

/**
 * 已校验的安装资源；digest 为不含 sha256: 前缀的小写十六进制字符串。
 * @typedef {{
 *   core: string,
 *   version: string,
 *   number: string,
 *   name: string,
 *   url: string,
 *   digest: string,
 *   destination: string,
 *   archive: string
 * }} AssetPlan
 */
