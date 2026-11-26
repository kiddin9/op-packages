'use strict';

import * as ubus from 'ubus';
import * as engine from 'tencentddns.engine';

function valid_section(s) {
	return (type(s) == 'string' && length(s) > 0 && length(s) <= 64 && match(s, /^[A-Za-z0-9_]+$/) != null);
}

const methods = {
	get_status: {
		call: function() {
			return engine.get_runtime_status();
		}
	},

	get_logs: {
		args: { lines: 200 },
		call: function(req) {
			let n = int(req.args?.lines || 200);
			if (n != n || n < 10)
				n = 200;
			if (n > 2000)
				n = 2000;
			return {
				logs: engine.read_logs(n)
			};
		}
	},

	clear_logs: {
		call: function() {
			engine.clear_logs();
			return { ok: true };
		}
	},

	sync_now: {
		args: { section: '', force: true },
		call: function(req) {
			let sec = req.args?.section || '';
			if (length(sec) > 0 && !valid_section(sec))
				return { ok: false, error: 'Invalid section identifier' };

			let force = (req.args?.force !== false);

			// Prefer non-blocking dispatch to running daemon via ubus if active
			let ctx = ubus.connect();
			if (ctx) {
				let res = ctx.call('tencentddns', 'sync', {
					section: sec,
					force: force
				});
				ctx.disconnect();
				if (type(res) == 'object' && res != null && res.ok)
					return { ok: true, mode: 'daemon', queued: res.queued };
			}

			// Fallback when daemon is stopped: spawn detached background one-shot sync
			// so single-threaded rpcd never blocks on external network timeouts.
			let cmd = '/usr/bin/ucode /usr/bin/tencentddns sync';
			if (force)
				cmd += ' --force';
			if (length(sec) > 0)
				cmd += ' ' + sec;
			cmd += ' >/dev/null 2>&1 &';

			let rc = system(cmd, 3000);
			return { ok: (rc == 0), mode: 'background' };
		}
	},

	test_rule: {
		args: { section: '' },
		call: function(req) {
			let sec = req.args?.section || '';
			if (length(sec) > 0 && !valid_section(sec))
				return { ok: false, error: 'Invalid section identifier' };
			return engine.test_rule_connectivity(length(sec) > 0 ? sec : null);
		}
	},

	service_action: {
		args: { action: 'restart' },
		call: function(req) {
			let act = '' + (req.args?.action || '');
			if (act != 'start' && act != 'stop' && act != 'restart' && act != 'reload')
				return { ok: false, error: 'Unsupported service action' };
			let rc = system([ '/etc/init.d/tencentddns', act ], 5000);
			return { ok: (rc == 0), code: rc };
		}
	}
};

return { 'luci.tencentddns': methods };
