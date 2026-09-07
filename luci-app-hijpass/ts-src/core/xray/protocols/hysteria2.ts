import type { ProxyNode } from '../../../module/luci'
import { Hysteria2Config } from '../../../module/luci'
import type { Outbound, TlsObject } from '../models'
import { xrayRegistry, type XrayProtocol } from './protocol'

interface HysteriaSettings {
    version: 2
    auth: string
    udpIdleTimeout?: number
}

interface Hysteria2StreamSettings {
    network: 'hysteria'
    security: 'tls'
    tlsSettings: TlsObject
    hysteriaSettings: HysteriaSettings
    finalmask?: {
        quicParams: {
            brutalUp?: string
            brutalDown?: string
        }
    }
}

export class Hysteria2Outbound implements Outbound {
    settings: { version: 2; address: string; port: number }
    protocol: string
    tag: string
    streamSettings: Hysteria2StreamSettings

    constructor(
        address: string,
        port: number,
        tag: string,
        password: string,
        serverName: string,
        udpIdleTimeout?: number,
        brutalUp?: string,
        brutalDown?: string
    ) {
        this.protocol = 'hysteria'
        this.tag = tag
        this.settings = { version: 2, address, port }
        this.streamSettings = {
            network: 'hysteria',
            security: 'tls',
            tlsSettings: { serverName, alpn: ['h3'] },
            hysteriaSettings: {
                version: 2,
                auth: password,
                ...(udpIdleTimeout !== undefined ? { udpIdleTimeout } : {})
            },
            ...((brutalUp || brutalDown) ? {
                finalmask: {
                    quicParams: {
                        ...(brutalUp ? { brutalUp } : {}),
                        ...(brutalDown ? { brutalDown } : {})
                    }
                }
            } : {})
        }
    }
}

function formatBrutalMbps(value: string | undefined): string | undefined {
    const mbps = (value || '').trim()
    if (!mbps) return undefined
    return mbps === '0' ? '0' : mbps + ' mbps'
}

const hysteria2Protocol: XrayProtocol = {
    type: 'hysteria2',
    build(config: ProxyNode): Outbound {
        const c = config as Hysteria2Config
        const udpIdleTimeout = c.udp_idle_timeout ? Number(c.udp_idle_timeout) : undefined
        const brutalUp = formatBrutalMbps(c.up_mbps)
        const brutalDown = formatBrutalMbps(c.down_mbps)
        return new Hysteria2Outbound(
            c.server,
            Number(c.server_port),
            c.name,
            c.password || '',
            c.tls_server_name || c.server,
            udpIdleTimeout,
            brutalUp,
            brutalDown
        )
    }
}

xrayRegistry.register(hysteria2Protocol)
