#!/usr/bin/ucode

'use strict';

import { readfile, writefile, popen, stat } from 'fs';
import { cursor } from 'uci';
import { connect } from 'ubus';
import {
	DEFAULT_HOST,
	DEFAULT_PORT,
	DEFAULT_SECRET,
	strip_dae_comments,
	parse_api_config,
	validate_api_for_core,
	render_api_file
} from 'daeuniverse_api';

const LOG_FILE = "/var/log/daeuniverse/daeuniverse.log";
const DL_SCRIPT = "/usr/share/daeuniverse/download_dashboard.sh";
const DL_LOG_FILE = "/tmp/daeuniverse_dashboard_download.log";
const DL_STATUS_FILE = "/tmp/daeuniverse_dashboard_download.status";

const CORE_BINS = {
	honk: "/usr/bin/honk-core",
	dae: "/usr/bin/dae"
};

const CORE_DEFAULTS = {
	honk: {
		config_file: "/etc/daeuniverse/honk/config.dae",
		api_file: "/etc/daeuniverse/honk/config.d/api.dae"
	},
	dae: {
		config_file: "/etc/daeuniverse/dae/config.dae",
		api_file: "/etc/daeuniverse/dae/api.dae"
	}
};

const DASHBOARD_DIRS = {
	zashboard: "/etc/daeuniverse/zashboard",
	doona: "/etc/daeuniverse/doona",
	doona_lite: "/etc/daeuniverse/doona-lite"
};

function is_executable(path) {
	if (!path) return false;
	let s = stat(path);
	if (!s || s.type != "file") return false;
	let safe = replace(path, "'", "'\\''");
	return system("test -x '" + safe + "'") == 0;
}

function get_installed_cores() {
	return {
		honk: is_executable(CORE_BINS.honk),
		dae: is_executable(CORE_BINS.dae)
	};
}

function get_uci_core() {
	let u = cursor();
	let core = null;
	if (u) {
		u.load("daeuniverse");
		core = u.get("daeuniverse", "config", "core");
		if (!core) {
			u.foreach("daeuniverse", "daeuniverse", function(s) {
				if (s.core) {
					core = s.core;
					return false;
				}
			});
		}
	}
	return (core == "dae" || core == "honk") ? core : "honk";
}

function get_core_config_file(core) {
	core = (core == "dae") ? "dae" : "honk";
	let u = cursor();
	let p = null;
	if (u) {
		u.load("daeuniverse");
		p = u.get("daeuniverse", "config", (core == "dae") ? "dae_config_file" : "honk_config_file");
	}
	return p || CORE_DEFAULTS[core].config_file;
}

function get_core_api_file(core) {
	return (core == "dae") ? CORE_DEFAULTS.dae.api_file : CORE_DEFAULTS.honk.api_file;
}

function get_uci_dashboard_type(u) {
	if (!u) return null;
	u.load("daeuniverse");
	let requested_type = u.get("daeuniverse", "config", "dashboard");
	if (!requested_type) {
		u.foreach("daeuniverse", "daeuniverse", function(s) {
			if (s.dashboard) {
				requested_type = s.dashboard;
				return false;
			}
		});
	}
	return requested_type;
}

function normalize_dashboard_type(type) {
	if (type == "doona-lite")
		return "doona_lite";
	return type;
}

function get_dashboard_dir(type) {
	type = normalize_dashboard_type(type);
	return DASHBOARD_DIRS[type] || DASHBOARD_DIRS.doona;
}

function is_other_default_ui(ui_path, current_type) {
	current_type = normalize_dashboard_type(current_type);
	for (let t, dir in DASHBOARD_DIRS) {
		if (t != current_type && dir == ui_path)
			return true;
	}
	return false;
}

function is_valid_dashboard_type(type) {
	if (type == "none")
		return true;

	type = normalize_dashboard_type(type);
	for (let known in keys(DASHBOARD_DIRS))
		if (known == type)
			return true;

	return false;
}

function is_safe_ui_dir(path) {
	if (!path || !match(path, /^\/etc\/daeuniverse\/[^\/]+$/))
		return false;

	let base = substr(path, 17);
	return base != "." && base != ".." && base != "honk" && base != "dae";
}

function match_core_pid(pid, core_name, bin_name) {
	if (!pid) return false;
	let comm = readfile("/proc/" + pid + "/comm");
	if (!comm || trim(comm) != bin_name)
		return false;

	let raw_cmd = readfile("/proc/" + pid + "/cmdline");
	if (!raw_cmd) return false;

	// /proc/<pid>/cmdline is NUL-delimited; split() avoids C-string truncation.
	let argv = split(raw_cmd, "\x00");
	if (core_name == "dae")
		return length(argv) > 1 && argv[1] == "run";

	// Ignore one-shot subcommands (reload, mode, proxy, delay, config, admin).
	return length(argv) == 1 || (length(argv) > 1 && substr(argv[1], 0, 1) == "-");
}

function find_pid_by_bin(core_name, bin_name) {
	let p = popen("pidof " + bin_name + " 2>/dev/null");
	let pids = p ? p.read("all") : "";
	if (p) p.close();
	if (!pids) return null;
	for (let _, token in split(trim(pids), /[ \t\r\n]+/)) {
		if (match(token, /^[0-9]+$/) && match_core_pid(token, core_name, bin_name))
			return token;
	}
	return null;
}

function get_running_core() {
	let bus = connect();
	if (bus) {
		let svc = bus.call("service", "list", { name: "daeuniverse" });
		bus.disconnect();
		let instances = svc && svc.daeuniverse && svc.daeuniverse.instances;
		if (instances) {
			for (let _, inst in instances) {
				if (inst && inst.running && inst.pid) {
					let bin = (inst.command && inst.command[0]) ? inst.command[0] : "";
					let core = (bin == CORE_BINS.dae || match(bin, /\/dae$/)) ? "dae" : "honk";
					return { pid: "" + inst.pid, core: core };
				}
			}
		}
	}

	let honk_pid = find_pid_by_bin("honk", "honk-core");
	if (honk_pid)
		return { pid: honk_pid, core: "honk" };

	let dae_pid = find_pid_by_bin("dae", "dae");
	if (dae_pid)
		return { pid: dae_pid, core: "dae" };

	return { pid: null, core: null };
}

function get_core_version(core) {
	let bin = CORE_BINS[core];
	if (!bin || !is_executable(bin)) return "";
	let p = popen(bin + " --version 2>/dev/null");
	let out = p ? p.read("all") : "";
	if (p) p.close();
	let first = trim(split(trim(out || ""), /[\r\n]+/)[0] || "");
	if (!first) return "";
	let parts = split(first, /[ \t]+/);
	let ver = parts[length(parts) - 1];
	let m = match(ver, /^[0-9]{4}\.[0-9]{2}\.[0-9]{2}~(.+)$/);
	return m ? m[1] : ver;
}

function check_dae_managed_layout(config_file) {
	let raw = readfile(config_file) || "";
	let clean = strip_dae_comments(raw);
	let has_wildcard = match(clean, /config\.d\/\*\.dae/);
	let has_api = match(clean, /api\.dae/);
	// Collapse newlines so include { ... } matches across lines in ucode regexes.
	let flat = replace(clean, /[ \t\r\n]+/g, " ");
	let stripped = replace(flat, /include *\{[^}]*\}/g, "");
	if (!has_wildcard || !has_api || trim(stripped) != "") {
		return { code: "layout_unmanaged", detail: config_file };
	}
	return null;
}

function run_dae_validate(config_file) {
	if (!is_executable(CORE_BINS.dae))
		return { ok: false, code: "dae_not_installed", message: "/usr/bin/dae is not installed" };
	let safe_cfg = replace(config_file, "'", "'\\''");
	let cmd = sprintf("DAE_LOCATION_ASSET='/usr/share/v2ray' '%s' validate -c '%s' 2>&1", CORE_BINS.dae, safe_cfg);
	let p = popen(cmd);
	let out = p ? p.read("all") : "";
	let rc = p ? p.close() : -1;
	if (rc != 0) {
		return { ok: false, code: "dae_validate_failed", message: trim(out || "dae config validation failed") };
	}
	return { ok: true };
}

function get_api_config(core) {
	if (core != "dae" && core != "honk")
		core = get_uci_core();
	let api_file = get_core_api_file(core);
	let raw = readfile(api_file) || "";
	return {
		file: api_file,
		raw: raw,
		parsed: parse_api_config(raw)
	};
}

function prepare_core_switch(target_core) {
	if (target_core != "honk" && target_core != "dae")
		return { success: false, code: "invalid_core", detail: target_core, message: "Invalid core: " + target_core };

	let installed = get_installed_cores();
	if (!installed[target_core])
		return { success: false, code: "core_not_installed", detail: CORE_BINS[target_core], message: "Selected core is not installed: " + CORE_BINS[target_core] };

	let api_cfg = get_api_config(target_core);
	let config_file = get_core_config_file(target_core);

	if (api_cfg.parsed.format) {
		let check = validate_api_for_core(target_core, api_cfg.parsed);
		if (!check.ok)
			return { success: false, code: check.code, message: check.message };
	}

	let warning = null;
	if (target_core == "dae") {
		let v = run_dae_validate(config_file);
		if (!v.ok)
			return { success: false, code: "dae_validate_failed", detail: v.message, message: "dae configuration validation failed:\n" + v.message };
		warning = check_dae_managed_layout(config_file);
	}

	return {
		success: true,
		core: target_core,
		warning: warning
	};
}

function get_dashboard_info(req) {
	let u = cursor();
	let requested_type = (req && req.args) ? req.args.type : null;
	if (!is_valid_dashboard_type(requested_type) && u) {
		requested_type = get_uci_dashboard_type(u);
	}
	if (!is_valid_dashboard_type(requested_type)) requested_type = "none";

	let configured_core = get_uci_core();
	let api_cfg = get_api_config(configured_core);
	let parsed = api_cfg.parsed;
	let proc = get_running_core();

	let res = {
		dashboard_type: requested_type,
		configured: false,
		has_ui: false,
		running: !!proc.pid,
		active_core: proc.core || configured_core,
		configured_core: configured_core,
		config_file: api_cfg.file,
		external_controller: "",
		host: "",
		port: "",
		secret: "",
		external_ui: ""
	};

	if (requested_type == "none") {
		return res;
	}

	let target_default_ui = get_dashboard_dir(requested_type);

	if (parsed && parsed.enabled && parsed.listen) {
		res.external_controller = parsed.listen;
		res.host = parsed.host;
		res.port = parsed.port || DEFAULT_PORT;
		res.secret = parsed.secret;

		res.external_ui = (parsed.ui && !is_other_default_ui(parsed.ui, requested_type)) ? parsed.ui : target_default_ui;

		let s = stat(res.external_ui + "/index.html");
		res.has_ui = (s && s.type == "file") ? true : false;

		if (!res.has_ui) {
			res.configured = true;
		} else if (parsed.ui && !is_other_default_ui(parsed.ui, requested_type)) {
			res.configured = true;
		} else {
			res.configured = false;
		}
	}

	return res;
}

function download_dashboard(req) {
	let requested_type = (req && req.args) ? req.args.type : null;
	if (!is_valid_dashboard_type(requested_type)) {
		requested_type = get_uci_dashboard_type(cursor());
	}
	if (!is_valid_dashboard_type(requested_type) || requested_type == "none") {
		requested_type = "doona";
	}
	requested_type = normalize_dashboard_type(requested_type);

	let url = (req && req.args && req.args.url) ? req.args.url : "";
	if (!match(url, /^https?:\/\//) || match(url, /[ \t\r\n'"`]/)) {
		return { success: false, code: "invalid_url", message: "Invalid URL" };
	}

	let configured_core = get_uci_core();
	let api_cfg = get_api_config(configured_core);
	let parsed = api_cfg.parsed;
	let target_dir = get_dashboard_dir(requested_type);
	if (parsed && parsed.ui && !is_other_default_ui(parsed.ui, requested_type) &&
	    is_safe_ui_dir(parsed.ui)) {
		target_dir = parsed.ui;
	}

	if (!is_safe_ui_dir(target_dir))
		return { success: false, code: "unsafe_target", message: "Refusing to deploy to an unsafe target directory" };

	if (!stat(DL_SCRIPT)) {
		return { success: false, code: "script_missing", detail: DL_SCRIPT, message: "Script not found: " + DL_SCRIPT };
	}

	let safe_script = replace(DL_SCRIPT, "'", "'\\''");
	let safe_target = replace(target_dir, "'", "'\\''");
	let safe_url = replace(url, "'", "'\\''");
	let safe_type = replace(requested_type, "'", "'\\''");

	let cmd = sprintf("/bin/sh '%s' '%s' '%s' '%s' >/dev/null 2>&1 &", safe_script, safe_target, safe_url, safe_type);
	if (system(cmd) != 0)
		return { success: false, code: "download_failed", message: "failed to dispatch the download task" };

	return { success: true, target_dir: target_dir, url: url, queued: true };
}

function update_core_api_dashboard(core, target_type, target_ui, has_target_ui) {
	let api_file = get_core_api_file(core);
	let raw = readfile(api_file);
	if (raw == null) return false;
	let parsed = parse_api_config(raw);

	if (target_type == "none" || !target_type) {
		if (parsed && parsed.format && parsed.enabled) {
			parsed.enabled = false;
			writefile(api_file, render_api_file(core, parsed, raw));
			system("chmod 600 '" + replace(api_file, "'", "'\\''") + "' 2>/dev/null || true");
			return true;
		}
		return false;
	}

	let next_cfg = parsed;
	next_cfg.enabled = true;
	next_cfg.config_write = true;
	if (!next_cfg.listen || next_cfg.listen == "")
		next_cfg.listen = DEFAULT_HOST + ":" + DEFAULT_PORT;
	if ((!next_cfg.secret || next_cfg.secret == "") && !next_cfg.password_auth)
		next_cfg.secret = DEFAULT_SECRET;

	if (has_target_ui) {
		next_cfg.ui = target_ui;
	} else if (next_cfg.ui) {
		// honk-core fails at startup if native_api.ui points to a missing directory.
		let existing_ui = stat(next_cfg.ui + "/index.html");
		if (!existing_ui || existing_ui.type != "file")
			next_cfg.ui = "";
	}

	let next_raw = render_api_file(core, next_cfg, raw);
	if (next_raw != raw) {
		writefile(api_file, next_raw);
		system("chmod 600 '" + replace(api_file, "'", "'\\''") + "' 2>/dev/null || true");
		return true;
	}
	return false;
}

function switch_dashboard_api(target_type, defer_apply) {
	target_type = normalize_dashboard_type(target_type);
	if (!is_valid_dashboard_type(target_type))
		return { success: false, code: "invalid_dashboard_type", message: "Invalid dashboard type" };

	let active_core = get_uci_core();
	let other_core = (active_core == "dae") ? "honk" : "dae";
	let active_api = get_api_config(active_core);
	let parsed = active_api.parsed;

	system("mkdir -p /etc/daeuniverse/honk/config.d /etc/daeuniverse/dae");

	if (!defer_apply) {
		let u = cursor();
		if (u) {
			u.load("daeuniverse");
			let sid = "config";
			if (!u.get("daeuniverse", sid)) {
				u.foreach("daeuniverse", "daeuniverse", function(s) { sid = s[".name"]; });
			}
			u.set("daeuniverse", sid, "dashboard", target_type || "none");
			u.commit("daeuniverse");
		}
	}

	if (target_type == "none" || !target_type) {
		let changed = update_core_api_dashboard(active_core, "none", "", false);
		if (stat(get_core_api_file(other_core)))
			update_core_api_dashboard(other_core, "none", "", false);
		if (changed && !defer_apply) {
			system("/etc/init.d/daeuniverse restart >/dev/null 2>&1 &");
			return { success: true, type: "none", queued: true };
		}
		return { success: true, type: "none" };
	}

	let target_ui = get_dashboard_dir(target_type);
	let s = stat(target_ui + "/index.html");
	let has_target_ui = (s && s.type == "file") ? true : false;

	if (!has_target_ui && parsed && parsed.enabled && parsed.listen) {
		return { success: true, type: target_type, has_ui: false, pending_download: true };
	}

	if (parsed && parsed.format == active_core && parsed.enabled &&
	    parsed.listen && parsed.config_write &&
	    (parsed.secret || parsed.password_auth) &&
	    parsed.ui == target_ui && has_target_ui) {
		if (stat(get_core_api_file(other_core)))
			update_core_api_dashboard(other_core, target_type, target_ui, has_target_ui);
		return { success: true, type: target_type };
	}

	update_core_api_dashboard(active_core, target_type, target_ui, has_target_ui);
	if (stat(get_core_api_file(other_core)))
		update_core_api_dashboard(other_core, target_type, target_ui, has_target_ui);

	if (!defer_apply) {
		system("/etc/init.d/daeuniverse restart >/dev/null 2>&1 &");
		return { success: true, type: target_type, queued: true };
	}

	return { success: true, type: target_type };
}

return {
	"luci.daeuniverse": {
		status: {
			call: function(req) {
				let proc = get_running_core();
				let running = !!proc.pid;
				let configured_core = get_uci_core();
				let installed = get_installed_cores();
				let memory = null;
				if (running) {
					let status_str = readfile("/proc/" + proc.pid + "/status");
					if (status_str) {
						let rss_m = match(status_str, /VmRSS:[ \t]+([0-9]+)[ \t]+kB/);
						if (rss_m) {
							memory = sprintf("%.1f MB", +rss_m[1] / 1024);
						}
					}
				}
				return {
					running: running,
					memory: memory,
					active_core: proc.core || configured_core,
					configured_core: configured_core,
					installed_cores: installed
				};
			}
		},

		get_cores: {
			call: function(req) {
				let proc = get_running_core();
				let installed = get_installed_cores();
				let configured = get_uci_core();
				return {
					configured_core: configured,
					active_core: proc.core || configured,
					running: !!proc.pid,
					installed_cores: installed,
					versions: {
						honk: installed.honk ? get_core_version("honk") : "",
						dae: installed.dae ? get_core_version("dae") : ""
					}
				};
			}
		},

		prepare_core_switch: {
			args: { core: "string" },
			call: function(req) {
				let c = req.args ? req.args.core : "honk";
				return prepare_core_switch(c);
			}
		},

		validate_config: {
			args: { core: "string" },
			call: function(req) {
				let c = (req.args && req.args.core) ? req.args.core : get_uci_core();
				let api_cfg = get_api_config(c);
				let check = validate_api_for_core(c, api_cfg.parsed);
				if (!check.ok)
					return { valid: false, code: check.code, message: check.message };

				if (c == "dae") {
					let config_file = get_core_config_file("dae");
					let layout_warn = check_dae_managed_layout(config_file);
					let v = run_dae_validate(config_file);
					if (!v.ok)
						return { valid: false, code: "dae_validate_failed", detail: v.message, message: v.message, warning: layout_warn };
					return { valid: true, warning: layout_warn };
				}
				return { valid: true };
			}
		},

		reload: {
			call: function(req) {
				let rc = system("/etc/init.d/daeuniverse hot_reload >/dev/null 2>&1 &");
				if (rc != 0)
					return { success: false, code: "reload_failed", message: "failed to trigger hot_reload" };

				return { success: true, queued: true };
			}
		},

		restart: {
			call: function(req) {
				let rc = system("/etc/init.d/daeuniverse restart >/dev/null 2>&1 &");
				if (rc != 0)
					return { success: false, code: "restart_failed", message: "failed to trigger restart" };

				return { success: true, queued: true };
			}
		},

		get_log: {
			call: function(req) {
				let p = popen("tail -n 1000 " + LOG_FILE + " 2>/dev/null");
				let content = p ? p.read("all") : "";
				if (p) p.close();
				return { log: content || "" };
			}
		},

		clear_log: {
			call: function(req) {
				system("mkdir -p /var/log/daeuniverse");
				writefile(LOG_FILE, "");
				return { success: true };
			}
		},

		get_dashboard_info: {
			args: { type: "string" },
			call: get_dashboard_info
		},

		download_dashboard: {
			args: { url: "string", type: "string" },
			call: download_dashboard
		},

		download_status: {
			call: function(req) {
				let status_raw = readfile(DL_STATUS_FILE) || "IDLE";
				let log = readfile(DL_LOG_FILE) || "";
				let status_m = match(status_raw, /[^ \t\r\n]+/);
				let status = status_m ? status_m[0] : "IDLE";
				return { status: status, log: log };
			}
		},

		switch_dashboard_api: {
			args: { type: "string", defer_apply: true },
			call: function(req) {
				let t = req.args ? req.args.type : "none";
				let defer_apply = !!(req.args && req.args.defer_apply);
				return switch_dashboard_api(t, defer_apply);
			}
		}
	}
};
