'use strict';

'require baseclass';

const NOTIFICATION_TIMEOUT = 2000;

const ICON = {
	START: '►',
	STOP: '◼',
	RESTART: '↻',
	PAUSE: '❚❚',
	CLEAR_LOG: '🗑️',
	INIT_ENABLED: '✓',
	INIT_MISSING: '⚠',
	INIT_DISABLED: '⏼',
	BACK: '🔙',
};

return baseclass.extend({
	NOTIFICATION_TIMEOUT,
	ICON,
});
