import type { ProxyNode } from '../../../module/luci'
import { ShadowTLSConfig } from '../../../module/luci'
import { TlsConfig, type Outbound, type Server } from '../models'
import { singboxRegistry, type SingBoxProtocol } from './protocol'

export class ShadowTLSOutbound implements Server, Outbound {
    type = 'shadowtls'
    tag: string
    server: string
    server_port: number
    version: number
    password?: string
    tls: TlsConfig

    constructor(tag: string, server: string, server_port: number, version: number, serverName: string) {
        this.tag = tag
        this.server = server
        this.server_port = server_port
        this.version = version
        this.tls = new TlsConfig(serverName)
    }
}

const shadowtlsProtocol: SingBoxProtocol = {
    type: 'shadowtls',
    build(config: ProxyNode): Outbound {
        const c = config as ShadowTLSConfig
        const outbound = new ShadowTLSOutbound(
            c.name, c.server, parseInt(c.server_port),
            parseInt(c.version), c.tls_server_name || c.server
        )
        if (c.password) outbound.password = c.password
        outbound.tls.insecure = c.tls_insecure === '1'
        return outbound
    }
}

singboxRegistry.register(shadowtlsProtocol)
