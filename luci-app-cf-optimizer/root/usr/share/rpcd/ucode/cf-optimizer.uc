'use strict';

import { connect } from 'ubus';
import { access, readfile, writefile, stat, popen } from 'fs';

function exec(cmd) {
	let p = popen(cmd, 'r');
	if (!p) return { code: -1, stdout: [] };
	let out = [];
	while (true) {
		let line = p.read('line');
		if (line == null) break;
		push(out, rtrim(line, '\r\n'));
	}
	let code = p.close();
	return { code: code, stdout: out };
}

const _trim = trim;
function trim_str(s) {
	if (s == null) return '';
	return _trim('' + s);
}

function get_procd_status() {
	let u = connect();
	if (!u) return { running: false };

	let res = u.call('service', 'list', { name: 'cf-optimizer' });
	if (res && res['cf-optimizer'] && res['cf-optimizer'].instances) {
		let instances = res['cf-optimizer'].instances;
		for (let name in instances) {
			let inst = instances[name];
			if (inst && inst.running)
				return { running: true, pid: inst.pid };
		}
	}

	let pid_res = exec('pidof cf-optimizer 2>/dev/null');
	if (pid_res.code == 0 && length(pid_res.stdout) > 0) {
		let pids = split(trim_str(join(' ', pid_res.stdout)), /\s+/);
		if (length(pids) > 0 && pids[0] != '')
			return { running: true, pid: +pids[0] };
	}

	return { running: false };
}

const methods = {};

methods.get_status = {
	call: function() {
		let proc_st = get_procd_status();
		let status_data = null;

		const status_file = '/tmp/run/cf-optimizer/status.json';
		if (access(status_file)) {
			let content = readfile(status_file);
			if (content) {
				try {
					status_data = json(content);
				} catch(e) {}
			}
		}

		if (!status_data) {
			status_data = {
				running: proc_st.running,
				last_update: '',
				best_ip: '',
				best_colo: '',
				best_tcp_lat: '',
				best_tls_lat: '',
				domains: [],
				rankings: []
			};
		}

		status_data.service_running = proc_st.running;
		status_data.service_pid = proc_st.pid || null;

		return status_data;
	}
};

methods.get_logs = {
	call: function() {
		const log_file = '/var/log/cf-optimizer.log';
		let logs = [];
		if (access(log_file)) {
			let res = exec('tail -n 120 ' + log_file + ' 2>/dev/null');
			if (res.code == 0) logs = res.stdout;
		}
		return { logs: logs };
	}
};

methods.clear_logs = {
	call: function() {
		const log_file = '/var/log/cf-optimizer.log';
		writefile(log_file, '');
		return { success: true };
	}
};

methods.run_once = {
	call: function() {
		exec('/usr/sbin/cf-optimizer run >/dev/null 2>&1 &');
		return { success: true };
	}
};

methods.service_action = {
	args: { action: 'action' },
	call: function(req) {
		let action = req.args?.action;
		if (!action) return { success: false, error: 'Missing action parameter' };

		if (action == 'restart') {
			exec('/etc/init.d/cf-optimizer restart >/dev/null 2>&1');
		} else if (action == 'start') {
			exec('/etc/init.d/cf-optimizer start >/dev/null 2>&1');
		} else if (action == 'stop') {
			exec('/etc/init.d/cf-optimizer stop >/dev/null 2>&1');
		}
		return { success: true };
	}
};

return { 'luci.cf-optimizer': methods };
