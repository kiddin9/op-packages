'use strict';
'require poll';
'require rpc';

// run/test/restore are backgrounded by rpcd ({started:true}); the only way to
// see how they went is to tail `log` until a terminal line appears. LuCI hands
// every view the same instance: one operation at a time per view.

var callLog = rpc.declare({
	object: 'luci.gitbackup',
	method: 'log',
	params: [ 'lines' ]
});

function gbFetchLog() {
	return L.resolveDefault(callLog(500), null).then(function(res) {
		return (res && res.text) || '';
	});
}

return L.Class.extend({
	callLog: callLog,

	// Resolves only once the operation is over, so a createHandlerFn button
	// stays disabled until then. Exactly one of opts.onFinish/onTimeout/onFail
	// fires.
	run: function(opts) {
		var self = this;
		var pre = opts.pre ? document.getElementById(opts.pre) : null;

		self._idle = 0;
		self._ticks = 0;
		self._lines = 0;
		self._done = false;

		if (pre) {
			pre.hidden = false;
			pre.textContent = '';
		}

		return new Promise(function(resolve) {
			self._opts = opts;
			self._resolve = resolve;

			// Baseline before the call, or the operation's first line is missed.
			gbFetchLog().then(function(text) {
				self._lines = text ? text.split('\n').length : 0;

				if (!self._bound)
					self._bound = L.bind(self._tick, self);

				poll.remove(self._bound);
				poll.add(self._bound, 2);

				return opts.call();
			}).then(function(res) {
				if (!res || res.started !== true)
					throw new Error((res && res.reason) || '');
			}).catch(function(e) {
				self._end(opts.onFail, e.message);
			});
		});
	},

	stop: function() {
		if (this._bound)
			poll.remove(this._bound);
	},

	_append: function(add) {
		var pre = this._opts.pre ? document.getElementById(this._opts.pre) : null;

		if (!pre)
			return;

		pre.textContent = pre.textContent ? pre.textContent + '\n' + add : add;
		pre.scrollTop = pre.scrollHeight;
	},

	_end: function(cb, arg) {
		if (this._done)
			return;
		this._done = true;
		this.stop();
		if (cb)
			cb(arg);
		this._resolve();
	},

	_tick: function() {
		var self = this;
		var opts = self._opts;

		self._ticks++;

		return callLog(500).then(function(res) {
			var lines = ((res && res.text) || '').split('\n');
			var newLines = (lines.length >= self._lines) ? lines.slice(self._lines) : lines;
			var add = newLines.filter(function(l) { return l; }).join('\n');
			var matched = null;
			var i;

			self._lines = lines.length;

			if (add) {
				self._idle = 0;
				self._append(add);
				for (i = 0; i < newLines.length; i++) {
					if (opts.terminalRe.test(newLines[i]))
						matched = newLines[i];
				}
			} else {
				self._idle++;
			}

			if (matched !== null)
				self._end(opts.onFinish, matched);
			else if (self._idle >= 30 || self._ticks >= 150)
				self._end(opts.onTimeout);
		}, function() {
			self._end(opts.onTimeout);
		});
	}
});
