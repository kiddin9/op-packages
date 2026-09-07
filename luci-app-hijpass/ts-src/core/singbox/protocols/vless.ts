import type { ProxyNode } from '../../../module/luci'
import { VlessConfig } from '../../../module/luci'
import { TlsConfig, MultiplexConfig, BrutalConfig, type Outbound, type Server } from '../models'
import { singboxRegistry, type SingBoxProtocol } from './protocol'

export interface HttpTransport {
    type: 'http'
    host?: string
    path?: string
    method?: string
    idle_timeout?: string
    ping_timeout?: string
}

export interface WebSocketTransport {
    type: 'ws'
    path?: string
    headers?: Record<string, string>
    max_early_data?: number
    early_data_header_name?: string
}

export interface GrpcTransport {
    type: 'grpc'
    service_name?: string
    idle_timeout?: string
    ping_timeout?: string
    permit_without_stream?: boolean
}

export interface HttpUpgradeTransport {
    type: 'httpupgrade'
    host?: string
    path?: string
}

export type TransportConfig =
    | HttpTransport
    | WebSocketTransport
    | GrpcTransport
    | HttpUpgradeTransport
    | { type: string; [key: string]: any }

export class VlessOutbound implements Server, Outbound {
    type = 'vless'
    tag: string
    server: string
    server_port: number
    uuid: string
    flow?: 'xtls-rprx-vision'
    network?: 'tcp' | 'udp'
    packet_encoding?: 'packetaddr' | 'xudp'
    tls: TlsConfig
    transport?: TransportConfig
    multiplex?: MultiplexConfig

    constructor(tag: string, server: string, server_port: number, uuid: string, serverName: string) {
        this.tag = tag
        this.server = server
        this.server_port = server_port
        this.uuid = uuid
        this.tls = new TlsConfig(serverName)
    }
}

function buildTransport(c: VlessConfig): TransportConfig | undefined {
    switch (c.transport_type) {
        case 'http': {
            const t: HttpTransport = { type: 'http' }
            if (c.transport_http_host) t.host = c.transport_http_host
            if (c.transport_http_path) t.path = c.transport_http_path
            if (c.transport_http_method) t.method = c.transport_http_method
            if (c.transport_http_idle_timeout) t.idle_timeout = c.transport_http_idle_timeout
            if (c.transport_http_ping_timeout) t.ping_timeout = c.transport_http_ping_timeout
            return t
        }
        case 'ws': {
            const t: WebSocketTransport = { type: 'ws' }
            if (c.transport_ws_path) t.path = c.transport_ws_path
            if (c.transport_ws_host) t.headers = { Host: c.transport_ws_host }
            if (c.transport_ws_max_early_data) t.max_early_data = parseInt(c.transport_ws_max_early_data)
            if (c.transport_ws_early_data_header_name) t.early_data_header_name = c.transport_ws_early_data_header_name
            return t
        }
        case 'grpc': {
            const t: GrpcTransport = { type: 'grpc' }
            if (c.transport_grpc_service_name) t.service_name = c.transport_grpc_service_name
            if (c.transport_grpc_idle_timeout) t.idle_timeout = c.transport_grpc_idle_timeout
            if (c.transport_grpc_ping_timeout) t.ping_timeout = c.transport_grpc_ping_timeout
            if (c.transport_grpc_permit_without_stream === '1') t.permit_without_stream = true
            return t
        }
        case 'httpupgrade': {
            const t: HttpUpgradeTransport = { type: 'httpupgrade' }
            if (c.transport_httpupgrade_host) t.host = c.transport_httpupgrade_host
            if (c.transport_httpupgrade_path) t.path = c.transport_httpupgrade_path
            return t
        }
        default: return undefined
    }
}

function buildMultiplex(c: VlessConfig): MultiplexConfig {
    const m = new MultiplexConfig()
    if (c.multiplex_protocol) m.protocol = c.multiplex_protocol as 'smux' | 'yamux' | 'h2mux'
    if (c.multiplex_max_connections) m.max_connections = parseInt(c.multiplex_max_connections)
    if (c.multiplex_min_streams) m.min_streams = parseInt(c.multiplex_min_streams)
    if (c.multiplex_max_streams) m.max_streams = parseInt(c.multiplex_max_streams)
    if (c.multiplex_brutal_enabled === '1') {
        const brutal = new BrutalConfig()
        if (c.multiplex_brutal_up_mbps) brutal.up_mbps = parseInt(c.multiplex_brutal_up_mbps)
        if (c.multiplex_brutal_down_mbps) brutal.down_mbps = parseInt(c.multiplex_brutal_down_mbps)
        m.brutal = brutal
    }
    return m
}

const vlessProtocol: SingBoxProtocol = {
    type: 'vless',
    build(config: ProxyNode): Outbound {
        const c = config as VlessConfig
        const outbound = new VlessOutbound(
            c.name, c.server, parseInt(c.server_port), c.uuid,
            c.tls_server_name || c.server
        )
        if (c.flow) outbound.flow = c.flow as 'xtls-rprx-vision'
        if (c.network) outbound.network = c.network as 'tcp' | 'udp'
        if (c.packet_encoding) outbound.packet_encoding = c.packet_encoding as 'packetaddr' | 'xudp'
        outbound.tls.insecure = c.tls_insecure === '1'
        if (c.tls_reality_enabled === '1' && c.tls_reality_public_key) {
            outbound.tls.reality = {
                enabled: true,
                public_key: c.tls_reality_public_key,
                short_id: c.tls_reality_short_id || ''
            }
        }
        if (c.transport_type) outbound.transport = buildTransport(c)
        if (c.multiplex_enabled === '1') outbound.multiplex = buildMultiplex(c)
        return outbound
    }
}

singboxRegistry.register(vlessProtocol)
