import type { ProxyNode } from '../../../module/luci'
import { Hysteria2Config } from '../../../module/luci'
import { TlsConfig, type Outbound } from '../models'
import { singboxRegistry, type SingBoxProtocol } from './protocol'

export class ObfsConfig {
    type: 'salamander'
    password?: string

    constructor(password: string) {
        this.type = 'salamander'
        this.password = password
    }
}

export class Hysteria2Outbound implements Outbound {
    type = 'hysteria2'
    tag: string
    server: string
    server_port: number
    password?: string
    obfs?: ObfsConfig
    up_mbps?: number
    down_mbps?: number
    server_ports?: string[]
    hop_interval?: string
    network?: string
    tls: TlsConfig

    constructor(tag: string, server: string, server_port: number, serverName: string) {
        this.tag = tag
        this.server = server
        this.server_port = server_port
        this.tls = new TlsConfig(serverName)
    }
}

const hysteria2Protocol: SingBoxProtocol = {
    type: 'hysteria2',
    build(config: ProxyNode): Outbound {
        const c = config as Hysteria2Config
        const outbound = new Hysteria2Outbound(
            c.name,
            c.server,
            parseInt(c.server_port),
            c.tls_server_name || c.server
        )
        if (c.password) outbound.password = c.password
        if (c.up_mbps) outbound.up_mbps = Number(c.up_mbps)
        if (c.down_mbps) outbound.down_mbps = Number(c.down_mbps)
        if (c.server_ports && c.server_ports.length > 0) {
            outbound.server_ports = c.server_ports
                .map(range => range.replace('-', ':'))
                .filter(range => range.length > 0)
        }
        if (c.hop_interval) outbound.hop_interval = c.hop_interval
        if (c.network) outbound.network = c.network
        if (c.obfs_type === 'salamander' && c.obfs_password) {
            outbound.obfs = new ObfsConfig(c.obfs_password)
        }
        outbound.tls.insecure = c.tls_insecure === '1'
        return outbound
    }
}

singboxRegistry.register(hysteria2Protocol)
