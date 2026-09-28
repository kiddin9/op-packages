'use strict';
'require fs';
'require poll';
'require ui';
'require view';

function translateLogText(message) {
	return (typeof _ === 'function') ? _(message) : message;
}

function formatLogLine(log) {
	const logParts = String(log || '').split(' ').filter(Boolean);
	const statusMappings = {
		'daemon.err': { status: 'StdErr', startIndex: 6 },
		'daemon.notice': { status: 'Info', startIndex: 6 },
		'user.err': { status: 'StdErr', startIndex: 6 },
		'user.notice': { status: 'Info', startIndex: 6 }
	};

	if (logParts.length < 6)
		return log;

	const formattedTime = logParts.slice(0, 4).join(' ');
	const status = logParts[5];
	const mapping = statusMappings[status] || { status: status, startIndex: 6 };
	const message = logParts.slice(mapping.startIndex).join(' ');

	return `${formattedTime} [ ${mapping.status} ] - ${message}`;
}

function formatLogLines(logdata) {
	const text = String(logdata || '').trim();

	if (!text)
		return { value: translateLogText('Log is empty.'), rows: 2 };

	const loglines = text.split(/\n/).map(formatLogLine).filter(Boolean);

	return { value: loglines.join('\n'), rows: loglines.length + 1 };
}

function formatLogError(err) {
	const message = String(
		(err && (err.stderr || err.message || err.stdout)) || err || translateLogText('Unknown error')
	).trim().replace(/\n+/g, ' ');

	return {
		value: translateLogText('Unable to load log data:') + ' ' + message,
		rows: 2
	};
}

return view.extend({
	async retrieveLog() {
		const stat = await Promise.all([
			L.resolveDefault(fs.stat('/sbin/logread'), null),
			L.resolveDefault(fs.stat('/usr/sbin/logread'), null)
		]);
		const logger = stat[0] ? stat[0].path : stat[1] ? stat[1].path : null;

		if (!logger)
			return formatLogError(translateLogText('logread command not found'));

		try {
			return formatLogLines(await fs.exec_direct(logger, ['-e', 'tailscale']));
		} catch (err) {
			return formatLogError(err);
		}
	},

	async pollLog() {
		const element = document.getElementById('syslog');
		if (element) {
			try {
				const log = await this.retrieveLog();
				element.value = log.value;
				element.rows = log.rows;
			} catch (err) {
				ui.addNotification(null, E('p', {}, _('Unable to load log data: ' + err.message)));
			}
		}
	},

	load() {
		poll.add(this.pollLog.bind(this));
		return this.retrieveLog();
	},

	render(loglines) {
		const scrollDownButton = E('button', { 
				id: 'scrollDownButton',
				class: 'cbi-button cbi-button-neutral'
			}, _('Scroll to tail', 'scroll to bottom (the tail) of the log file')
		);
		scrollDownButton.addEventListener('click', function() {
			scrollUpButton.scrollIntoView();
		});

		const scrollUpButton = E('button', { 
				id : 'scrollUpButton',
				class: 'cbi-button cbi-button-neutral'
			}, _('Scroll to head', 'scroll to top (the head) of the log file')
		);
		scrollUpButton.addEventListener('click', function() {
			scrollDownButton.scrollIntoView();
		});

		return E([], [
			E('div', { id: 'content_syslog' }, [
				E('div', { style: 'padding-bottom: 20px' }, [scrollDownButton]),
				E('textarea', {
					id: 'syslog',
					style: 'font-size:12px',
					readonly: 'readonly',
					wrap: 'off',
					rows: loglines.rows,
				}, [ loglines.value ]),
				E('div', { style: 'padding-bottom: 20px' }, [scrollUpButton])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
