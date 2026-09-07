import type { ProxyNode } from '../../../module/luci'
import { TuicConfig } from '../../../module/luci'
import { TlsConfig, type Outbound, type Server } from '../models'
import { singboxRegistry, type SingBoxProtocol } from './protocol'

export class TuicOutbound implements Server, Outbound {
    type = 'tuic'
    tag: string
    server: string
    server_port: number
    uuid: string
    password: string
    congestion_control?: 'bbr' | 'cubic' | 'new_reno'
    udp_relay_mode?: 'native' | 'quic'
    udp_over_stream?: boolean
    zero_rtt_handshake?: boolean
    heartbeat?: string
    network?: 'tcp' | 'udp'
    tls: TlsConfig

    constructor(
        tag: string, server: string, server_port: number,
        uuid: string, password: string, serverName: string
    ) {
        this.tag = tag
        this.server = server
        this.server_port = server_port
        this.uuid = uuid
        this.password = password
        this.tls = new TlsConfig(serverName)
    }
}

const tuicProtocol: SingBoxProtocol = {
    type: 'tuic',
    build(config: ProxyNode): Outbound {
        const c = config as TuicConfig
        const outbound = new TuicOutbound(
            c.name, c.server, parseInt(c.server_port),
            c.uuid, c.password, c.tls_server_name || c.server
        )
        if (c.congestion_control) outbound.congestion_control = c.congestion_control as 'bbr' | 'cubic' | 'new_reno'
        if (c.udp_relay_mode) outbound.udp_relay_mode = c.udp_relay_mode as 'native' | 'quic'
        if (c.udp_over_stream === '1') outbound.udp_over_stream = true
        if (c.zero_rtt_handshake === '1') outbound.zero_rtt_handshake = true
        if (c.heartbeat) outbound.heartbeat = c.heartbeat
        if (c.network) outbound.network = c.network as 'tcp' | 'udp'
        outbound.tls.insecure = c.tls_insecure === '1'
        return outbound
    }
}

singboxRegistry.register(tuicProtocol)
