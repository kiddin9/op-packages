'use strict';
'require poll';

// gitbackup -- shared bounded live-log poller (ticket 23, spec "Не
// изобретать четвёртый механизм"). Before this file existed, overview.js
// (run/test), history.js (restore) and settings.js (test) each carried
// their own, separately-typed copy of the exact same state machine: fetch
// a log tail, diff it against the line count from the previous tick, feed
// the new lines to a caller-supplied terminal-line regex, and give up
// after 60s of no new output or a hard 5-minute ceiling regardless --
// interfaces.md's own record of tickets 11-14 already names this bound
// three times over ("терминальная строка лога, простой в 60 секунд,
// жёсткий потолок в 5 минут"), copied rather than shared. Ticket 23's own
// acceptance criterion ("механизм поллинга один на все три view, а не
// четыре разных") asks for exactly one implementation of that shape; this
// is it.
//
// LuCI's own require() resolves a module ONCE per page and hands back the
// same already-instantiated singleton to every caller (luci.js:
// `compileClass`'s `new _class()`, cached in `classes[name]`) -- so every
// one of the three views above sharing this same instance is safe only
// because each of them is its own full page load (classic multi-page LuCI
// tears down the whole JS context on tab switch) AND never runs two such
// pollers from itself at once (the button(s) a poller was started from
// stay disabled for its entire run). start() below resets every piece of
// this instance's state, so a second, later operation on the very same
// page (e.g. overview.js's "Backup now" followed later by its own "Test
// connection") reuses the same instance cleanly once the first one has
// actually stopped.
return L.Class.extend({
	// start(opts) -- begins polling opts.fetch() every opts.interval
	// seconds (default 2, matching every prior copy of this poller).
	// opts.fetch() must resolve to the log's current text tail (a
	// rejected fetch is treated as "no output this tick", same as an
	// empty string, and repeated failures alone can still trip the idle
	// bound below). Returns a promise that resolves once the FIRST fetch
	// (establishing the starting line count) has completed and polling
	// has actually started -- callers await this before firing the
	// backgrounded CLI call itself, exactly like every prior copy of this
	// poller did, so a very fast operation's own first output line is
	// never missed.
	//
	// opts.terminalRe (RegExp, required) -- tested against each newly
	// arrived line; a match stops the poller and fires opts.onFinish.
	// opts.onProgress(addedText), if given, fires on every tick that saw
	// new output at all, with only the lines new since the previous tick
	// (already newline-joined, blank lines dropped) -- never the whole
	// accumulated text, so a caller appending it to a growing <pre> never
	// duplicates a line.
	// opts.onFinish(matchedLine), if given, fires exactly once, after the
	// poller has already stopped itself, with the one line that matched
	// opts.terminalRe.
	// opts.onTimeout(), if given, fires exactly once, after the poller has
	// already stopped itself, when opts.idleLimit ticks (default 30 == 60s
	// at the default 2s interval) passed with no new output at all, when
	// opts.tickLimit ticks (default 150 == 5 minutes) is reached
	// regardless, or when opts.fetch() itself keeps rejecting for that
	// same idle span -- three different reasons this project's own
	// interfaces.md has always treated as one bound ("простой... либо
	// потолок"), not three outcomes a caller has to tell apart.
	start: function(opts) {
		var self = this;

		self._opts = opts;
		self._idle = 0;
		self._ticks = 0;
		self._lines = 0;

		return opts.fetch().then(function(text) {
			text = text || '';
			self._lines = text ? text.split('\n').length : 0;

			if (!self._bound)
				self._bound = L.bind(self._tick, self);

			poll.remove(self._bound);
			poll.add(self._bound, opts.interval || 2);
		});
	},

	// stop() -- idempotent; safe to call whether or not a poll is
	// currently running (every call site here does, on the "could not
	// even start the operation" path, whether or not start() got as far
	// as poll.add).
	stop: function() {
		if (this._bound)
			poll.remove(this._bound);
	},

	_tick: function() {
		var self = this;
		var opts = self._opts;
		var idleLimit = opts.idleLimit || 30;
		var tickLimit = opts.tickLimit || 150;

		self._ticks++;

		return opts.fetch().then(function(text) {
			var lines, newLines, add, finished, matchedLine, i;

			text = text || '';
			lines = text.split('\n');
			newLines = (lines.length >= self._lines) ? lines.slice(self._lines) : lines;
			add = newLines.filter(function(l) { return l; }).join('\n');
			finished = false;
			matchedLine = null;

			self._lines = lines.length;

			if (add) {
				self._idle = 0;
				if (opts.onProgress)
					opts.onProgress(add);
				for (i = 0; i < newLines.length; i++) {
					if (opts.terminalRe.test(newLines[i])) {
						finished = true;
						matchedLine = newLines[i];
					}
				}
			} else {
				self._idle++;
			}

			if (finished) {
				self.stop();
				if (opts.onFinish)
					opts.onFinish(matchedLine);
			} else if (self._idle >= idleLimit || self._ticks >= tickLimit) {
				self.stop();
				if (opts.onTimeout)
					opts.onTimeout();
			}
		}, function() {
			// A single failed poll must not spin forever either -- same
			// convention every prior copy of this poller used (count it
			// as a big idle jump rather than a distinct error path).
			self._idle += idleLimit;
			if (self._idle >= idleLimit) {
				self.stop();
				if (opts.onTimeout)
					opts.onTimeout();
			}
		});
	}
});
