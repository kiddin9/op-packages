/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';

'require baseclass';
'require form';
'require uci';

'require homeproxy as hp';

/* Build the shared body of a routing/dns rule section.  The two sections
 * differ in their tab/option names, the sniffed-protocol value list, the
 * order of the protocol/network/query-type triplet, a handful of
 * descriptions and their action-specific field sets; everything else is
 * emitted identically. */
function renderRuleSection(s, kind, self) {
	let o, ss, so;
	let is_dns = (kind === 'dns');
	let uci_type = is_dns ? 'dns_rule' : 'routing_rule';

	s.tab(uci_type, is_dns ? _('DNS Rules') : _('Routing Rules'));
	o = s.taboption(uci_type, form.SectionValue, '_' + uci_type, form.GridSection, uci_type);
	o.depends('routing_mode', 'custom');

	ss = o.subsection;
	ss.addremove = true;
	ss.rowcolors = true;
	ss.sortable = true;
	ss.nodescriptions = true;
	ss.modaltitle = L.bind(hp.loadModalTitle, hp, is_dns ? _('DNS rule') : _('Routing rule'),
		is_dns ? _('Add a DNS rule') : _('Add a routing rule'), 'homeproxy');
	ss.sectiontitle = L.bind(hp.loadDefaultLabel, self, 'homeproxy');
	/* Plain wrapper, not L.bind(): see hp.renderSectionAdd() for why the bound
	 * form hands a call site's button factory to the wrong argument. */
	ss.renderSectionAdd = function(extra_class) {
		return hp.renderSectionAdd(ss, extra_class);
	};

	ss.tab('field_other', _('Other fields'));
	ss.tab('field_host', _('Host/IP fields'));
	ss.tab('field_port', _('Port fields'));
	ss.tab('fields_process', _('Process fields'));

	so = ss.taboption('field_other', form.Value, 'label', _('Label'));
	so.load = L.bind(hp.loadDefaultLabel, self, 'homeproxy');
	so.validate = L.bind(hp.validateUniqueValue, self, 'homeproxy', uci_type, 'label');
	so.modalonly = true;

	so = ss.taboption('field_other', form.Flag, 'enabled', _('Enable'));
	so.default = so.enabled;
	so.rmempty = false;
	so.editable = true;

	so = ss.taboption('field_other', form.ListValue, 'mode', _('Mode'),
		is_dns ? _('The default rule uses the following matching logic:<br/>' +
			'<code>(domain || domain_suffix || domain_keyword || domain_regex)</code> &&<br/>' +
			'<code>(port || port_range)</code> &&<br/>' +
			'<code>(source_ip_cidr || source_ip_is_private)</code> &&<br/>' +
			'<code>(source_port || source_port_range)</code> &&<br/>' +
			'<code>other fields</code>.<br/>' +
			'Additionally, included rule sets can be considered merged rather than as a single rule sub-item.') :
			_('The default rule uses the following matching logic:<br/>' +
			'<code>(domain || domain_suffix || domain_keyword || domain_regex || ip_cidr || ip_is_private)</code> &&<br/>' +
			'<code>(port || port_range)</code> &&<br/>' +
			'<code>(source_ip_cidr || source_ip_is_private)</code> &&<br/>' +
			'<code>(source_port || source_port_range)</code> &&<br/>' +
			'<code>other fields</code>.<br/>' +
			'Additionally, included rule sets can be considered merged rather than as a single rule sub-item.'));
	so.value('default', _('Default'));
	so.default = 'default';
	so.rmempty = false;
	so.readonly = true;
	if (is_dns)
		so.modalonly = true;

	so = ss.taboption('field_other', form.ListValue, 'ip_version', _('IP version'),
		is_dns ? null : _('4 or 6. Not limited if empty.'));
	so.value('4', _('IPv4'));
	so.value('6', _('IPv6'));
	so.value('', _('Both'));
	so.modalonly = true;

	function addSniffedProtocol() {
		let opt = ss.taboption('field_other', form.MultiValue, 'protocol', _('Protocol'),
			_('Sniffed protocol, see <a target="_blank" href="https://sing-box.sagernet.org/configuration/route/sniff/">Sniff</a> for details.'));
		opt.value('bittorrent', _('BitTorrent'));
		if (!is_dns)
			opt.value('dns', _('DNS'));
		opt.value('dtls', _('DTLS'));
		opt.value('http', _('HTTP'));
		opt.value('quic', _('QUIC'));
		opt.value('rdp', _('RDP'));
		opt.value('ssh', _('SSH'));
		opt.value('stun', _('STUN'));
		opt.value('tls', _('TLS'));

		return opt;
	}

	function addNetwork() {
		let opt = ss.taboption('field_other', form.ListValue, 'network', _('Network'));
		opt.value('tcp', _('TCP'));
		opt.value('udp', _('UDP'));
		opt.value('', _('Both'));

		return opt;
	}

	if (is_dns) {
		so = ss.taboption('field_other', form.DynamicList, 'query_type', _('Query type'),
			_('Match query type.'));
		so.modalonly = true;

		so = addNetwork();
		so = addSniffedProtocol();
	} else {
		so = addSniffedProtocol();

		so = ss.taboption('field_other', form.Value, 'client', _('Client'),
			_('Sniffed client type (QUIC client type or SSH client name).'));
		so.value('chromium', _('Chromium / Cronet'));
		so.value('firefox', _('Firefox / uquic firefox'));
		so.value('quic-go', _('quic-go / uquic chrome'));
		so.value('safari', _('Safari / Apple Network API'));
		so.depends('protocol', 'quic');
		so.depends('protocol', 'ssh');
		so.modalonly = true;

		so = addNetwork();
	}

	so = ss.taboption('field_other', form.DynamicList, 'user', _('User'),
		_('Match user name.'));
	so.modalonly = true;

	so = ss.taboption('field_other', hp.CBIStaticList, 'rule_set', _('Rule set'),
		is_dns ? _('Match rule set. DNS: rules referencing rule-sets that contain query_type are incompatible with legacy address filters (ip_cidr / ip_is_private) — use match_response instead (1.14).') :
			_('Match rule set. Since 1.14: a rule-set holding a single default rule is merged into this rule; any other rule-set matches as an OR collection.'));
	so.load = function(section_id) {
		delete this.keylist;
		delete this.vallist;

		uci.sections('homeproxy', 'ruleset', (res) => {
			if (res.enabled === '1')
				this.value(res['.name'], res.label);
		});

		return this.super('load', section_id);
	}
	so.modalonly = true;

	so = ss.taboption('field_other', form.Flag, 'rule_set_ip_cidr_match_source', _('Rule set IP CIDR as source IP'),
		is_dns ? _('Make IP CIDR in rule sets match the source IP.') : _('Make IP CIDR in rule set used to match the source IP.'));
	so.modalonly = true;

	so = ss.taboption('field_other', form.Flag, 'invert', _('Invert'),
		_('Invert match result.'));
	so.modalonly = true;

	so = ss.taboption('field_other', form.ListValue, 'action', _('Action'));
	so.value('route', _('Route'));
	so.value('route-options', _('Route options'));
	so.value('reject', _('Reject'));
	if (is_dns) {
		so.value('predefined', _('Predefined'));
		so.value('evaluate', _('Evaluate (1.14)'));
	} else {
		so.value('resolve', _('Resolve'));
	}
	so.default = 'route';
	so.rmempty = false;
	so.editable = true;

	if (is_dns) {
			so = ss.taboption('field_other', form.ListValue, 'server', _('Server'),
				_('Tag of the target dns server.'));
			so.load = function(section_id) {
				delete this.keylist;
				delete this.vallist;

				this.value('default-dns', _('Default DNS (issued by WAN)'));
				this.value('system-dns', _('System DNS'));
				uci.sections('homeproxy', 'dns_server', (res) => {
					if (res.enabled === '1')
						this.value(res['.name'], res.label);
				});

				return this.super('load', section_id);
			}
			so.rmempty = false;
			so.editable = true;
			so.depends('action', 'route');
			so.depends('action', 'evaluate');

			so = ss.taboption('field_other', form.Flag, 'dns_disable_cache', _('Disable dns cache'),
				_('Disable cache and save cache in this query.'));
			so.depends('action', 'route');
			so.depends('action', 'route-options');
			so.modalonly = true;

			so = ss.taboption('field_other', form.Value, 'rewrite_ttl', _('Rewrite TTL'),
				_('Rewrite TTL in DNS responses.'));
			so.datatype = 'uinteger';
			so.depends('action', 'route');
			so.depends('action', 'route-options');
			so.modalonly = true;

			so = ss.taboption('field_other', form.Value, 'client_subnet', _('EDNS Client subnet'),
				_('Append a <code>edns0-subnet</code> OPT extra record with the specified IP prefix to every query by default.<br/>' +
				'If value is an IP address instead of prefix, <code>/32</code> or <code>/128</code> will be appended automatically.'));
			so.datatype = 'or(cidr, ipaddr)';
			so.depends('action', 'route');
			so.depends('action', 'route-options');
			so.modalonly = true;

			so = ss.taboption('field_other', form.Value, 'match_response', _('Match response'),
				_('1 matches the latest untagged evaluate result; other values match an evaluate tag (1.14).'));
			so.depends('action', 'route');
			so.modalonly = true;

			so = ss.taboption('field_other', form.Value, 'evaluate_tag', _('Evaluate tag'),
				_('Optional tag for this evaluate result.'));
			so.depends('action', 'evaluate');
			so.modalonly = true;

			so = ss.taboption('field_other', form.Flag, 'race', _('Race'),
				_('Judge this response-dependent rule in parallel; first match wins (1.14).'));
			so.depends({'action': 'route', 'match_response': /[\s\S]/});
			so.modalonly = true;

			so = ss.taboption('field_other', form.Flag, 'speculative', _('Speculative'),
				_('Send the query before pending race rules are judged (1.14).'));
			so.depends('action', 'route');
			so.depends('action', 'evaluate');
			so.modalonly = true;

			so = ss.taboption('field_other', form.Flag, 'disable_optimistic_cache', _('Disable optimistic cache'),
				_('Disable optimistic DNS caching for this query.'));
			so.depends('action', 'route');
			so.depends('action', 'evaluate');
			so.modalonly = true;

			so = ss.taboption('field_other', form.Value, 'dns_timeout', _('Query timeout'),
				_('Override dns.timeout for this query, in seconds.'));
			so.datatype = 'uinteger';
			so.depends('action', 'route');
			so.depends('action', 'evaluate');
			so.modalonly = true;

			so = ss.taboption('field_other', form.Flag, 'remove_client_subnet', _('Remove EDNS client subnet'),
				_('Remove the edns0-subnet record from the query (1.14).'));
			so.depends('action', 'route');
			so.depends('action', 'evaluate');
			so.modalonly = true;

			so = ss.taboption('field_other', form.ListValue, 'response_rcode', _('Response RCode'),
				_('Match the evaluated response code (requires match_response).'));
			for (let rc of [ 'NOERROR', 'FORMERR', 'SERVFAIL', 'NXDOMAIN', 'NOTIMP', 'REFUSED' ])
				so.value(rc);
			so.depends({'action': 'route', 'match_response': /[\s\S]/});
			so.modalonly = true;

			so = ss.taboption('field_other', form.DynamicList, 'response_answer', _('Response answer'),
				_('Text DNS records to match in the evaluated answer.'));
			so.depends({'action': 'route', 'match_response': /[\s\S]/});
			so.modalonly = true;

			so = ss.taboption('field_other', form.DynamicList, 'response_ns', _('Response NS'));
			so.depends({'action': 'route', 'match_response': /[\s\S]/});
			so.modalonly = true;

			so = ss.taboption('field_other', form.DynamicList, 'response_extra', _('Response extra'));
			so.depends({'action': 'route', 'match_response': /[\s\S]/});
			so.modalonly = true;

			so = ss.taboption('field_other', form.ListValue, 'reject_method', _('Method'));
			so.value('default', _('Reply with REFUSED'));
			so.value('drop', _('Drop requests'));
			so.default = 'default';
			so.depends('action', 'reject');
			so.modalonly = true;

			so = ss.taboption('field_other', form.Flag, 'reject_no_drop', _('Don\'t drop requests'),
				_('<code>%s</code> will be temporarily overwritten to <code>%s</code> after 50 triggers in 30s if not enabled.').format(
					_('Method'), _('Drop requests')));
			so.depends('reject_method', 'default');
			so.modalonly = true;

			so = ss.taboption('field_other', form.ListValue, 'predefined_rcode', _('RCode'),
				_('The response code.'));
			so.value('NOERROR');
			so.value('FORMERR');
			so.value('SERVFAIL');
			so.value('NXDOMAIN');
			so.value('NOTIMP');
			so.value('REFUSED');
			so.default = 'NOERROR';
			so.depends('action', 'predefined');
			so.modalonly = true;

			so = ss.taboption('field_other', form.DynamicList, 'predefined_answer', _('Answer'),
				_('List of text DNS record to respond as answers.'));
			so.depends('action', 'predefined');
			so.modalonly = true;

			so = ss.taboption('field_other', form.DynamicList, 'predefined_ns', _('NS'),
				_('List of text DNS record to respond as name servers.'));
			so.depends('action', 'predefined');
			so.modalonly = true;

			so = ss.taboption('field_other', form.DynamicList, 'predefined_extra', _('Extra records'),
				_('List of text DNS record to respond as extra records.'));
			so.depends('action', 'predefined');
			so.modalonly = true;
	} else {
			so = ss.taboption('field_other', form.ListValue, 'outbound', _('Outbound'),
				_('Tag of the target outbound.'));
			so.load = function(section_id) {
				delete this.keylist;
				delete this.vallist;

				this.value('direct-out', _('Direct'));
				uci.sections('homeproxy', 'routing_node', (res) => {
					if (res.enabled === '1')
						this.value(res['.name'], res.label);
				});

				return this.super('load', section_id);
			}
			so.rmempty = false;
			so.depends('action', 'route');
			so.editable = true;

			so = ss.taboption('field_other', form.Value, 'override_address', _('Override address'),
				_('Override the connection destination address.'));
			so.datatype = 'ipaddr';
			so.depends('action', 'route');
			so.depends('action', 'route-options');
			so.modalonly = true;

			so = ss.taboption('field_other', form.Value, 'override_port', _('Override port'),
				_('Override the connection destination port.'));
			so.datatype = 'port';
			so.depends('action', 'route');
			so.depends('action', 'route-options');
			so.modalonly = true;

			so = ss.taboption('field_other', form.Flag, 'udp_disable_domain_unmapping', _('Disable UDP domain unmapping'),
				_('If enabled, for UDP proxy requests addressed to a domain, the original packet address will be sent in the response instead of the mapped domain.'));
			so.depends('action', 'route');
			so.depends('action', 'route-options');
			so.modalonly = true;

			so = ss.taboption('field_other', form.Flag, 'udp_connect', _('connect UDP connections'),
				_('If enabled, attempts to connect UDP connection to the destination instead of listen.'));
			so.depends('action', 'route');
			so.depends('action', 'route-options');
			so.modalonly = true;

			so = ss.taboption('field_other', form.Value, 'udp_timeout', _('UDP timeout'),
				_('Timeout for UDP connections.<br/>Setting a larger value than the UDP timeout in inbounds will have no effect.'));
			so.datatype = 'uinteger';
			so.depends('action', 'route');
			so.depends('action', 'route-options');
			so.modalonly = true;

			so = ss.taboption('field_other', form.Flag, 'tls_record_fragment', _('TLS record fragment'),
				_('Fragment TLS handshake into multiple TLS records.'));
			so.depends('action', 'route');
			so.depends('action', 'route-options');
			so.modalonly = true;

			so = ss.taboption('field_other', form.Flag, 'tls_fragment', _('TLS fragment'),
				_('Fragment TLS handshakes. Due to poor performance, try <code>%s</code> first.').format(
					_('TLS record fragment')));
			so.depends('action', 'route');
			so.depends('action', 'route-options');
			so.modalonly = true;

			so = ss.taboption('field_other', form.Value, 'tls_fragment_fallback_delay', _('Fragment fallback delay'),
				_('The fallback value in milliseconds used when TLS segmentation cannot automatically determine the wait time.'));
			so.datatype = 'uinteger';
			so.placeholder = '500';
			so.depends('tls_fragment', '1');
			so.modalonly = true;

			so = ss.taboption('field_other', form.Value, 'tls_spoof', _('TLS spoof SNI (1.14)'),
				_('Inject a forged TLS ClientHello carrying this SNI before the real one to fool SNI-filtering middleboxes. Requires elevated privileges.'));
			so.datatype = 'hostname';
			so.depends('action', 'route');
			so.depends('action', 'route-options');
			so.modalonly = true;

			so = ss.taboption('field_other', form.ListValue, 'tls_spoof_method', _('TLS spoof method (1.14)'),
				_('How the forged segment is rejected by the real server.'));
			so.value('', _('wrong-sequence (default)'));
			so.value('wrong-checksum', _('wrong-checksum'));
			so.value('wrong-ack', _('wrong-ack'));
			so.value('wrong-md5', _('wrong-md5'));
			so.value('wrong-timestamp', _('wrong-timestamp'));
			so.depends('action', 'route');
			so.depends('action', 'route-options');
			so.depends('tls_spoof', /[\s\S]/);
			so.modalonly = true;

			so = ss.taboption('field_other', form.ListValue, 'resolve_server', _('DNS server'),
				_('Specifies DNS server tag to use instead of selecting through DNS routing.'));
			so.load = function(section_id) {
				delete this.keylist;
				delete this.vallist;

				this.value('', _('Default'));
				this.value('default-dns', _('Default DNS (issued by WAN)'));
				this.value('system-dns', _('System DNS'));
				uci.sections('homeproxy', 'dns_server', (res) => {
					if (res.enabled === '1')
						this.value(res['.name'], res.label);
				});

				return this.super('load', section_id);
			}
			so.depends('action', 'resolve');
			so.modalonly = true;

			so = ss.taboption('field_other', form.ListValue, 'reject_method', _('Method'));
			so.value('default', _('Reply with TCP RST / ICMP port unreachable'));
			so.value('drop', _('Drop packets'));
			so.depends('action', 'reject');
			so.modalonly = true;

			so = ss.taboption('field_other', form.Flag, 'reject_no_drop', _('Don\'t drop packets'),
				_('<code>%s</code> will be temporarily overwritten to <code>%s</code> after 50 triggers in 30s if not enabled.').format(
				_('Method'), _('Drop packets')));
			so.depends('reject_method', 'default');
			so.modalonly = true;

			so = ss.taboption('field_other', form.ListValue, 'resolve_strategy', _('Resolve strategy'),
				_('Domain strategy for resolving the domain names.'));
			for (let i in hp.dns_strategy)
				so.value(i, hp.dns_strategy[i]);
			so.depends('action', 'resolve');
			so.modalonly = true;

			so = ss.taboption('field_other', form.Flag, 'resolve_disable_cache', _('Disable DNS cache'),
				_('Disable DNS cache in this query.'));
			so.depends('action', 'resolve');
			so.modalonly = true;

			so = ss.taboption('field_other', form.Value, 'resolve_rewrite_ttl', _('Rewrite TTL'),
				_('Rewrite TTL in DNS responses.'));
			so.datatype = 'uinteger';
			so.depends('action', 'resolve');
			so.modalonly = true;

			so = ss.taboption('field_other', form.Value, 'resolve_client_subnet', _('EDNS Client subnet'),
				_('Append a <code>edns0-subnet</code> OPT extra record with the specified IP prefix to every query by default.<br/>' +
				'If value is an IP address instead of prefix, <code>/32</code> or <code>/128</code> will be appended automatically.'));
			so.datatype = 'or(cidr, ipaddr)';
			so.depends('action', 'resolve');
			so.modalonly = true;

			so = ss.taboption('field_other', form.Flag, 'resolve_disable_optimistic_cache', _('Disable optimistic cache'),
				_('Disable optimistic DNS caching in this lookup (1.14).'));
			so.depends('action', 'resolve');
			so.modalonly = true;

			so = ss.taboption('field_other', form.Value, 'resolve_timeout', _('Query timeout'),
				_('Override dns.timeout for this lookup, in seconds (1.14).'));
			so.datatype = 'uinteger';
			so.depends('action', 'resolve');
			so.modalonly = true;
	}

	so = ss.taboption('field_host', form.DynamicList, 'domain', _('Domain name'),
		_('Match full domain.'));
	so.datatype = 'hostname';
	so.modalonly = true;

	so = ss.taboption('field_host', form.DynamicList, 'domain_suffix', _('Domain suffix'),
		_('Match domain suffix.'));
	so.modalonly = true;

	so = ss.taboption('field_host', form.DynamicList, 'domain_keyword', _('Domain keyword'),
		_('Match domain using keyword.'));
	so.modalonly = true;

	so = ss.taboption('field_host', form.DynamicList, 'domain_regex', _('Domain regex'),
		_('Match domain using regular expression.'));
	so.modalonly = true;

	so = ss.taboption('field_host', form.DynamicList, 'source_ip_cidr', _('Source IP CIDR'),
		_('Match source IP CIDR.'));
	so.datatype = 'or(cidr, ipaddr)';
	so.modalonly = true;

	so = ss.taboption('field_host', form.Flag, 'source_ip_is_private', _('Match private source IP'));
	so.modalonly = true;

	so = ss.taboption('field_host', form.DynamicList, 'ip_cidr', _('IP CIDR'),
		is_dns ? _('Match IP CIDR with the evaluated response (needs match_response; old rules are auto-wrapped in 1.14).') :
			_('Match IP CIDR.'));
	so.datatype = 'or(cidr, ipaddr)';
	so.modalonly = true;

	so = ss.taboption('field_host', form.Flag, 'ip_is_private', _('Match private IP'),
		is_dns ? _('Match private IP with the evaluated response (needs match_response).') : null);
	so.modalonly = true;

	so = ss.taboption('field_host', form.DynamicList, 'source_mac_address', _('Source MAC address'),
		_('Match LAN device by MAC address.'));
	so.datatype = 'macaddr';
	so.modalonly = true;

	so = ss.taboption('field_host', form.DynamicList, 'source_hostname', _('Source hostname'),
		_('Match LAN device hostname via neighbor resolution; enable find_neighbor.'));
	so.modalonly = true;

	if (is_dns) {
		so = ss.taboption('field_host', form.Value, 'query_client_subnet', _('Query EDNS client subnet'),
			_('Match the EDNS Client Subnet in the query (1.14).'));
		so.datatype = 'or(cidr, ipaddr)';
		so.modalonly = true;

		so = ss.taboption('field_host', form.Flag, 'query_dnssec', _('Match DNSSEC OK'),
			_('Match queries with the DNSSEC OK bit set (1.14).'));
		so.modalonly = true;
	}

	so = ss.taboption('field_port', form.DynamicList, 'source_port', _('Source port'),
		_('Match source port.'));
	so.datatype = 'port';
	so.modalonly = true;

	so = ss.taboption('field_port', form.DynamicList, 'source_port_range', _('Source port range'),
		_('Match source port range. Format as START:/:END/START:END.'));
	so.validate = hp.validatePortRange;
	so.modalonly = true;

	so = ss.taboption('field_port', form.DynamicList, 'port', _('Port'),
		_('Match port.'));
	so.datatype = 'port';
	so.modalonly = true;

	so = ss.taboption('field_port', form.DynamicList, 'port_range', _('Port range'),
		_('Match port range. Format as START:/:END/START:END.'));
	so.validate = hp.validatePortRange;
	so.modalonly = true;

	so = ss.taboption('fields_process', form.DynamicList, 'process_name', _('Process name'),
		_('Match process name.'));
	so.modalonly = true;

	so = ss.taboption('fields_process', form.DynamicList, 'process_path', _('Process path'),
		_('Match process path.'));
	so.modalonly = true;

	so = ss.taboption('fields_process', form.DynamicList, 'process_path_regex', _('Process path (regex)'),
		_('Match process path using regular expression.'));
	so.modalonly = true;
}

return baseclass.extend({ renderRuleSection });
