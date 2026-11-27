'use strict';
'require view';
'require form';
'require uci';

return view.extend({
	load: function() {
		return uci.load('uniwrt');
	},

	render: function() {
		var m, s, o;

		m = new form.Map('uniwrt', _('UniWRT Theme'),
			_('Configure the appearance of the UniWRT Portal theme. Changes apply after saving and reloading the page.'));

		/* ---- Appearance ---- */
		s = m.section(form.NamedSection, 'global', 'global', _('Appearance'));
		s.anonymous = true;

		o = s.option(form.ListValue, 'mode', _('Theme mode'),
			_('"Auto" follows your operating system\'s light/dark preference. The header toggle can override this per-browser.'));
		o.value('auto', _('Auto (follow system)'));
		o.value('light', _('Light'));
		o.value('dark', _('Dark'));
		o.default = 'auto';

		o = s.option(form.ListValue, 'font_size', _('Base font size'),
			_('Scales all text in the interface.'));
		o.value('13', _('Small (13px)'));
		o.value('14', _('Normal (14px)'));
		o.value('16', _('Large (16px)'));
		o.value('18', _('Extra large (18px)'));
		o.default = '14';

		o = s.option(form.Flag, 'rail_collapsed', _('Collapse navigation by default'),
			_('Start with the side navigation rail collapsed to icons on desktop.'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Flag, 'menu_expanded', _('Expand all menu sections'),
			_('Start with all sections open and toggle each one independently. When disabled, opening a section closes the previous one.'));
		o.default = '0';
		o.rmempty = false;

		/* ---- Accent colours ---- */
		s = m.section(form.NamedSection, 'global', 'global', _('Accent Colour'));
		s.anonymous = true;

		function colorWidget(section_id) {
			var el = form.Value.prototype.renderWidget.apply(this, arguments);
			var input = el.querySelector('input');
			if (input) { input.type = 'color'; input.style.height = '2.6rem'; input.style.width = '4rem'; input.style.cursor = 'pointer'; input.style.padding = '3px'; }
			return el;
		}

		/* only #RGB / #RRGGBB — the theme writes these straight into CSS */
		function validateHex(section_id, value) {
			return (value == null || value === '' || /^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6})$/.test(value))
				? true : _('Expecting a colour in #RRGGBB format');
		}

		o = s.option(form.Value, 'accent', _('Accent (light mode)'),
			_('Primary colour for links, active items and buttons in light mode.'));
		o.default = '#006fff';
		o.placeholder = '#006fff';
		o.renderWidget = colorWidget;
		o.validate = validateHex;

		o = s.option(form.Value, 'dark_accent', _('Accent (dark mode)'),
			_('Primary colour for links, active items and buttons in dark mode.'));
		o.default = '#4797ff';
		o.placeholder = '#4797ff';
		o.renderWidget = colorWidget;
		o.validate = validateHex;

		/* ---- Dashboard ---- */
		s = m.section(form.NamedSection, 'global', 'global', _('Dashboard & Status'));
		s.anonymous = true;

		o = s.option(form.Flag, 'status_bar', _('Live header status bar'),
			_('Show CPU, memory, throughput and uptime chips in the header. Disable to reduce polling on low-end devices.'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Flag, 'overview', _('UniWRT Overview page'),
			_('Add a custom live "Overview" dashboard entry to the menu.'));
		o.default = '1';
		o.rmempty = false;

		/* ---- Network map ---- */
		s = m.section(form.NamedSection, 'global', 'global', _('Network Map'));
		s.anonymous = true;

		o = s.option(form.ListValue, 'netmap_interval', _('Refresh interval'),
			_('How often the map asks the router for new data while it is open. Longer intervals mean less work for low-end routers; nothing is polled while the map is closed or the browser tab is hidden.'));
		o.value('3', _('3 seconds'));
		o.value('5', _('5 seconds'));
		o.value('10', _('10 seconds'));
		o.value('30', _('30 seconds'));
		o.default = '5';

		o = s.option(form.Flag, 'netmap_discover', _('Find device IP addresses on access points'),
			_('When this router is an access point behind a main router, it does not hand out IP addresses and so does not know them. While the map is open, the router briefly pings each address of its LAN every 5 minutes (at most 16 at a time) to learn them. Has no effect on a main router.'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Flag, 'netmap_animate', _('Animate live traffic'),
			_('Show moving lines where traffic flows. Runs in your browser only; it does not affect the router.'));
		o.default = '1';
		o.rmempty = false;

		return m.render();
	}
});
