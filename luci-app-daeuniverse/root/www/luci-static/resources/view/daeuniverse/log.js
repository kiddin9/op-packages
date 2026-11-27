'use strict';
'require view';
'require ui';
'require uci';
'require daeuniverse.common as daeu';

return view.extend({
	load: function() {
		return uci.load('daeuniverse');
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	render: function() {
		var scrolled = false;

		var logTextarea = E('textarea', {
			'id': 'log_textarea',
			'class': 'cbi-input-textarea',
			'style': 'width: 100%; height: 600px; font-family: var(--font-mono, monospace); font-size: 12px; line-height: 1.4; box-sizing: border-box; resize: vertical;',
			'rows': 25,
			'wrap': 'off',
			'readonly': 'readonly'
		});

		var btnClear = E('button', {
			'type': 'button',
			'class': 'btn cbi-button cbi-button-remove',
			'click': function() {
				btnClear.disabled = true;
				daeu.callClearLog().then(function() {
					btnClear.disabled = false;
					logTextarea.value = '';
					logTextarea.scrollTop = 0;
					scrolled = false;
					daeu.showNotification(null, E('p', _('Logs cleared successfully.')), 'info');
				}).catch(function(err) {
					btnClear.disabled = false;
					daeu.showNotification(null, E('p', _('Failed to clear logs:') + ' ' + (err.message || err)), 'error');
				});
			}
		}, _('Clear logs'));

		function updateLog() {
			return daeu.callGetLog().then(function(data) {
				var content = (data && data.log) ? data.log : '';
				var atBottom = !scrolled || (logTextarea.scrollHeight - logTextarea.scrollTop - logTextarea.clientHeight < 50);
				logTextarea.value = content;
				if (atBottom && content) {
					logTextarea.scrollTop = logTextarea.scrollHeight;
					scrolled = true;
				}
			});
		}

		updateLog();

		var onVisibilityChange;

		var logPollFn = function() {
			if (document.hidden) {
				return Promise.resolve();
			}
			return updateLog().catch(function() { });
		};

		daeu.addElementPoll(logPollFn, logTextarea, 3, function() {
			if (onVisibilityChange) {
				document.removeEventListener('visibilitychange', onVisibilityChange);
			}
		});

		onVisibilityChange = function() {
			if (!document.body.contains(logTextarea)) {
				document.removeEventListener('visibilitychange', onVisibilityChange);
				return;
			}
			if (!document.hidden) {
				updateLog();
			}
		};

		document.addEventListener('visibilitychange', onVisibilityChange);

		return E('fieldset', { 'class': 'cbi-section', 'id': '_log_fieldset' }, [
			E('legend', {}, _('Logs')),
			E('div', { 'style': 'margin-bottom: 10px;' }, [ btnClear ]),
			logTextarea
		]);
	}
});
