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

function trim(s) {
	if (s == null) return '';
	return replace('' + s, /^[\s\r\n]+|[\s\r\n]+$/g, '');
}

function get_procd_status(instance_name) {
	let u = connect();
	if (!u) return { running: false };

	let res = u.call('service', 'list', { name: 'easytier' });
	if (res && res['easytier'] && res['easytier'].instances) {
		let instances = res['easytier'].instances;
		let inst = instances[instance_name || 'core'];
		if (inst && inst.running)
			return { running: true, pid: inst.pid };
	}
	return { running: false };
}

function get_rogue_pid(bin_name, managed_pid) {
	let res = exec('pidof ' + bin_name + ' 2>/dev/null');
	if (res.code == 0 && length(res.stdout) > 0) {
		let pid_str = trim(join(' ', res.stdout));
		if (pid_str != '') {
			let pids = split(pid_str, /\s+/);
			for (let i = 0; i < length(pids); i++) {
				let pid = pids[i];
				if (pid != '' && (managed_pid == null || pid != ('' + managed_pid)))
					return +pid;
			}
		}
	}
	return null;
}

function get_service_state(bin_name, instance_name) {
	let procd_st = get_procd_status(instance_name);
	let rogue_pid = get_rogue_pid(bin_name, procd_st.pid);

	let state = 'stopped';
	if (procd_st.running)
		state = 'managed';
	else if (rogue_pid)
		state = 'unmanaged';

	return {
		state: state,
		running: (state != 'stopped'),
		pid: procd_st.pid || rogue_pid || null
	};
}

function get_cached_version() {
	const cache_file = '/tmp/easytier_version.cache';
	const bin_path = '/usr/bin/easytier-core';
	if (!access(bin_path)) return 'Unknown';

	let bin_st = stat(bin_path);
	let cache_st = access(cache_file) ? stat(cache_file) : null;

	if (cache_st && cache_st.size > 0 && bin_st && cache_st.mtime >= bin_st.mtime) {
		let cached = trim(readfile(cache_file) || '');
		if (cached != '') return cached;
	}

	let ver_res = exec(bin_path + ' --version 2>/dev/null');
	if (ver_res.code == 0 && length(ver_res.stdout) > 0) {
		let ver_line = trim(ver_res.stdout[0]);
		if (ver_line != '') {
			writefile(cache_file, ver_line + '\n');
			return ver_line;
		}
	}
	return 'Unknown';
}

const methods = {};

methods.get_status = {
	call: function() {
		let core_st = get_service_state('/usr/bin/easytier-core', 'core');
		let web_st = get_service_state('/usr/bin/easytier-web', 'web');

		let data = {
			installed: access('/usr/bin/easytier-core') ? true : false,
			web_installed: access('/usr/bin/easytier-web') ? true : false,
			version: get_cached_version(),
			core: core_st,
			web: web_st,
			node_info: null
		};

		if (core_st.running && access('/usr/bin/easytier-cli')) {
			let node_res = exec('/usr/bin/easytier-cli node 2>/dev/null');
			if (node_res.code == 0 && length(node_res.stdout) > 0) {
				data.node_info = join('\n', node_res.stdout);
			}
		}

		return data;
	}
};

function get_route_info_map() {
	let route_map = {};
	if (!access('/usr/bin/easytier-cli')) return route_map;
	let r_res = exec('/usr/bin/easytier-cli -o json route 2>/dev/null');
	if (r_res.code == 0 && length(r_res.stdout) > 0) {
		let r_data = json(join('\n', r_res.stdout));
		if (r_data && length(r_data) > 0) {
			for (let i = 0; i < length(r_data); i++) {
				let item = r_data[i];
				let cidrs = trim(item.proxy_cidrs || '');
				let ip = trim(item.ipv4 || '');
				let host = trim(item.hostname || '');
				let next_hop_host = trim(item.next_hop_hostname_lat_first || item.next_hop_hostname || '');
				let next_hop_ip = trim(item.next_hop_ipv4_lat_first || item.next_hop_ipv4 || '');
				let path_len = item.path_len_lat_first != null ? item.path_len_lat_first : item.path_len;
				let path_lat = item.path_latency_lat_first != null ? item.path_latency_lat_first : item.path_latency;

				let entry = {
					proxy_cidrs: cidrs,
					next_hop_hostname: next_hop_host,
					next_hop_ipv4: next_hop_ip,
					path_len: path_len,
					path_latency: path_lat
				};

				if (ip != '') {
					route_map[ip] = entry;
					let ip_clean = split(ip, '/')[0];
					route_map[ip_clean] = entry;
				}
				if (host != '') {
					route_map[host] = entry;
				}
			}
		}
	}
	return route_map;
}

methods.get_peers = {
	call: function() {
		if (!access('/usr/bin/easytier-cli')) {
			return { peers: [], raw: '' };
		}

		let route_map = get_route_info_map();
		let json_res = exec('/usr/bin/easytier-cli -o json peer 2>/dev/null');
		if (json_res.code == 0 && length(json_res.stdout) > 0) {
			let j_data = json(join('\n', json_res.stdout));
			if (j_data && length(j_data) > 0) {
				let peers = [];
				for (let i = 0; i < length(j_data); i++) {
					let item = j_data[i];
					let p_ip = trim(item.cidr || item.ipv4 || '');
					let p_host = trim(item.hostname || '');
					let p_ip_clean = split(p_ip, '/')[0];
					let r_entry = route_map[p_ip] || route_map[p_ip_clean] || route_map[p_host] || {};
					let proxy_cidrs = r_entry.proxy_cidrs || '';
					let next_hop_hostname = r_entry.next_hop_hostname || '';
					let next_hop_ipv4 = r_entry.next_hop_ipv4 || '';
					let path_latency = r_entry.path_latency != null ? r_entry.path_latency : '';

					push(peers, {
						ipv4: p_ip,
						hostname: p_host,
						proxy_cidrs: proxy_cidrs,
						next_hop_hostname: next_hop_hostname,
						next_hop_ipv4: next_hop_ipv4,
						path_latency: path_latency,
						cost: trim(item.cost || ''),
						latency: (item.lat_ms != null && item.lat_ms != '-') ? ('' + item.lat_ms) : '-',
						loss_rate: trim(item.loss_rate || '-'),
						rx: trim(item.rx_bytes || '-'),
						tx: trim(item.tx_bytes || '-'),
						tunnel: trim(item.tunnel_proto || '-'),
						nat: trim(item.nat_type || '-'),
						version: trim(item.version || '-')
					});
				}
				return { peers: peers, raw: '' };
			}
		}

		let peer_res = exec('/usr/bin/easytier-cli peer 2>/dev/null');
		let raw_output = (peer_res.code == 0) ? join('\n', peer_res.stdout) : '';
		let peers = [];
		if (peer_res.code == 0 && length(peer_res.stdout) > 0) {
			for (let i = 0; i < length(peer_res.stdout); i++) {
				let line = trim(peer_res.stdout[i]);
				if (line == '' || match(line, /ipv4|hostname|--/i) && match(line, /\|/)) continue;
				if (match(line, /^[-+─━=| ]+$/)) continue;

				let parts = split(line, '|');
				let cols = [];
				for (let idx = 0; idx < length(parts); idx++) {
					push(cols, trim(parts[idx]));
				}
				if (length(cols) > 0 && cols[0] == '') shift(cols);
				if (length(cols) > 0 && cols[length(cols) - 1] == '') pop(cols);

				if (length(cols) >= 2) {
					let peer_ip = trim(cols[0] || '');
					let peer_host = trim(cols[1] || '');
					let peer_ip_clean = split(peer_ip, '/')[0];
					let r_entry = route_map[peer_ip] || route_map[peer_ip_clean] || route_map[peer_host] || {};
					let proxy_cidrs = r_entry.proxy_cidrs || '';
					let next_hop_hostname = r_entry.next_hop_hostname || '';
					let next_hop_ipv4 = r_entry.next_hop_ipv4 || '';
					let path_latency = r_entry.path_latency != null ? r_entry.path_latency : '';

					push(peers, {
						ipv4: peer_ip,
						hostname: peer_host,
						proxy_cidrs: proxy_cidrs,
						next_hop_hostname: next_hop_hostname,
						next_hop_ipv4: next_hop_ipv4,
						path_latency: path_latency,
						cost: trim(cols[2] || ''),
						latency: trim(cols[3] || ''),
						loss_rate: trim(cols[4] || ''),
						rx: trim(cols[5] || ''),
						tx: trim(cols[6] || ''),
						tunnel: trim(cols[7] || ''),
						nat: trim(cols[8] || ''),
						version: trim(cols[9] || '')
					});
				}
			}
		}

		return { peers: peers, raw: raw_output };
	}
};

methods.get_logs = {
	call: function() {
		let logs = [];
		let res = exec('logread -e easytier 2>/dev/null | tail -n 80');
		if (res.code == 0 && length(res.stdout) > 0) {
			logs = res.stdout;
		} else if (access('/tmp/easytier.log')) {
			let f_res = exec('tail -n 80 /tmp/easytier.log 2>/dev/null');
			if (f_res.code == 0) logs = f_res.stdout;
		}
		return { logs: logs };
	}
};

methods.get_topology = {
	call: function() {
		if (!access('/usr/bin/easytier-cli')) {
			return { nodes: [] };
		}
		let route_map = get_route_info_map();
		let res = exec('/usr/bin/easytier-cli -o json peer-center 2>/dev/null');
		if (res.code == 0 && length(res.stdout) > 0) {
			let full_str = join('\n', res.stdout);
			let data = json(full_str);
			if (data && length(data) > 0) {
				let valid_nodes = [];
				for (let i = 0; i < length(data); i++) {
					let n_ip = trim(data[i].ipv4 || '');
					let n_host = trim(data[i].hostname || '');
					if (n_host == '' || match(n_host, /^unknown$/i)) continue;
					if (n_ip == '' || n_ip == '-') continue;

					let n_ip_clean = split(n_ip, '/')[0];
					let r_entry = route_map[n_ip] || route_map[n_ip_clean] || route_map[n_host] || {};
					data[i].proxy_cidrs = r_entry.proxy_cidrs || '';
					push(valid_nodes, data[i]);
				}
				return { nodes: valid_nodes };
			}
		}
		return { nodes: [] };
	}
};

methods.get_subroutes = {
	call: function() {
		try {
			let subnets = [];
			let seen = {};

			// 1. 尝试 ip -j route (支持 JSON 的 iproute2)
			let res = exec('ip -j route 2>/dev/null');
			if (res && res.code == 0 && length(res.stdout) > 0) {
				let routes_json = json(join('', res.stdout));
				if (routes_json && length(routes_json) > 0) {
					for (let i = 0; i < length(routes_json); i++) {
						let r = routes_json[i];
						if (r.dst && r.dst != 'default' && r.scope == 'link' && index(r.dst, '.') != -1 && r.dev != 'easytier0' && r.dev != 'lo') {
							if (!seen[r.dst]) {
								seen[r.dst] = true;
								push(subnets, r.dst);
							}
						}
					}
				}
			}

			// 2. 降级：标准文本格式 ip route (兼容 OpenWrt 21.02/BusyBox)
			if (length(subnets) == 0) {
				let txt_res = exec('ip route 2>/dev/null');
				if (txt_res && txt_res.code == 0 && length(txt_res.stdout) > 0) {
					for (let i = 0; i < length(txt_res.stdout); i++) {
						let line = trim(txt_res.stdout[i]);
						if (line == '' || match(line, /^default/i)) continue;
						if (index(line, 'easytier0') != -1 || index(line, 'lo') != -1) continue;
						let m = match(line, /^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+)\s+dev\s+([^\s]+)/);
						if (m && m[1]) {
							let subnet = m[1];
							let dev = m[2];
							if (dev != 'easytier0' && dev != 'lo' && !seen[subnet]) {
								seen[subnet] = true;
								push(subnets, subnet);
							}
						}
					}
				}
			}

			// 3. 终极兜底：通过 ubus 调用 network.interface dump 提取各接口 IPv4 直连子网
			if (length(subnets) == 0) {
				let net_res = exec('ubus call network.interface dump 2>/dev/null');
				if (net_res && net_res.code == 0 && length(net_res.stdout) > 0) {
					let net_data = json(join('', net_res.stdout));
					if (net_data && net_data.interface && length(net_data.interface) > 0) {
						for (let i = 0; i < length(net_data.interface); i++) {
							let iface = net_data.interface[i];
							if (iface.interface == 'loopback' || iface.interface == 'easytier') continue;
							if (iface['ipv4-address'] && length(iface['ipv4-address']) > 0) {
								for (let j = 0; j < length(iface['ipv4-address']); j++) {
									let addr = iface['ipv4-address'][j];
									let ip_str = addr.address;
									let mask = addr.mask;
									if (ip_str && mask) {
										let parts = split(ip_str, '.');
										if (length(parts) == 4) {
											let subnet = '';
											if (mask == 24) {
												subnet = parts[0] + '.' + parts[1] + '.' + parts[2] + '.0/24';
											} else if (mask == 16) {
												subnet = parts[0] + '.' + parts[1] + '.0.0/16';
											} else if (mask == 8) {
												subnet = parts[0] + '.0.0.0/8';
											} else {
												subnet = ip_str + '/' + mask;
											}
											if (subnet != '' && !seen[subnet]) {
												seen[subnet] = true;
												push(subnets, subnet);
											}
										}
									}
								}
							}
						}
					}
				}
			}

			return { routes: subnets };
		} catch(e) {
			return { routes: [] };
		}
	}
};

methods.clear_logs = {
	call: function() {
		writefile('/tmp/easytier.log', '');
		writefile('/tmp/easytier-web.log', '');
		return { success: true };
	}
};

methods.service_action = {
	args: { action: 'action' },
	call: function(req) {
		let action = req.args?.action;
		if (!action) return { success: false, error: 'Missing action' };

		if (action == 'restart' || action == 'stop') {
			exec('killall -9 easytier-core easytier-web 2>/dev/null');
		}

		if (action == 'start' || action == 'restart') {
			exec('/etc/init.d/easytier restart >/dev/null 2>&1');
		} else if (action == 'stop') {
			exec('/etc/init.d/easytier stop >/dev/null 2>&1');
		}

		return { success: true };
	}
};

return { 'easytier': methods };
