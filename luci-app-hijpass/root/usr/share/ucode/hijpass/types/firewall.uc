// 已转换的防火墙模板参数；原始 UCI FirewallSection 位于 sections.uc。

/**
 * @typedef {{
 *   direct: string[],
 *   proxy: string[],
 *   china: string[]
 * }} FirewallAddressLists
 */

/**
 * @typedef {{
 *   proxyPort: integer,
 *   shuntPort: integer,
 *   forwardPort: integer,
 *   proxyMark: integer,
 *   shuntMark: integer,
 *   protocols: string[],
 *   wan: string[],
 *   macs: string[],
 *   excludedMacs: string[],
 *   interfaces: string[],
 *   excludedInterfaces: string[],
 *   proxyLocal: boolean,
 *   allowAll: boolean,
 *   useChnRoute: boolean,
 *   useChn: boolean,
 *   useGfw: boolean,
 *   domainSets: boolean,
 *   user: string,
 *   wanNames: string,
 *   interfaceNames: string,
 *   excludedInterfaceNames: string,
 *   ip4: FirewallAddressLists,
 *   ip6: FirewallAddressLists
 * }} FirewallOptions
 */
