'use strict';
'require fs';
'require poll';
'require uci';
'require ui';
'require view';

const DEFAULT_LOG_PATH = '/var/log/openlist2.log';

let scrollPosition = 0;
let userScrolled = false;
let logTextarea;
let log_path = DEFAULT_LOG_PATH;

const isSafeLogPath = value => /^\/var\/log\/openlist2(?:[._-][A-Za-z0-9._-]+)?$/.test(value || '');

const formatLog = res => {
	const log = (res || '').trim().replace(/\u001b\[[0-9;]*m/g, '');

	return log || _('No log data.');
};

const pollLog = () => {
	if (!logTextarea)
		return Promise.resolve();

	return fs.read_direct(log_path, 'text')
		.then(formatLog)
		.catch(() => _('No log data.'))
		.then(log => {
			logTextarea.value = log;

			if (!userScrolled) {
				logTextarea.scrollTop = logTextarea.scrollHeight;
			} else {
				logTextarea.scrollTop = scrollPosition;
			}
		});
};

return view.extend({
	load() {
		return uci.load('openlist2');
	},

	handleCleanLogs() {
		return fs.write(log_path, '')
			.then(pollLog)
			.catch(e => {
				ui.addNotification(null, E('p', e.message));
			});
	},

	render() {
		const configuredLogPath = uci.get('openlist2', '@openlist2[0]', 'log_path');
		log_path = isSafeLogPath(configuredLogPath) ? configuredLogPath : DEFAULT_LOG_PATH;

		logTextarea = E('textarea', {
			'id': 'log_content',
			'class': 'cbi-input-textarea',
			'wrap': 'off',
			'readonly': 'readonly',
			'style': 'width: calc(100% - 20px);height: 535px;margin: 10px;overflow-y: scroll;',
		});

		logTextarea.addEventListener('scroll', () => {
			userScrolled = true;
			scrollPosition = logTextarea.scrollTop;
		});

		const log_textarea_wrapper = E('div', { 'id': 'log_textarea' }, logTextarea);

		setTimeout(() => {
			poll.add(pollLog);
		}, 100);

		const clear_logs_button = E('input', { 'class': 'btn cbi-button-action', 'type': 'button', 'style': 'margin-left: 10px; margin-top: 10px;', 'value': _('Clear logs') });
		clear_logs_button.addEventListener('click', L.bind(this.handleCleanLogs, this));

		return E([
			E('div', { 'class': 'cbi-map' }, [
				E('div', { 'class': 'cbi-section' }, [
					clear_logs_button,
					log_textarea_wrapper,
					E('div', { 'style': 'text-align:right' },
						E('small', {}, _('Refresh every %s seconds.').format(L.env.pollinterval))
					)
				])
			])
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
