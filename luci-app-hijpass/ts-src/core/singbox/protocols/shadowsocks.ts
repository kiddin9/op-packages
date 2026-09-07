import type { ProxyNode } from '../../../module/luci'
import { ShadowsocksConfig } from '../../../module/luci'
import { MultiplexConfig, BrutalConfig, type Outbound, type Server } from '../models'
import { singboxRegistry, type SingBoxProtocol } from './protocol'

export class ShadowsocksOutbound implements Server, Outbound {
    type = 'shadowsocks'
    tag: string
    server: string
    server_port: number
    method: string
    password: string
    network?: 'tcp' | 'udp'
    udp_over_tcp?: boolean
    plugin?: string
    plugin_opts?: string
    multiplex?: MultiplexConfig

    constructor(tag: string, server: string, server_port: number, method: string, password: string) {
        this.tag = tag
        this.server = server
        this.server_port = server_port
        this.method = method
        this.password = password
    }
}

function buildMultiplex(config: ShadowsocksConfig): MultiplexConfig {
    const m = new MultiplexConfig()
    if (config.multiplex_protocol) m.protocol = config.multiplex_protocol as 'smux' | 'yamux' | 'h2mux'
    if (config.multiplex_max_connections) m.max_connections = parseInt(config.multiplex_max_connections)
    if (config.multiplex_min_streams) m.min_streams = parseInt(config.multiplex_min_streams)
    if (config.multiplex_max_streams) m.max_streams = parseInt(config.multiplex_max_streams)
    if (config.multiplex_brutal_enabled === '1') {
        const brutal = new BrutalConfig()
        if (config.multiplex_brutal_up_mbps) brutal.up_mbps = parseInt(config.multiplex_brutal_up_mbps)
        if (config.multiplex_brutal_down_mbps) brutal.down_mbps = parseInt(config.multiplex_brutal_down_mbps)
        m.brutal = brutal
    }
    return m
}

const shadowsocksProtocol: SingBoxProtocol = {
    type: 'shadowsocks',
    build(config: ProxyNode): Outbound {
        const c = config as ShadowsocksConfig
        const outbound = new ShadowsocksOutbound(
            c.name, c.server, parseInt(c.server_port), c.method, c.password
        )
        if (c.network) outbound.network = c.network as 'tcp' | 'udp'
        if (c.udp_over_tcp === '1') outbound.udp_over_tcp = true
        if (c.plugin) outbound.plugin = c.plugin
        if (c.plugin_opts) outbound.plugin_opts = c.plugin_opts
        if (c.multiplex_enabled === '1') outbound.multiplex = buildMultiplex(c)
        return outbound
    }
}

singboxRegistry.register(shadowsocksProtocol)
