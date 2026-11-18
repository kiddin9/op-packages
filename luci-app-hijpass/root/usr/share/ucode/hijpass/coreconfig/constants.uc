// 输出标签与 UCI 的用户节点名称分开，避免直接出口、DNS 和真实节点混淆。
export const TAG = {
	direct: 'direct-out', block: 'block', dns: 'dns-out',
	tproxy: 'tproxy-in', socks: 'socks-in', dnsInbound: 'dns-in',
	upstream: 'upstream-', balance: 'slb', member: 'lb-member-',
	ruleset: 'ruleset-out', rulesetDNS: 'ruleset-dns-resolver',
};
