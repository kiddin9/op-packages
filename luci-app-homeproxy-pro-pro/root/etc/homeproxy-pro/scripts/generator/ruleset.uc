/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 *     generator/ruleset.uc: user-defined rule_set entries + the sing-box
 *                           1.14 http_clients normalisation.
 *
 * Two distinct pieces share this module because they both iterate over
 * `config.route.rule_set` after every other module has had a chance to
 * append:
 *
 *   build_user_rulesets(rule_set_array, dm, ctx)
 *     The custom-mode `dm.routing.rulesets` loop, which builds the
 *     user-defined rule_set entries (cfg-<name>-rule tag) and pre-1.14
 *     download_detour. The legacy field is stripped later, in the same
 *     module, by build_http_clients(); leaving it here would make
 *     sing-box 1.14 reject the config.
 *
 *   build_http_clients(rule_set_array, dm, ctx)
 *     sing-box 1.14 dropped download_detour from local/inline rule-sets
 *     and moved the remote rule-set fetch into top-level http_clients.
 *     This walks every entry, strips download_detour (sing-box 1.14
 *     rejects it on local/inline), and emits a http_clients array whose
 *     `detour` is dropped for pure-TUN setups (direct outbound with no
 *     self_mark; sing-box rejects that detour).
 */

'use strict';

import { isEmpty, validateHomeProxyPath } from '../homeproxy.uc';

import { get_outbound, isDirectOutboundTag } from './common.uc';

/* --- user-defined rule_set entries (custom mode only) ----------------- */

/* Append user-defined rule_set entries to `rule_set_array`. Each cfg
 * produces one entry; `extra_tags` adds additional rule_set tags that
 * share the same fetch source (sing-box 1.14 multi-tag). */
export function build_user_rulesets(rule_set_array, dm, ctx) {
	for (let cfg in dm.routing.rulesets) {
		if (!cfg.enabled)
			continue;

		const extra_tags = cfg.extra_tags || [];
		let rs_tag = 'cfg-' + cfg.name + '-rule';
		if (length(extra_tags) && cfg.type !== 'inline') {
			rs_tag = [rs_tag];
			for (let t in extra_tags)
				push(rs_tag, 'cfg-' + t + '-rule');
			/* sing-box 1.14: multi-tag requires a {tag} placeholder in the fetch source
			   (remote: url and initial_path, local: path).  A missing
			   placeholder makes sing-box try to literal-substitute the
			   first tag name and reject the whole config; the reload then
			   keeps the previous one and the user only sees "my change did
			   not take".  die() early so the saved UCI is rejected at
			   apply time, the same way get_resolver/get_ruleset already
			   fail loud on a missing/disabled reference. */
			const fetch_ref = (cfg.type === 'remote') ? (cfg.url || '') : (cfg.path || '');
			if (!match(fetch_ref, /\{tag\}/))
				die(sprintf("homeproxy: rule-set '%s' uses extra tags but its %s source lacks a {tag} placeholder; add {tag} to the source or drop the extra tags.", cfg.name, cfg.type));
			if (cfg.type === 'remote' && !isEmpty(cfg.initial_path) && !match(cfg.initial_path, /\{tag\}/))
				die(sprintf("homeproxy: rule-set '%s' uses extra tags but its initial_path lacks a {tag} placeholder.", cfg.name));
		}

		/* Local rule-set path is read by sing-box as root. The whitelist
		 * is enforced here because the LuCI form's datatype='file' is
		 * only UX - UCI can be set from anywhere on the LAN, and an
		 * arbitrary /etc/passwd would leak the file to anyone who
		 * could write UCI.  die() early (same as get_resolver on a
		 * missing/disabled dns_server): silently dropping path left
		 * sing-box checking whatever the field evaluated to, and the
		 * user only saw the reload keep the previous config. */
		if (cfg.type === 'local' && cfg.path && !validateHomeProxyPath(cfg.path))
			die(sprintf("homeproxy: rule-set '%s' path '%s' is outside the homeproxy whitelist; choose a path under /etc/homeproxy/.", cfg.name, cfg.path));

		const ruleset = {
			type: cfg.type,
			tag: rs_tag,
			format: cfg.format,
			path: cfg.path,
			url: cfg.url,
			update_interval: cfg.update_interval
		};
		/* download_detour is a pre-1.14 option that only makes sense for
		   remote rule-sets; emitting it for local/inline ones makes sing-box
		 * 1.14 reject the whole config. It is translated into http_clients
		   right below. */
		if (cfg.type === 'remote')
			ruleset.download_detour = get_outbound(cfg.outbound, dm) || get_outbound(ctx.default_outbound, dm);
		if (cfg.type === 'remote' && !isEmpty(cfg.initial_path))
			/* initial_path is read off the local disk as root; same
			 * whitelist as the local ruleset path. */
			ruleset.initial_path = validateHomeProxyPath(cfg.initial_path) ? cfg.initial_path : null;
		push(rule_set_array, ruleset);
	}
};

/* --- http_clients normalisation (every routing mode) ------------------ */

/* Strip the legacy download_detour from every entry (sing-box 1.14
 * rejects it on local/inline), and for remote rule-sets translate it
 * into the http_client tag pointing at the corresponding http_clients
 * entry. Returns the http_clients array (caller attaches it to
 * config.http_clients) and mutates the rule_set entries in place. */
export function build_http_clients(rule_set_array, dm, ctx) {
	const http_clients = [];
	const http_seen = {};
	for (let rs in (rule_set_array || [])) {
		/* Strip the legacy field from every entry first, including the
		   local/inline ones: sing-box 1.14 rejects it everywhere except on
		   remote rule-sets, where it is replaced by http_client below. */
		let detour = rs.download_detour;
		delete rs.download_detour;

		if (rs.type !== 'remote')
			continue;

		if (isEmpty(detour))
			detour = (ctx.routing_mode === 'custom') ? (get_outbound(ctx.default_outbound, dm) || 'direct-out') : 'direct-out';

		const tag = 'hp-' + detour;
		rs.http_client = tag;
		if (!http_seen[detour]) {
			http_seen[detour] = true;
			/* sing-box 1.14 rejects detouring to an empty direct outbound
			   (pure TUN mode has no self_mark on direct-out). Omitting detour
			   uses the same system direct dialer, so behavior is unchanged. */
			const client = { tag: tag };
			if (!(isEmpty(ctx.self_mark) && isDirectOutboundTag(detour, dm)))
				client.detour = detour;
			push(http_clients, client);
		}
	}
	return http_clients;
};