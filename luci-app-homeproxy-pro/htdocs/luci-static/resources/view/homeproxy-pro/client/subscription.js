/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';

'require baseclass';
'require form';
'require uci';

'require homeproxy-pro as hp';

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
	ss.modaltitle = L.bind(hp.loadModalTitle, hp, _('Rule set'), _('Add a rule set'), 'homeproxy-pro');
	ss.sectiontitle = L.bind(hp.loadDefaultLabel, this, 'homeproxy-pro');
	/* Plain wrapper, not L.bind(): see hp.renderSectionAdd() for why the bound
	 * form hands a call site's button factory to the wrong argument. */
	ss.renderSectionAdd = function(extra_class) {
		return hp.renderSectionAdd(ss, extra_class);
	};

	so = ss.option(form.Value, 'label', _('Label'));
	so.load = L.bind(hp.loadDefaultLabel, this, 'homeproxy-pro');
	so.validate = L.bind(hp.validateUniqueValue, this, 'homeproxy-pro', 'ruleset', 'label');
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

	so = ss.option(form.ListValue, 'format', _('Format'),
		_('Rule-set file format. Leave it empty and HomeProxy reads it from the file itself; a value that does not match the file is corrected and reported in the log.'));
	so.value('binary', _('Binary file'));
	so.value('source', _('Source file'));
	/* rmempty, and no default.
	 *
	 * A default of 'binary' plus rmempty=false meant EVERY local rule-set
	 * carried an explicit format - and an explicit value beats sing-box's
	 * extension inference, so "add a local rule-set, pick my example.json,
	 * forget to change Format" produced a configuration that parsed JSON as
	 * a compiled .srs and was rejected at apply time.
	 *
	 * Leaving the field empty is now the recommended state rather than an
	 * accident: the generator reads the first bytes of the file and declares
	 * the format itself (generator/ruleset.uc's resolveFormat), correcting a
	 * wrong value and saying so in the log.  Writing a default here would
	 * put a value back on every rule-set for that code to undo. */
	so.rmempty = true;

	so = ss.option(form.Value, 'path', _('Path'),
		_('Rule-set file in %s. Copy it there first: the generator refuses a rule-set whose file is missing.').format('/etc/homeproxy-pro/ruleset/'));
	so.datatype = 'file';
	/* The archive is the only directory the backend admits (RULE_PATH_ROOTS),
	 * and it is created for the user - at install time and again before every
	 * generation. Offering it as the datalist entry is what turns "point at a
	 * file under a directory that may not exist" into a one-click default.
	 * The same field used to carry a placeholder naming example.json while
	 * the UI defaulted the format to binary, so the file it suggested was one
	 * the generated configuration would then refuse to parse. */
	so.value(hp.rule_path_default);
	so.placeholder = hp.rule_path_default;
	so.validate = hp.validateRuleSetPath;
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
		uci.sections('homeproxy-pro', 'routing_node', (res) => {
			if (res.enabled === '1')
				this.value(res['.name'], res.label);
		});

		return this.super('load', section_id);
	}
	so.depends('type', 'remote');

	so = ss.option(form.Value, 'initial_path', _('Initial path'),
		_('Local file with initial rule-set content; avoids blocking startup on first download (1.14). Must be under %s.').format('/etc/homeproxy-pro/ruleset/'));
	so.datatype = 'file';
	so.value(hp.rule_path_default);
	so.placeholder = hp.rule_path_default;
	so.validate = hp.validateRuleSetPath;
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
		_('Update interval of rule set, e.g. 24h or 3600 (seconds).'));
	/* 24h, not 1d.
	 *
	 * sing-box parses update_interval as a Go duration, and Go's units are
	 * ns/us/ms/s/m/h - there is no day.  The placeholder used to read "1d",
	 * which is the one value a user is most likely to copy verbatim into a
	 * field that then rejects the whole configuration.  24h is the same
	 * interval, is a unit Go reads, and is exactly what this generator emits
	 * for its own built-in rule-sets (generator/route.uc).
	 *
	 * A bare number is accepted because the generator normalises it: the
	 * value is passed through strToTime(), which appends "s" to anything
	 * that does not already end in a unit - that is the fix for the measured
	 * `time: missing unit in duration "3600"` failure. */
	so.placeholder = '24h';
	so.validate = function(section_id, value) {
		/* Empty means "no update_interval", which sing-box reads as its own
		 * default - the field is optional, so it must not be made required. */
		if (!section_id || !value)
			return true;

		/* What Go's time.ParseDuration accepts: a sequence of
		 * number+unit groups (so 1h30m is fine), or a bare number, which
		 * strToTime() will turn into seconds.  Everything else - "1d", "1w",
		 * "daily", "24 h" - is refused here, on the page, instead of becoming
		 * a rejected configuration the user only learns about from a log. */
		if (/^\d+$/.test(value) || /^(\d+(\.\d+)?(ns|us|µs|ms|s|m|h))+$/.test(value))
			return true;

		return _('Expecting: %s').format(_('update interval like 24h, 1h30m or 3600'));
	};
	so.depends('type', 'remote');
	/* Rule set settings end */
}

return baseclass.extend({ render });
