'use strict';

export const DEFAULT_HOST = "0.0.0.0";
export const DEFAULT_PORT = "9527";
export const DEFAULT_SECRET = "daeuniverse114514";

export function parse_host_port(addr) {
	let res = { host: "", port: "" };
	if (!addr) return res;
	let m_v6 = match(addr, /^\[([^\]]+)\]:([0-9]+)$/);
	let m_v4 = match(addr, /^([^:]+):([0-9]+)$/);
	let m_p = match(addr, /^:([0-9]+)$/);
	if (m_v6) {
		res.host = m_v6[1];
		res.port = m_v6[2];
	} else if (m_v4) {
		res.host = m_v4[1];
		res.port = m_v4[2];
	} else if (m_p) {
		res.host = "0.0.0.0";
		res.port = m_p[1];
	} else if (match(addr, /^[0-9]+$/)) {
		res.host = "0.0.0.0";
		res.port = addr;
	}
	return res;
}

export function strip_dae_comments(content) {
	if (!content) return "";
	let lines = split(content, /[\r\n]+/);
	let clean_lines = [];

	for (let idx, line in lines) {
		let in_single = false;
		let in_double = false;
		let escaped = false;
		let clean = "";
		let len = length(line);

		for (let i = 0; i < len; i++) {
			let c = substr(line, i, 1);

			if (escaped) {
				escaped = false;
				clean += c;
				continue;
			}
			if (c == "\\" && (in_single || in_double)) {
				escaped = true;
				clean += c;
				continue;
			}
			if (c == "'" && !in_double) {
				in_single = !in_single;
				clean += c;
			} else if (c == '"' && !in_single) {
				in_double = !in_double;
				clean += c;
			} else if (!in_single && !in_double && c == '#') {
				break;
			} else {
				clean += c;
			}
		}
		if (match(clean, /[^ \t\r\n]/)) {
			push(clean_lines, clean);
		}
	}
	return join("\n", clean_lines);
}

export function find_bracket_block(content, header_regex) {
	if (!content) return { start: -1, end: -1 };
	let lines = split(content, "\n");
	let start_idx = -1;
	let end_idx = -1;
	let in_block = false;
	let depth = 0;
	let in_single = false;
	let in_double = false;

	for (let idx, line in lines) {
		let trimmed = trim(line);
		if (!in_block && !match(trimmed, /^#/) && match(trimmed, header_regex)) {
			in_block = true;
			start_idx = idx;
		}

		if (in_block) {
			let len = length(line);
			let escaped = false;
			for (let i = 0; i < len; i++) {
				let c = substr(line, i, 1);
				if (escaped) {
					escaped = false;
					continue;
				}
				if (c == "\\" && (in_single || in_double)) {
					escaped = true;
					continue;
				}
				if (c == "'" && !in_double) {
					in_single = !in_single;
				} else if (c == '"' && !in_single) {
					in_double = !in_double;
				} else if (!in_single && !in_double) {
					if (c == '#') {
						break;
					} else if (c == '{') {
						depth++;
					} else if (c == '}') {
						depth--;
						if (depth <= 0) {
							end_idx = idx;
							break;
						}
					}
				}
			}
			if (end_idx != -1) break;
		}
	}
	return { start: start_idx, end: end_idx };
}

export function extract_bracket_block(content, header_regex) {
	let bounds = find_bracket_block(content, header_regex);
	if (bounds.start == -1 || bounds.end == -1) return null;
	let lines = split(content, "\n");
	let block_lines = [];
	for (let i = bounds.start; i <= bounds.end; i++) {
		push(block_lines, lines[i]);
	}
	return join("\n", block_lines);
}

export function remove_bracket_block(content, header_regex) {
	let bounds = find_bracket_block(content, header_regex);
	if (bounds.start == -1 || bounds.end == -1) return content;
	let lines = split(content, "\n");
	let new_lines = [];
	for (let i = 0; i < length(lines); i++) {
		if (i < bounds.start || i > bounds.end) {
			push(new_lines, lines[i]);
		}
	}
	return join("\n", new_lines);
}

function parse_bool(val, fallback) {
	if (!val) return fallback;
	let v = lc(trim(replace(val, /^['"]|['"]$/g, "")));
	if (v == "true" || v == "1" || v == "yes" || v == "on") return true;
	if (v == "false" || v == "0" || v == "no" || v == "off") return false;
	return fallback;
}

function unquote_scalar(val) {
	if (!val) return "";
	let s = trim(val);
	if (length(s) >= 2) {
		let first = substr(s, 0, 1);
		let last = substr(s, length(s) - 1, 1);
		if ((first == "'" && last == "'") || (first == '"' && last == '"')) {
			return substr(s, 1, length(s) - 2);
		}
	}
	return s;
}

function quote_scalar(val) {
	let s = "" + (val == null ? "" : val);
	let escaped = replace(s, "'", "\\'");
	return "'" + escaped + "'";
}

export function parse_api_config(raw_content) {
	let clean = strip_dae_comments(raw_content || "");
	let format = null;
	let block = extract_bracket_block(clean, /^native_api[ \t]*\{/);
	if (block) {
		format = "honk";
	} else {
		block = extract_bracket_block(clean, /^api[ \t]*\{/);
		if (block) format = "dae";
	}

	let res = {
		format: format,
		enabled: false,
		config_write: false,
		allow_anonymous_loopback: false,
		password_auth: false,
		listen: "",
		ui: "",
		secret: "",
		host: "",
		port: "",
		extra_lines: {}
	};

	if (!block) return res;

	let has_enabled = false;
	let lines = split(block, "\n");
	for (let i, line in lines) {
		let t = trim(line);
		if (match(t, /^((experimental|native_api|api)[ \t]*\{|\})$/))
			continue;
		let kv = match(t, /^([a-zA-Z0-9_]+)[ \t]*:[ \t]*(.*)$/);
		if (!kv) continue;
		let k = kv[1];
		let v = trim(kv[2]);
		if (k == "enabled") {
			has_enabled = true;
			res.enabled = parse_bool(v, false);
		} else if (k == "config_write") {
			res.config_write = parse_bool(v, false);
		} else if (k == "allow_anonymous_loopback") {
			res.allow_anonymous_loopback = parse_bool(v, false);
		} else if (k == "password_auth") {
			res.password_auth = parse_bool(v, false);
		} else if (k == "listen") {
			res.listen = unquote_scalar(v);
		} else if (k == "secret") {
			res.secret = unquote_scalar(v);
		} else if (k == "ui") {
			res.ui = unquote_scalar(v);
		} else {
			res.extra_lines[k] = v;
		}
	}

	if (!has_enabled) {
		res.enabled = false;
	}

	let hp = parse_host_port(res.listen);
	res.host = hp.host;
	res.port = hp.port;

	return res;
}

function is_valid_socket_addr(addr) {
	if (!addr) return false;
	let m = match(addr, /^(\[([0-9a-fA-F:]+)\]|([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})):([0-9]+)$/);
	if (!m) return false;
	let port = +m[4];
	if (port < 1 || port > 65535) return false;
	if (m[3]) {
		for (let _, o in split(m[3], ".")) {
			if (+o < 0 || +o > 255) return false;
		}
	}
	return true;
}

// dae is validated authoritatively via `dae validate -c`; honk-core lacks a
// validate subcommand, so perform lightweight native_api sanity checks here.
export function validate_api_for_core(core, cfg) {
	if (!cfg || core == "dae") return { ok: true };
	if (cfg.config_write && (!cfg.secret || cfg.secret == "") && !cfg.password_auth) {
		return { ok: false, code: "native_secret_required", message: "native_api.config_write requires secret or password_auth." };
	}
	if (cfg.enabled && !is_valid_socket_addr(cfg.listen)) {
		return { ok: false, code: "native_listen_not_numeric", message: "native_api.listen must be a numeric IP:port (for example 0.0.0.0:9527)." };
	}
	return { ok: true };
}

export function strip_api_blocks(raw_content) {
	let cleaned = raw_content || "";
	for (let iter = 0; iter < 10; iter++) {
		let before = cleaned;
		cleaned = remove_bracket_block(cleaned, /^clash_api[ \t]*\{/);
		cleaned = remove_bracket_block(cleaned, /^native_api[ \t]*\{/);
		cleaned = remove_bracket_block(cleaned, /^api[ \t]*\{/);
		cleaned = replace(cleaned, /[ \t]*experimental[ \t]*\{[ \t\r\n]*\}[ \t]*\n?/g, "");
		if (cleaned == before) break;
	}
	return trim(cleaned);
}

export function render_api_file(core, cfg, raw_existing) {
	let indent = (core == "dae") ? "    " : "        ";
	let body = [];
	push(body, indent + "enabled: " + (cfg.enabled ? "true" : "false"));
	if (cfg.listen && cfg.listen != "")
		push(body, indent + "listen: " + quote_scalar(cfg.listen));
	if (cfg.secret != null && cfg.secret != "")
		push(body, indent + "secret: " + quote_scalar(cfg.secret));
	if (cfg.allow_anonymous_loopback)
		push(body, indent + "allow_anonymous_loopback: true");
	if (cfg.password_auth && core != "dae")
		push(body, indent + "password_auth: true");
	if (cfg.ui && cfg.ui != "")
		push(body, indent + "ui: " + quote_scalar(cfg.ui));
	push(body, indent + "config_write: " + (cfg.config_write ? "true" : "false"));

	for (let k in sort(keys(cfg.extra_lines || {}))) {
		push(body, indent + k + ": " + cfg.extra_lines[k]);
	}

	let block = (core == "dae")
		? ("api {\n" + join("\n", body) + "\n}\n")
		: ("experimental {\n    native_api {\n" + join("\n", body) + "\n    }\n}\n");

	let base = strip_api_blocks(raw_existing);
	if (base == "") {
		let header = (core == "dae")
			? "# /etc/daeuniverse/dae/api.dae\n"
			: "# /etc/daeuniverse/honk/config.d/api.dae\n";
		return header + block;
	}
	return base + "\n\n" + block;
}
