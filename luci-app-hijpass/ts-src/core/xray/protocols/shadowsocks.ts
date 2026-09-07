import type { ProxyNode } from '../../../module/luci'
import { ShadowsocksConfig } from '../../../module/luci'
import type { Outbound } from '../models'
import { xrayRegistry, type XrayProtocol } from './protocol'

export class ShadowsocksXrayOutbound implements Outbound {
    settings: {
        address: string
        port: number
        method: string
        password: string
        uot?: boolean
        level: number
    }
    protocol: string
    tag: string

    constructor(
        address: string,
        port: number,
        tag: string,
        method: string,
        password: string,
        uot?: boolean
    ) {
        this.protocol = 'shadowsocks'
        this.tag = tag
        this.settings = { address, port, method, password, uot: uot || undefined, level: 0 }
    }
}

const shadowsocksProtocol: XrayProtocol = {
    type: 'shadowsocks',
    build(config: ProxyNode): Outbound {
        const c = config as ShadowsocksConfig
        return new ShadowsocksXrayOutbound(
            c.server,
            Number(c.server_port),
            c.name,
            c.method,
            c.password,
            c.udp_over_tcp === '1' ? true : undefined
        )
    }
}

xrayRegistry.register(shadowsocksProtocol)
