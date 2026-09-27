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

/* Rule set sub-grid (per-rule-set entries: local file or remote URL with
 * download metadata). Called after dns.renderDnsRules() so the
 * ruleset tab appears after the dns_rule sub-tab. */
function render(ctx) {
	const { s } = ctx;
	let o, ss, so;

	s.tab('ruleset', _('Rule Set'));
	o = s.taboption('ruleset', form.SectionValue, '_ruleset', form.GridSection, 'ruleset');
	o.depends('routing_mode', 'custom');

	ss = o.subsection;
	ss.addremove = true;
	ss.rowcolors = true;
	ss.sortable = true;
	ss.nodescriptions = true;
	ss.modaltitle = L.bind(hp.loadModalTitle, hp, _('Rule set'), _('Add a rule set'), 'homeproxy');
	ss.sectiontitle = L.bind(hp.loadDefaultLabel, this, 'homeproxy');
	/* Plain wrapper, not L.bind(): see hp.renderSectionAdd() for why the bound
	 * form hands a call site's button factory to the wrong argument. */
	ss.renderSectionAdd = function(extra_class) {
		return hp.renderSectionAdd(ss, extra_class);
	};

	so = ss.option(form.Value, 'label', _('Label'));
	so.load = L.bind(hp.loadDefaultLabel, this, 'homeproxy');
	so.validate = L.bind(hp.validateUniqueValue, this, 'homeproxy', 'ruleset', 'label');
	so.modalonly = true;

	so = ss.option(form.Flag, 'enabled', _('Enable'));
	so.default = so.enabled;
	so.rmempty = false;
	so.editable = true;

	so = ss.option(form.ListValue, 'type', _('Type'));
	so.value('local', _('Local'));
	so.value('remote', _('Remote'));
	so.default = 'remote';
	so.rmempty = false;

	so = ss.option(form.ListValue, 'format', _('Format'));
	so.value('binary', _('Binary file'));
	so.value('source', _('Source file'));
	so.default = 'binary';
	so.rmempty = false;

	so = ss.option(form.Value, 'path', _('Path'));
	so.datatype = 'file';
	so.placeholder = '/etc/homeproxy/ruleset/example.json';
	so.rmempty = false;
	so.depends('type', 'local');
	so.modalonly = true;

	so = ss.option(form.Value, 'url', _('Rule set URL'));
	so.validate = function(section_id, value) {
		if (section_id) {
			if (!value)
				return _('Expecting: %s').format(_('non-empty value'));
			let extra = this.section.formvalue(section_id, 'extra_tags') || [];
			if (extra.length && !value.includes('{tag}'))
				return _('Expecting: %s').format(_('{tag} in URL when extra tags are used'));

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
	so.rmempty = false;
	so.depends('type', 'remote');
	so.modalonly = true;

	so = ss.option(form.ListValue, 'outbound', _('Outbound'),
		_('Outbound used to download this rule-set (via sing-box 1.14 http_clients).'));
	so.load = function(section_id) {
		delete this.keylist;
		delete this.vallist;

		this.value('', _('Default'));
		this.value('direct-out', _('Direct'));
		uci.sections('homeproxy', 'routing_node', (res) => {
			if (res.enabled === '1')
				this.value(res['.name'], res.label);
		});

		return this.super('load', section_id);
	}
	so.depends('type', 'remote');

	so = ss.option(form.Value, 'initial_path', _('Initial path'),
		_('Local file with initial rule-set content; avoids blocking startup on first download (1.14).'));
	so.datatype = 'file';
	so.depends('type', 'remote');
	so.modalonly = true;

	so = ss.option(form.DynamicList, 'extra_tags', _('Extra tags'),
		_('Extra rule-set tags sharing these options. Requires {tag} in path/url (1.14).'));
	so.depends('type', 'remote');
	so.validate = function(section_id, value) {
		if (section_id && value && value.length) {
			let rule_url = this.section.formvalue(section_id, 'url') || '';
			if (!rule_url.includes('{tag}'))
				return _('Expecting: %s').format(_('{tag} in URL when extra tags are used'));
			let rule_initial = this.section.formvalue(section_id, 'initial_path') || '';
			if (rule_initial && !rule_initial.includes('{tag}'))
				return _('Expecting: %s').format(_('{tag} in initial path when extra tags are used'));
		}
		return true;
	}
	so.modalonly = true;

	so = ss.option(form.Value, 'update_interval', _('Update interval'),
		_('Update interval of rule set.'));
	so.placeholder = '1d';
	so.depends('type', 'remote');
	/* Rule set settings end */
}

return baseclass.extend({ render });
