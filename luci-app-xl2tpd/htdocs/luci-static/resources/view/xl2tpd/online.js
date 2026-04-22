'use strict';
'require view';
'require fs';
'require ui';
'require rpc';

return view.extend({
	load: function() {
		return fs.lines('/tmp/xl2tpd/clients');
	},

	updateTable: function(table, data) {
		var rows = [];

		for (var i = 0; i < data.length; i++) {
			var client = data[i];
			var info = client.split(';').map((part) => part.split(':')[1]);

			rows.push([
				info[0],
				info[1],
				info[2]
			]);
		}

		cbi_update_table(table, rows, E('em', _('No information available')));
	},

	render: function(data) {
		var v = E([], [
			E('h2', _('L2TP Server')),
			E('div', { 'class': 'cbi-map-descr' }, _('Simple, quick and convenient L2TP VPN, universal across the platform')),

			E('table', { 'class': 'table' }, [
				E('tr', { 'class': 'tr table-titles' }, [
					E('th', { 'class': 'th' }, _('Interface')),
					E('th', { 'class': 'th' }, _('Server IP')),
					E('th', { 'class': 'th' }, _('Client IP'))
				])
			])
		]);

		this.updateTable(v.lastElementChild, data);

		return v;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
