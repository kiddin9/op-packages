export const identity = {
  hostname: 'openwrt-home-main',
  displayName: 'router-admin',
  domain: 'tailabcd12.ts.net',
  ipv4: '100.101.10.25',
  ipv6: 'fd7a:115c:a1e0::1025'
};
const dnsName = `${identity.hostname}.${identity.domain}`;

export const configs = {
  luci: {
    main: { '.name': 'main', '.type': 'core', '.anonymous': false, '.index': 0, lang: 'en', mediaurlbase: '/luci-static/bootstrap-light' },
    apply: { '.name': 'apply', '.type': 'internal', '.anonymous': false, '.index': 1, rollback: '90', holdoff: '4', timeout: '5', display: '1.5' }
  },
  'luci-app-tailscale-ng': {
    settings: {
      '.name': 'settings', '.type': 'settings', '.anonymous': false, '.index': 0,
      enabled: '1', accept_dns: '1', accept_routes: '0', advertise_exit_node: '0',
      login_server: '', authkey: '', advertise_routes: [], flags: []
    }
  },
  tailscale: {
    settings: {
      '.name': 'settings', '.type': 'settings', '.anonymous': false, '.index': 0,
      enabled: '0', port: '41641', state_file: '/etc/tailscale/tailscaled.state',
      fw_mode: 'nftables', log_stdout: '1', log_stderr: '1'
    }
  },
  network: {
    lan: {
      '.name': 'lan', '.type': 'interface', '.anonymous': false, '.index': 0,
      proto: 'static', ipaddr: '192.168.10.1', netmask: '255.255.255.0'
    }
  }
};

const statusJson = {
  BackendState: 'Running', AuthURL: '',
  Self: { UserID: '1000', HostName: identity.hostname, DNSName: `${dnsName}.`, TailscaleIPs: [identity.ipv4, identity.ipv6], OS: 'linux' },
  User: {
    '1000': { ID: '1000', DisplayName: identity.displayName, LoginName: 'router-admin@example.com' },
    '1001': { ID: '1001', DisplayName: 'user-main', LoginName: 'user-main@example.com' },
    '1002': { ID: '1002', DisplayName: 'infra', LoginName: 'infra@example.com' }
  },
  Peer: {
    phone: { UserID: '1001', HostName: 'pixel-8-pro', DNSName: `pixel-8-pro.${identity.domain}.`, TailscaleIPs: ['100.109.44.12'], OS: 'android', Online: false, ExitNodeOption: false },
    laptop: { UserID: '1001', HostName: 'thinkpad-x1', DNSName: `thinkpad-x1.${identity.domain}.`, TailscaleIPs: ['100.97.201.77'], OS: 'linux', Online: true, ExitNodeOption: false, TxBytes: 4120, RxBytes: 9981 },
    macbook: { UserID: '1001', HostName: 'macbook-air', DNSName: `macbook-air.${identity.domain}.`, TailscaleIPs: ['100.76.33.90'], OS: 'macOS', Online: true, ExitNodeOption: false },
    exit: { UserID: '1002', HostName: 'homelab-node', DNSName: `homelab-node.${identity.domain}.`, TailscaleIPs: ['100.120.5.199'], OS: 'linux', Online: true, ExitNodeOption: true, PrimaryRoutes: ['192.168.20.0/24'] }
  }
};

const commands = new Map([
  ['tailscale version', '1.98.3\n'],
  ['tailscale status --json', JSON.stringify(statusJson)],
  ['tailscale status', `${identity.ipv4}   openwrt-home-main   router-admin@   linux    -\n100.109.44.12   pixel-8-pro         user-main@      android  offline, last seen 2h ago\n100.97.201.77   thinkpad-x1         user-main@      linux    active; tx 4120 rx 9981\n100.76.33.90    macbook-air         user-main@      macOS    -\n100.120.5.199   homelab-node        infra@          linux    idle; offers exit node\n`],
  ['tailscale ip', `${identity.ipv4}\n${identity.ipv6}\n`],
  ['ip addr show tailscale0', `9: tailscale0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 1280 qdisc fq_codel state UNKNOWN qlen 500\n    link/none\n    inet ${identity.ipv4}/32 scope global tailscale0\n       valid_lft forever preferred_lft forever\n    inet6 ${identity.ipv6}/128 scope global\n       valid_lft forever preferred_lft forever\n    inet6 fe80::7b3d:5e1f:2c90:4a11/64 scope link flags 800\n       valid_lft forever preferred_lft forever\n`],
  ['tailscale netcheck', `Report:\n    * Time: 2026-01-15T12:00:00Z\n    * UDP: true\n    * IPv4: yes, 203.0.113.10:41641\n    * IPv6: no, but OS has support\n    * MappingVariesByDestIP: false\n    * PortMapping:\n    * Nearest DERP: Amsterdam\n    * DERP latency:\n        - ams: 12.4ms (Amsterdam)\n        - fra: 20.1ms (Frankfurt)\n        - par: 25.8ms (Paris)\n        - lhr: 31.2ms (London)\n        - nyc: 89.6ms (New York City)\n`],
  ['tailscale dns status', `=== 'Use Tailscale DNS' status ===\n\nTailscale DNS: enabled.\n\nTailscale is configured to handle DNS queries on this device.\nRun 'tailscale set --accept-dns=false' to revert to your system default DNS resolver.\n\n=== MagicDNS configuration ===\n\nThis is the DNS configuration provided by the coordination server to this device.\n\nMagicDNS: enabled tailnet-wide (suffix = ${identity.domain})\n\nOther devices in your tailnet can reach this device at ${dnsName}.\n\nResolvers (in preference order):\n  (no resolvers configured, system default will be used: see 'System DNS configuration' below)\n\nSplit DNS Routes:\n  - ts.net.                        -> 199.247.155.53\n  - ts.net.                        -> 2620:111:8007::53\n\nSearch Domains:\n  - ${identity.domain}\n\n=== System DNS configuration ===\n\nThis is the DNS configuration that Tailscale believes your operating system is using.\nTailscale may use this configuration if 'Override Local DNS' is disabled in the admin console,\nor if no resolvers are provided by the coordination server.\n\nNameservers:\n  - 127.0.0.1\n  - ::1\n\nSearch domains:\n  - lan\n\n[this is a preliminary version of this command; the output format may change in the future]\n`]
]);

export function rpcReply(object, method, args) {
  if (object === 'service' && method === 'list' && args.name === 'tailscale')
    return { tailscale: { instances: { instance1: { running: true } } } };
  if (object === 'system' && method === 'board')
    return { hostname: identity.hostname, system: 'Example router', model: 'Example router', release: { distribution: 'OpenWrt', version: '25.12.5' } };
  if (object === 'uci' && method === 'get' && configs[args.config])
    return { values: structuredClone(configs[args.config]) };
  if (object === 'uci' && method === 'changes') return { changes: {} };
  if (object === 'session' && method === 'access')
    return args.object ? { access: true } : {
      'access-group': { 'luci-base': ['read', 'write'], 'luci-app-tailscale-ng': ['read', 'write'] },
      uci: { 'luci-app-tailscale-ng': ['read', 'write'], tailscale: ['read', 'write'], network: ['read'] }
    };
  if (object === 'luci' && method === 'getFeatures') return {};
  if (object === 'file' && method === 'list' && args.path === '/www/luci-static/resources/preload')
    return { entries: [] };
  if (object === 'luci' && method === 'getInitList')
    return { 'luci-app-tailscale-ng': { enabled: true }, tailscale: { enabled: false } };
  if (object === 'file' && method === 'exec') {
    const command = [args.command?.split('/').pop(), ...(args.params || [])].join(' ');
    if (commands.has(command)) return { code: 0, stdout: commands.get(command), stderr: '' };
  }
  throw new Error(`Unmapped RPC: ${object}.${method} (${object === 'uci' ? args.config : object === 'file' && method === 'list' ? args.path : Object.keys(args || {}).sort().join(',')})`);
}

export const menu = {
  admin: {
    title: 'Administration', order: 10, action: { type: 'firstchild' }, children: {
      status: { title: 'Status', order: 10, action: { type: 'firstchild' }, children: { overview: { title: 'Overview', action: { type: 'view', path: 'status/overview' } } } },
      system: { title: 'System', order: 20, action: { type: 'firstchild' }, children: { system: { title: 'System', action: { type: 'view', path: 'system/system' } } } },
      network: { title: 'Network', order: 30, action: { type: 'firstchild' }, children: { network: { title: 'Interfaces', action: { type: 'view', path: 'network/interfaces' } } } },
      vpn: { title: 'VPN', order: 40, action: { type: 'firstchild' }, children: { 'tailscale-ng': { title: 'Tailscale NG', action: { type: 'view', path: 'tailscale-ng/index' } } } },
      logout: { title: 'Log out', order: 90, action: { type: 'call' } }
    }
  }
};

function satisfy(nodes) {
  for (const node of Object.values(nodes)) {
    node.satisfied = true;
    if (node.children) satisfy(node.children);
  }
}
satisfy(menu);
