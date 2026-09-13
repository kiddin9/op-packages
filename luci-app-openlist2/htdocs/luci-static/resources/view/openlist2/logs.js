'use strict';
'require fs';
'require poll';
'require ui';
'require view';

const HELPER = '/usr/libexec/openlist2-helper';
let logTextarea, errorMessage;

const formatLog = text => (text || '').replace(/\u001b\[[0-9;]*m/g, '').trim() || _('No log data.');

const pollLog = () => {
	if (!logTextarea)
		return Promise.resolve();

	return fs.exec(HELPER, ['log-read']).then(result => {
		if (result.code !== 0)
			throw new Error((result.stderr || _('Unable to read the log.')).trim());

		// Decide before replacing text, so programmatic scrolling is not
		// mistaken for the user scrolling away from the bottom.
		const atBottom = logTextarea.scrollTop + logTextarea.clientHeight >= logTextarea.scrollHeight - 10;
		const position = logTextarea.scrollTop;
		logTextarea.value = formatLog(result.stdout);
		logTextarea.scrollTop = atBottom ? logTextarea.scrollHeight : position;
		errorMessage.textContent = '';
		errorMessage.hidden = true;
	}).catch(error => {
		errorMessage.textContent = _('Unable to read the log: %s').format(error.message);
		errorMessage.hidden = false;
	});
};

return view.extend({
	handleCleanLogs() {
		if (!L.hasViewPermission())
			return Promise.resolve();
		return fs.exec(HELPER, ['log-clear']).then(result => {
			if (result.code !== 0)
				throw new Error((result.stderr || _('Unable to clear the log.')).trim());
			return pollLog();
		}).catch(error => ui.addNotification(null, E('p', error.message)));
	},

	render() {
		logTextarea = E('textarea', {
			'id': 'log_content',
			'class': 'cbi-input-textarea',
			'wrap': 'off',
			'readonly': 'readonly',
			'style': 'width:100%;height:535px;overflow:auto;'
		}, _('Collecting data...'));
		errorMessage = E('p', { 'class': 'alert-message warning', 'role': 'status', 'hidden': true });
		const clearButton = E('button', {
			'class': 'btn cbi-button-action',
			'type': 'button',
			'disabled': !L.hasViewPermission(),
			'click': ui.createHandlerFn(this, 'handleCleanLogs')
		}, _('Clear current log'));

		poll.add(pollLog);
		return E('div', { 'class': 'cbi-map' }, [
			E('div', { 'class': 'cbi-section' }, [
				E('p', {}, _('Showing up to the last 200 lines and 16 KiB. Older entries remain in the log files.')),
				clearButton,
				errorMessage,
				logTextarea,
				E('p', { 'style': 'text-align:right' },
					_('Refresh every %s seconds.').format(L.env.pollinterval))
			])
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
