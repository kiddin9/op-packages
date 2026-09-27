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
'require tools.widgets as widgets';

/* Routing nodes sub-grid (the per-outbound entries that routing_rule
 * actions dispatch to). Called after routing.render() so the SectionValue
 * grid nesting is intact. */
function renderRoutingNodes(ctx) {
	const { s, proxy_nodes } = ctx;
	let o, ss, so;

	s.tab('routing_node', _('Routing Nodes'));
	o = s.taboption('routing_node', form.SectionValue, '_routing_node', form.GridSection, 'routing_node');
	o.depends('routing_mode', 'custom');

	ss = o.subsection;
	ss.addremove = true;
	ss.rowcolors = true;
	ss.sortable = true;
	ss.nodescriptions = true;
	ss.modaltitle = L.bind(hp.loadModalTitle, hp, _('Routing node'), _('Add a routing node'), 'homeproxy');
	ss.sectiontitle = L.bind(hp.loadDefaultLabel, this, 'homeproxy');
	/* Plain wrapper, not L.bind(): see hp.renderSectionAdd() for why the bound
	 * form hands a call site's button factory to the wrong argument. */
	ss.renderSectionAdd = function(extra_class) {
		return hp.renderSectionAdd(ss, extra_class);
	};

	so = ss.option(form.Value, 'label', _('Label'));
	so.load = L.bind(hp.loadDefaultLabel, this, 'homeproxy');
	so.validate = L.bind(hp.validateUniqueValue, this, 'homeproxy', 'routing_node', 'label');
	so.modalonly = true;

	so = ss.option(form.Flag, 'enabled', _('Enable'));
	so.default = so.enabled;
	so.rmempty = false;
	so.editable = true;

	so = ss.option(form.ListValue, 'node', _('Node'),
		_('Outbound node'));
	so.value('urltest', _('URLTest'));
	for (let i in proxy_nodes)
		so.value(i, proxy_nodes[i]);
	so.validate = L.bind(hp.validateUniqueValue, this, 'homeproxy', 'routing_node', 'node');
	so.editable = true;

	so = ss.option(form.ListValue, 'domain_resolver', _('Domain resolver'),
		_('For resolving domain name in the server address.'));
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
	so.depends({'node': 'urltest', '!reverse': true});
	so.modalonly = true;

	so = ss.option(form.ListValue, 'domain_strategy', _('Domain strategy'),
		_('The domain strategy for resolving the domain name in the address.'));
	for (let i in hp.dns_strategy)
		so.value(i, hp.dns_strategy[i]);
	so.depends({'node': 'urltest', '!reverse': true});
	so.modalonly = true;

	so = ss.option(widgets.DeviceSelect, 'bind_interface', _('Bind interface'),
		_('The network interface to bind to.'));
	so.multiple = false;
	so.noaliases = true;
	so.depends({'outbound': '', 'node': /^((?!urltest$).)+$/});
	so.modalonly = true;

	so = ss.option(form.ListValue, 'outbound', _('Outbound'),
		_('The tag of the upstream outbound.<br/>Other dial fields will be ignored when enabled.'));
	so.load = function(section_id) {
		delete this.keylist;
		delete this.vallist;

		this.value('', _('Direct'));
		uci.sections('homeproxy', 'routing_node', (res) => {
			if (res['.name'] !== section_id && res.enabled === '1')
				this.value(res['.name'], res.label);
		});

		return this.super('load', section_id);
	}
	so.validate = function(section_id, value) {
		if (section_id && value) {
			let node = this.section.formvalue(section_id, 'node');

			let conflict = false;
			uci.sections('homeproxy', 'routing_node', (res) => {
				if (res['.name'] !== section_id) {
					if (res.outbound === section_id && res['.name'] == value)
						conflict = true;
					else if (res.node === 'urltest' && res.urltest_nodes?.includes(node) && res['.name'] == value)
						conflict = true;
				}
			});
			if (conflict)
				return _('Recursive outbound detected!');
		}

		return true;
	}
	so.depends({'node': 'urltest', '!reverse': true});
	so.editable = true;

	so = ss.option(hp.CBIStaticList, 'urltest_nodes', _('URLTest nodes'),
		_('List of nodes to test.'));
	for (let i in proxy_nodes)
		so.value(i, proxy_nodes[i]);
	so.depends('node', 'urltest');
	/* The repository's other validators take (section_id, value) and check
	 * `value` before dereferencing it. This one re-read the value through
	 * `this.section.formvalue()`, which returns null when the widget is not
	 * in the DOM, so `.length` threw a TypeError - the save aborted with a
	 * console error instead of the "non-empty value" message. The framework
	 * already hands the current value in (getValidator is
	 * L.bind(this.validate, this, section_id)), so use it. */
	so.validate = function(section_id, value) {
		if (section_id && value && !value.length)
			return _('Expecting: %s').format(_('non-empty value'));

		return true;
	}
	so.modalonly = true;

	so = ss.option(form.Value, 'urltest_url', _('Test URL'),
		_('The URL to test.'));
	so.placeholder = 'https://www.gstatic.com/generate_204';
	so.validate = function(section_id, value) {
		if (section_id && value) {
			try {
				let url = new URL(value);
				if (!url.hostname)
					return _('Expecting: %s').format(_('valid URL'));
			}
			catch(e) {
				return _('Expecting: %s').format(_('valid URL'));
			}
		}

		return true;
	}
	so.depends('node', 'urltest');
	so.modalonly = true;

	so = ss.option(form.Value, 'urltest_interval', _('Test interval'),
		_('The test interval in seconds.'));
	so.datatype = 'uinteger';
	so.placeholder = '180';
	so.validate = function(section_id, value) {
		if (section_id && value) {
			let idle_timeout = this.section.formvalue(section_id, 'urltest_idle_timeout') || '1800';
			if (parseInt(value) > parseInt(idle_timeout))
				return _('Test interval must be less or equal than idle timeout.');
		}

		return true;
	}
	so.depends('node', 'urltest');
	so.modalonly = true;

	so = ss.option(form.Value, 'urltest_tolerance', _('Test tolerance'),
		_('The test tolerance in milliseconds.'));
	so.datatype = 'uinteger';
	so.placeholder = '50';
	so.depends('node', 'urltest');
	so.modalonly = true;

	so = ss.option(form.Value, 'urltest_idle_timeout', _('Idle timeout'),
		_('The idle timeout in seconds.'));
	so.datatype = 'uinteger';
	so.placeholder = '1800';
	so.depends('node', 'urltest');
	so.modalonly = true;

	so = ss.option(form.Flag, 'urltest_interrupt_exist_connections', _('Interrupt existing connections'),
		_('Interrupt existing connections when the selected outbound has changed.'));
	so.depends('node', 'urltest');
	so.modalonly = true;
	/* Routing nodes end */

}

/* DNS servers sub-grid (per-server entries that dns_rule 'route'/'evaluate'
 * actions can target). Called after dns.renderDnsSettings() so the dns
 * NamedSection is in place. */
function renderDnsServers(ctx) {
	const { s } = ctx;
	let o, ss, so;

	s.tab('dns_server', _('DNS Servers'));
	o = s.taboption('dns_server', form.SectionValue, '_dns_server', form.GridSection, 'dns_server');
	o.depends('routing_mode', 'custom');

	ss = o.subsection;
	ss.addremove = true;
	ss.rowcolors = true;
	ss.sortable = true;
	ss.nodescriptions = true;
	ss.modaltitle = L.bind(hp.loadModalTitle, hp, _('DNS server'), _('Add a DNS server'), 'homeproxy');
	ss.sectiontitle = L.bind(hp.loadDefaultLabel, this, 'homeproxy');
	/* Plain wrapper, not L.bind(): see hp.renderSectionAdd() for why the bound
	 * form hands a call site's button factory to the wrong argument. */
	ss.renderSectionAdd = function(extra_class) {
		return hp.renderSectionAdd(ss, extra_class);
	};

	so = ss.option(form.Value, 'label', _('Label'));
	so.load = L.bind(hp.loadDefaultLabel, this, 'homeproxy');
	so.validate = L.bind(hp.validateUniqueValue, this, 'homeproxy', 'dns_server', 'label');
	so.modalonly = true;

	so = ss.option(form.Flag, 'enabled', _('Enable'));
	so.default = so.enabled;
	so.rmempty = false;
	so.editable = true;

	so = ss.option(form.ListValue, 'type', _('Type'));
	so.value('udp', _('UDP'));
	so.value('tcp', _('TCP'));
	so.value('tls', _('TLS'));
	so.value('https', _('HTTPS'));
	so.value('h3', _('HTTP/3'));
	so.value('quic', _('QUIC'));
	so.default = 'udp';
	so.rmempty = false;

	so = ss.option(form.Value, 'server', _('Address'),
		_('The address of the dns server.'));
	so.datatype = 'or(hostname, ipaddr)';
	so.rmempty = false;

	so = ss.option(form.Value, 'server_port', _('Port'),
		_('The port of the DNS server.'));
	so.placeholder = 'auto';
	so.datatype = 'port';

	so = ss.option(form.Value, 'path', _('Path'),
		_('The path of the DNS server.'));
	so.placeholder = '/dns-query';
	so.depends('type', 'https');
	so.depends('type', 'h3');
	so.modalonly = true;

	so = ss.option(form.DynamicList, 'headers', _('Headers'),
		_('Additional headers to be sent to the DNS server.'));
	so.depends('type', 'https');
	so.depends('type', 'h3');
	so.modalonly = true;

	so = ss.option(form.Value, 'tls_sni', _('TLS SNI'),
		_('Used to verify the hostname on the returned certificates.'));
	so.depends('type', 'tls');
	so.depends('type', 'https');
	so.depends('type', 'h3');
	so.depends('type', 'quic');
	so.modalonly = true;

	so = ss.option(form.ListValue, 'address_resolver', _('Address resolver'),
		_('Tag of a another server to resolve the domain name in the address. Required if address contains domain.'));
	so.load = function(section_id) {
		delete this.keylist;
		delete this.vallist;

		this.value('', _('None'));
		this.value('default-dns', _('Default DNS (issued by WAN)'));
		this.value('system-dns', _('System DNS'));
		uci.sections('homeproxy', 'dns_server', (res) => {
			if (res['.name'] !== section_id && res.enabled === '1')
				this.value(res['.name'], res.label);
		});

		return this.super('load', section_id);
	}
	so.validate = function(section_id, value) {
		if (section_id && value) {
			let conflict = false;
			uci.sections('homeproxy', 'dns_server', (res) => {
				if (res['.name'] !== section_id)
					if (res.address_resolver === section_id && res['.name'] == value)
						conflict = true;
			});
			if (conflict)
				return _('Recursive resolver detected!');
		}

		return true;
	}
	so.modalonly = true;

	so = ss.option(form.ListValue, 'address_strategy', _('Address strategy'),
		_('The domain strategy for resolving the domain name in the address.'));
	for (let i in hp.dns_strategy)
		so.value(i, hp.dns_strategy[i]);
	so.depends({'address_resolver': '', '!reverse': true});
	so.modalonly = true;

	so = ss.option(form.ListValue, 'outbound', _('Outbound'),
		_('Tag of an outbound for connecting to the dns server.'));
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
	so.default = 'direct-out';
	so.rmempty = false;
	so.editable = true;
	/* DNS servers end */
}

return baseclass.extend({ renderRoutingNodes, renderDnsServers });
