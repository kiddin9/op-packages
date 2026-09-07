import type { ProxyNode } from '../../../module/luci'
import type { Outbound } from '../models'

export interface XrayProtocol {
    readonly type: string
    build(config: ProxyNode): Outbound
}

export class XrayProtocolRegistry {
    private readonly protocols = new Map<string, XrayProtocol>()

    register(p: XrayProtocol): void {
        this.protocols.set(p.type, p)
    }

    build(type: string, config: ProxyNode): Outbound {
        const p = this.protocols.get(type)
        if (!p) throw new Error(`Unsupported xray protocol: ${type}`)
        return p.build(config)
    }
}

export const xrayRegistry = new XrayProtocolRegistry()
