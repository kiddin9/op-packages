'use strict';
'require view';
'require dom';
'require fs';
'require poll';
'require ui';

var MAX_LINES = 1000;

function level(line) {
	if (/\bERROR\b|\.err\b|\.crit\b|panicked/.test(line)) return 'error';
	if (/\bWARN\b|\.warn\b/.test(line)) return 'warn';
	return '';
}

function fetchLog() {
	return fs.exec_direct('/sbin/logread', ['-e', 'meow']).then(function(out) {
		var lines = (out || '').replace(/\x1b\[[0-9;]*m/g, '').trim().split('\n');
		return lines.filter(Boolean).slice(-MAX_LINES);
	}).catch(function(e) {
		return [ _('Unable to read log: %s').format(e.message) ];
	});
}

return view.extend({
	load: fetchLog,
	show: function() {
		var pre = this.pre;
		var filter = (this.filter.value || '').toLowerCase();
		var levelValue = this.levelSel.value;
		var lines = this.lines.filter(function(l) {
			if (levelValue === 'warn' && !level(l)) return false;
			if (levelValue === 'error' && level(l) !== 'error') return false;
			return !filter || l.toLowerCase().indexOf(filter) !== -1;
		});
		var atBottom = pre.scrollHeight - pre.scrollTop - pre.clientHeight < 40;
		dom.content(pre, lines.length ? lines.map(function(l) {
			var lv = level(l);
			return E('div', { style: lv === 'error' ? 'color:#c62828;' : lv === 'warn' ? 'color:#ef6c00;' : '' }, l);
		}) : E('em', {}, _('No log entries.')));
		dom.content(this.count, _('%d of %d entries').format(lines.length, this.lines.length));
		if (atBottom || !this.scrolled) {
			pre.scrollTop = pre.scrollHeight;
			if (pre.isConnected && pre.scrollHeight > 0) this.scrolled = true;
		}
	},
	refresh: function() {
		if (this.paused) return Promise.resolve();
		return fetchLog().then(L.bind(function(lines) { this.lines = lines; this.show(); }, this));
	},
	handlePause: function() {
		this.paused = !this.paused;
		this.pauseBtn.textContent = this.paused ? _('Resume') : _('Pause');
		if (!this.paused) return this.refresh();
	},
	handleDownload: function() {
		var blob = new Blob([this.lines.join('\n') + '\n'], { type: 'text/plain' });
		var a = E('a', { href: URL.createObjectURL(blob), download: 'meow.log' });
		document.body.appendChild(a); a.click(); document.body.removeChild(a); URL.revokeObjectURL(a.href);
	},
	render: function(lines) {
		var self = this;
		this.lines = lines || [];
		this.pre = E('pre', { style: 'white-space:pre-wrap; font-size:12px; max-height:70vh; overflow:auto; margin:0;' });
		this.count = E('span', { style: 'color:#888; margin-left:auto;' });
		this.filter = E('input', { type:'text', class:'cbi-input-text', placeholder:_('Filter…'), style:'max-width:16em;', input:function(){self.show();} });
		this.levelSel = E('select', { class:'cbi-input-select', change:function(){self.show();} }, [
			E('option', { value:'all' }, _('All levels')),
			E('option', { value:'warn' }, _('Warnings and errors')),
			E('option', { value:'error' }, _('Errors only'))
		]);
		this.pauseBtn = E('button', { class:'cbi-button', click:ui.createHandlerFn(this, 'handlePause') }, _('Pause'));
		poll.add(function() { return self.refresh(); }, 5);
		var node = E('div', { class:'cbi-map' }, [
			E('h2', {}, _('meow Log')),
			E('div', { class:'cbi-map-descr' }, _('meow entries from the system log; refreshes every 5 seconds.')),
			E('div', { style:'display:flex; flex-wrap:wrap; gap:.5em; align-items:center; margin-bottom:.5em;' },
				[this.filter, this.levelSel, this.pauseBtn,
					E('button', { class:'cbi-button cbi-button-action', click:ui.createHandlerFn(this,'handleDownload') }, _('Download')),
					this.count]),
			E('div', { class:'cbi-section' }, [this.pre])
		]);
		this.show();
		return node;
	}
});
