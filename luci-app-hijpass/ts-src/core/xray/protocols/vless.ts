import type { ProxyNode } from '../../../module/luci'
import { VlessConfig } from '../../../module/luci'
import type { Outbound, TlsObject } from '../models'
import { xrayRegistry, type XrayProtocol } from './protocol'

interface WsObject {
    host?: string
    path?: string
    headers?: Record<string, string>
    heartbeatPeriod?: number
}

interface GrpcObject {
    serviceName?: string
    multiMode?: boolean
    authority?: string
    user_agent?: string
    idle_timeout?: number
    health_check_timeout?: number
    permit_without_stream?: boolean
    initial_windows_size?: number
}

interface HttpObject {
    host?: string[]
    path?: string
    method?: string
}

interface HttpUpgradeObject {
    host?: string
    path?: string
    headers?: Record<string, string>
}

interface XHTTPObject {
    host?: string
    path?: string
    mode?: string
    uplinkHTTPMethod?: string
}

interface RealityObject {
    show?: boolean
    target?: string
    xver?: number
    serverNames?: string[]
    privateKey?: string
    minClientVer?: string
    maxClientVer?: string
    maxTimeDiff?: number
    shortIds?: string[]
    mldsa65Seed?: string
    fingerprint?: string
    serverName?: string
    password?: string
    shortId?: string
    mldsa65Verify?: string
    spiderX?: string
}

interface VlessStreamSettings {
    network?: string
    security: string
    xhttpSettings?: XHTTPObject
    wsSettings?: WsObject
    grpcSettings?: GrpcObject
    httpSettings?: HttpObject
    httpupgradeSettings?: HttpUpgradeObject
    realitySettings?: RealityObject
    tlsSettings?: TlsObject
}

export class VlessOutbound implements Outbound {
    settings: any
    protocol: string
    tag: string
    streamSettings?: any

    constructor(
        address: string,
        port: number,
        id: string,
        tag: string,
        encryption: string = 'none',
        flow?: string,
        level: number = 0
    ) {
        this.protocol = 'vless'
        this.tag = tag
        this.settings = { address, port, id, encryption, level }
        if (flow) this.settings.flow = flow
    }
}

function parseDurationSeconds(value?: string): number | undefined {
    const raw = (value || '').trim()
    if (!raw) return undefined
    const match = raw.match(/^(\d+)(?:s)?$/)
    if (!match) return undefined
    const seconds = Number(match[1])
    return Number.isFinite(seconds) && seconds > 0 ? seconds : undefined
}

function appendEarlyData(path: string, maxEarlyData?: string): string {
    const ed = (maxEarlyData || '').trim()
    if (!ed) return path

    const base = path || '/'
    const hashIndex = base.indexOf('#')
    const pathAndQuery = hashIndex >= 0 ? base.slice(0, hashIndex) : base
    const hash = hashIndex >= 0 ? base.slice(hashIndex) : ''
    const separator = pathAndQuery.indexOf('?') >= 0 ? '&' : '?'
    return pathAndQuery + separator + 'ed=' + encodeURIComponent(ed) + hash
}

const vlessProtocol: XrayProtocol = {
    type: 'vless',
    build(config: ProxyNode): Outbound {
        const c = config as VlessConfig

        const outbound = new VlessOutbound(
            c.server,
            Number(c.server_port),
            c.uuid,
            c.name,
            'none',
            c.flow || undefined,
            0
        )

        const useReality = c.tls_reality_enabled === '1'
        const realitySettings: RealityObject | undefined = useReality ? {
            fingerprint: 'chrome',
            serverName: c.tls_server_name || c.server,
            password: c.tls_reality_public_key || '',
            shortId: c.tls_reality_short_id || ''
        } : undefined

        const tlsSettings: TlsObject | undefined = !useReality ? {
            alpn: ['h2', 'http/1.1'],
            serverName: c.tls_server_name || c.server,
        } : undefined

        const security = useReality
            ? 'reality'
            : (c.tls_server_name ? 'tls' : 'none')

        const streamSettings: VlessStreamSettings = { network: 'raw', security }
        if (realitySettings) streamSettings.realitySettings = realitySettings
        if (tlsSettings && security === 'tls') streamSettings.tlsSettings = tlsSettings

        switch (c.transport_type || '') {
            case 'xhttp':
                streamSettings.network = 'xhttp'
                streamSettings.xhttpSettings = {
                    host: c.transport_xhttp_host || undefined,
                    path: c.transport_xhttp_path || '/',
                    mode: c.transport_xhttp_mode || 'auto'
                }
                break
            case 'ws':
                streamSettings.network = 'websocket'
                streamSettings.wsSettings = {
                    host: c.transport_ws_host || undefined,
                    path: appendEarlyData(c.transport_ws_path || '/', c.transport_ws_max_early_data)
                }
                break
            case 'grpc':
                streamSettings.network = 'grpc'
                streamSettings.grpcSettings = {
                    serviceName: c.transport_grpc_service_name || 'TunService',
                    ...(parseDurationSeconds(c.transport_grpc_idle_timeout) ? { idle_timeout: parseDurationSeconds(c.transport_grpc_idle_timeout) } : {}),
                    ...(parseDurationSeconds(c.transport_grpc_ping_timeout) ? { health_check_timeout: parseDurationSeconds(c.transport_grpc_ping_timeout) } : {}),
                    ...(c.transport_grpc_permit_without_stream === '1' ? { permit_without_stream: true } : {})
                }
                break
            case 'http':
                streamSettings.network = 'xhttp'
                streamSettings.xhttpSettings = {
                    ...(c.transport_http_host ? { host: c.transport_http_host } : {}),
                    path: c.transport_http_path || '/',
                    mode: 'stream-one',
                    ...(c.transport_http_method ? { uplinkHTTPMethod: c.transport_http_method } : {})
                }
                break
            case 'httpupgrade':
                streamSettings.network = 'httpupgrade'
                streamSettings.httpupgradeSettings = {
                    host: c.transport_httpupgrade_host || undefined,
                    path: c.transport_httpupgrade_path || '/'
                }
                break
        }

        outbound['streamSettings'] = streamSettings
        return outbound
    }
}

xrayRegistry.register(vlessProtocol)
