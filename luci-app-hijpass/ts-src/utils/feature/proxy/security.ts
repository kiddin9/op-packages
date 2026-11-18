import { CORE_TYPE } from "../../../enum/hijpass";

/** 未保存安全选项的旧节点，保持原核心生成器的 TLS 行为。 */
export function vlessSecurity(section: {
    security?: string; core?: string; tls_reality_enabled?: string; tls_server_name?: string;
}): string {
    return section.security || (section.tls_reality_enabled === '1' ? 'reality'
        : (!section.core || section.core === CORE_TYPE.SING_BOX || section.tls_server_name ? 'tls' : 'none'));
}
