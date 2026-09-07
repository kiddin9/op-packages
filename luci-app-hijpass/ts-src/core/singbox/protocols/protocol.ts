import type { ProxyNode } from '../../../module/luci'
import type { Outbound } from '../models'

export interface SingBoxProtocol {
    readonly type: string
    build(config: ProxyNode): Outbound
}

export class SingBoxProtocolRegistry {
    private readonly protocols = new Map<string, SingBoxProtocol>()

    register(p: SingBoxProtocol): void {
        this.protocols.set(p.type, p)
    }

    build(type: string, config: ProxyNode): Outbound {
        const p = this.protocols.get(type)
        if (!p) throw new Error(`Unsupported sing-box protocol: ${type}`)
        return p.build(config)
    }
}

export const singboxRegistry = new SingBoxProtocolRegistry()
