// Run with: node tests/backend/generate-fixtures.cjs
// The last browser-side TS generator is the source of expected behavior.
// Execute that historical TS code directly, independently of the ucode implementation.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { execFileSync } = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const esbuild = require(path.join(root, 'ts-src/node_modules/esbuild'));
const revision = 'bca34e5285fd8edd7da6cb2fd23e499e68c9f502';
const source = fs.mkdtempSync(path.join(os.tmpdir(), 'hijpass-ts-fixtures-'));
process.on('exit', () => fs.rmSync(source, { recursive: true, force: true }));
execFileSync('tar', ['-xf', '-', '-C', source], {
    input: execFileSync('git', ['archive', revision, 'ts-src'], { cwd: root, maxBuffer: 16 * 1024 * 1024 }),
});
const bundle = esbuild.buildSync({
    stdin: {
        contents: `export { CoreAdapterFactory, LuciConverterFactory } from './core/adapter';
            export { ProxyUtils } from './utils/feature/proxy/section';
            export { JsonUtils } from './utils/base/files/json';`,
        resolveDir: path.join(source, 'ts-src'), loader: 'ts',
    },
    bundle: true, format: 'cjs', platform: 'node', external: ['uci'], write: false, target: 'es2022',
}).outputFiles[0].text;
let sections = [];
const uci = {
    sections(_, type, callback) {
        const selected = sections.filter(s => !type || s['.type'] === type);
        if (callback) selected.forEach(callback);
        return selected;
    },
    get_first(_, type, key) {
        const section = sections.find(s => s['.type'] === type);
        return key ? section?.[key] : section;
    },
};
const context = vm.createContext({ exports: {}, module: { exports: {} }, require: () => uci, structuredClone });
vm.runInContext(`function _(s) { return s; }
    String.prototype.format = function(...args) {
        let i = 0; return this.replace(/%s/g, () => args[i++]);
    };` + bundle, context);
const { CoreAdapterFactory, LuciConverterFactory, ProxyUtils, JsonUtils } = context.module.exports;

// Explicit upstream schema fixes only. Keep false, 0, arrays, durations and ordering intact.
// sing-box: https://sing-box.sagernet.org/migration/#migrate-legacy-special-outbounds-to-rule-actions
// Domain resolver: https://sing-box.sagernet.org/configuration/route/#default_domain_resolver
// Reality requires uTLS: https://github.com/SagerNet/sing-box/blob/v1.14.1/common/tls/reality_client.go
// Xray: https://xtls.github.io/config/outbounds/freedom.html and /config/routing.html
function currentSchema(result) {
    for (const config of Object.values(result.nodes)) {
        if (config.inbounds[0].type) {
            config.route = { ...config.route, default_domain_resolver: 'local' };
            for (const outbound of config.outbounds) {
                if (outbound.tls?.reality)
                    outbound.tls.utls = { enabled: true, fingerprint: 'chrome' };
            }
        } else {
            // The old TS emitted level=0; current Xray calls this field userLevel and defaults to zero.
            for (const outbound of config.outbounds) delete outbound.settings?.level;
        }
    }
    if (!result.shunt) return result;
    if (result.shunt.route) {
        // Block routing already uses action=reject; the obsolete block outbound is unused.
        result.shunt.outbounds = result.shunt.outbounds.filter(o => o.type !== 'block');
    } else {
        for (const outbound of result.shunt.outbounds) {
            if (outbound.protocol === 'freedom') {
                const domainStrategy = outbound.settings.domainStrategy;
                delete outbound.settings.domainStrategy;
                outbound.streamSettings = { sockopt: { domainStrategy } };
            }
        }
        // TS accidentally converted Xray port ranges to sing-box's colon syntax.
        for (const rule of result.shunt.routing.rules)
            if (rule.port) rule.port = rule.port.replaceAll(':', '-');
    }
    return result;
}

const global = { '.name': 'global', '.type': 'hijpass', enabled: '1' };
const base = {
    '.name': 'node', '.type': 'proxy_node', name: 'node', enabled: '1',
    listen_port: '11001', socks_port: '12001', server: 'example.org', server_port: '443',
    password: 'test-password', uuid: '11111111-1111-4111-8111-111111111111', method: 'aes-128-gcm',
};
const samples = [];
function add(name, config) {
    sections = config;
    const nodes = {};
    for (const section of uci.sections('', 'proxy_node')) {
        if (section.enabled !== '1' || section.type === 'custom' || section.core === 'custom') continue;
        const proxy = ProxyUtils.createProxyConfigFromSection(section);
        nodes[section['.name']] = LuciConverterFactory.genProxyConf(proxy.core, proxy);
    }
    const shunt = uci.get_first('', 'shunt');
    const result = { nodes };
    if (shunt && shunt.enabled !== '0' && shunt.config_type === 'tmpl')
        result.shunt = CoreAdapterFactory.getCoreAdapter(shunt.type).genShuntConf();
    const expected = currentSchema(JSON.parse(JSON.stringify(result, JsonUtils.omitEmptyReplacer)));
    samples.push({ name, sections: config, expected });
}
for (const core of ['sing-box', 'xray']) {
    const protocols = core === 'xray' ? ['shadowsocks', 'hysteria2', 'vless']
        : ['shadowsocks', 'hysteria2', 'vless', 'tuic', 'shadowtls'];
    for (const type of protocols) {
        add(`${core}-${type}-defaults`, [global, { ...base, core, type }]);
        add(`${core}-${type}-options`, [global, {
            ...base, core, type, tls_server_name: 'tls.example.org', tls_insecure: '1', network: 'udp',
            up_mbps: '20', down_mbps: '0', udp_idle_timeout: '30', server_ports: ['443', '1000-2000'],
            hop_interval: '30s', obfs_type: 'salamander', obfs_password: 'test-obfs', version: '3',
            congestion_control: 'bbr', udp_relay_mode: 'quic', udp_over_stream: '1', zero_rtt_handshake: '1',
            heartbeat: '5s', udp_over_tcp: core === 'xray' ? '0' : '1', plugin: 'obfs-local', plugin_opts: 'obfs=http',
            multiplex_enabled: '1', multiplex_max_connections: '4', multiplex_min_streams: '2', multiplex_max_streams: '8',
            multiplex_brutal_enabled: '1', multiplex_brutal_up_mbps: '30', multiplex_brutal_down_mbps: '60',
            packet_encoding: 'xudp', flow: 'xtls-rprx-vision', tls_reality_enabled: '1',
            tls_reality_public_key: 'test-public-key', tls_reality_short_id: '12345678',
        }]);
    }
    const transports = core === 'xray' ? ['http', 'ws', 'grpc', 'httpupgrade', 'xhttp'] : ['http', 'ws', 'grpc', 'httpupgrade'];
    for (const transport of transports) {
        add(`${core}-vless-${transport}`, [global, {
            ...base, core, type: 'vless', transport_type: transport,
            transport_http_host: 'host.example.org', transport_http_path: '/http', transport_http_method: 'POST',
            transport_ws_host: 'ws.example.org', transport_ws_path: '/ws?test=1#frag',
            transport_ws_max_early_data: '1024', transport_ws_early_data_header_name: 'Sec-WebSocket-Protocol',
            transport_grpc_service_name: 'service', transport_grpc_permit_without_stream: '1',
            transport_httpupgrade_host: 'upgrade.example.org', transport_httpupgrade_path: '/upgrade',
            transport_xhttp_host: 'xhttp.example.org', transport_xhttp_path: '/xhttp', transport_xhttp_mode: 'packet-up',
        }]);
    }
    const member = { ...base, '.name': 'member', name: 'member', core, type: 'shadowsocks' };
    const balance = { '.name': 'lb', '.type': 'proxy_node', name: 'lb', enabled: '1', core, type: 'load_balance',
        listen_port: '11002', socks_port: '12002', member_node: ['member'] };
    add(`${core}-load-balance`, [global, member, balance]);
    add(`${core}-load-balance-options`, [global, member, {
        ...balance, url: 'https://example.org/204', interval: '1m', tolerance: '100', idle_timeout: '10m',
        interrupt_exist_connections: '1', strategy: 'leastLoad', strategy_expected: '2', strategy_max_rtt: '2s',
        strategy_tolerance: '0.1', probe_url: 'https://example.org/probe', probe_connectivity: 'https://example.org/check',
        probe_interval: '2m', probe_timeout: '3s', probe_sampling: '5', probe_http_method: 'HEAD',
    }]);
    add(`${core}-chain`, [global, member, { ...base, '.name': 'downstream', name: 'downstream', core, type: 'vless',
        listen_port: '11003', socks_port: '12003', upstream_proxy_node: 'member' }]);
    const shunt = { '.name': 'shunt', '.type': 'shunt', type: core, config_type: 'tmpl',
        shunt_listen_port: '18081', dns_listen_port: '10153', log_level: 'warn', default_proxy_node: 'hijpass-direct',
        default_dns_node: 'dns', default_strategy: '64', use_cache: '1', ruleset_convert: '0' };
    const dns = { '.name': 'dns', '.type': 'shunt_dns_node', tag: 'dns', type: 'https', server: '1.1.1.1' };
    const rule = { '.name': 'rule', '.type': 'shunt_route_rule', name: 'rule', enabled: '1', proxy_node: 'member',
        dns_strategy: '4', domain_list: 'full:example.org\ndomain:example.net\nkeyword\nregexp:.*test.*',
        ip_list: '1.2.3.4/32\n2001:db8::/32', protocol: ['tls'], network: ['tcp'], port: ['443'], port_range: ['8000-9000'] };
    add(`${core}-shunt-default`, [global, shunt, dns]);
    add(`${core}-shunt-rules`, [global, member, shunt, dns, rule]);
    add(`${core}-shunt-split`, [global, member, shunt, dns, { ...rule, ip_version_split: '1',
        proxy_node_v4: 'member', proxy_node_v6: 'hijpass-direct', dns_proxy_node: 'member' }]);
    add(`${core}-shunt-block`, [global, member, shunt, dns, { ...rule, proxy_node: 'hijpass-block' }]);
    add(`${core}-shunt-geo`, [global, member, { ...shunt, ruleset_convert: '1', ruleset_out_node: 'member', ruleset_dns_node: 'dns' },
        dns, { ...rule, domain_list: 'geosite:cn\nfull:example.org', ip_list: 'geoip:cn' }]);
    add(`${core}-shunt-rulesets`, [global, member, { ...shunt, ruleset_out_node: 'member', ruleset_dns_node: 'dns' },
        dns, { ...rule, domain_list: 'rule-set:remote:https://example.org/test.srs\nrule-set:local:/etc/hijpass/test.json' }]);
    for (const type of ['tcp', 'udp', 'quic'])
        add(`${core}-dns-${type}`, [global, { ...shunt, use_cache: '0', default_strategy: '6' }, { ...dns, type, port: '5353' }]);

    // Boundary cases distinguish absent options from explicitly configured zero/false values.
    add(`${core}-hysteria2-zero-bandwidth`, [global, { ...base, core, type: 'hysteria2', up_mbps: '0', down_mbps: '0' }]);
    add(`${core}-load-balance-zero-options`, [global, member, { ...balance,
        interval: '0s', idle_timeout: '0s', tolerance: '0', interrupt_exist_connections: '0',
        strategy_expected: '0', strategy_max_rtt: '0s', strategy_tolerance: '0', probe_sampling: '0' }]);
    add(`${core}-vless-empty-grpc-options`, [global, { ...base, core, type: 'vless', transport_type: 'grpc',
        transport_grpc_idle_timeout: '', transport_grpc_ping_timeout: '', transport_grpc_permit_without_stream: '0' }]);
    add(`${core}-shunt-source-ruleset`, [global, member, shunt, dns, { ...rule,
        domain_list: 'rule-set:remote:https://example.org/source.json' }]);
    for (const version of [4, 6])
        add(`${core}-shunt-ipv${version}-only`, [global, member, shunt, dns, { ...rule, ip_version_split: '1',
            [`proxy_node_v${version}`]: 'member', dns_proxy_node: 'member' }]);
    if (core === 'xray') add(`${core}-shunt-external-ip-split`, [global, member, shunt, dns, { ...rule, domain_list: '',
        ip_version_split: '1', proxy_node_v4: 'member', proxy_node_v6: 'hijpass-direct',
        ip_list: 'ext:/etc/hijpass/custom.dat:cn\n192.0.2.0/24\n2001:db8::/32' }]);
}
fs.writeFileSync(path.join(__dirname, 'testdata/compatibility.json'), JSON.stringify(samples, null, 2) + '\n');
console.log(`${samples.length} fixtures generated directly from TS ${revision.slice(0, 7)}`);
