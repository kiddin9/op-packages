/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * generator/server.uc: server-side orchestrator.
 *
 * This module no longer shapes
 * any protocol. It used to read the flat UCI section directly
 * (`cfg.snell_version`, `cfg.shadowsocks_encrypt_method`,
 * `cfg.hysteria_obfs_min_packet_size`, ...) and spell out every
 * per-protocol sing-box field inline, which meant the server path had
 * no domain model and adding a protocol touched the generator.
 *
 * Now:
 *
 *   UCI -> Loader.load_inbound() -> Inbound (domain) -> InboundFactory
 *          -> sing-box inbound JSON
 *
 * The protocol knowledge lives in config/model.uc (the canonical <->
 * UCI tables) and config/adapter.uc (InboundFactory's sing-box field
 * tables). What is left here is the orchestration: gate on `enabled`,
 * build the log block, and decide that "no inbound" means "server
 * disabled" (the CLI shell turns the null into exit 1).
 *
 * generate_server(dm) -> config object. Pure: no UCI, no file I/O.
 */

'use strict';

import { InboundFactory } from '../config/adapter.uc';

/* --- public entry ------------------------------------------------------ */

/* Build the sing-box server config object. Returns null when no
 * enabled inbound exists (the caller treats that as "service disabled",
 * which the runtime interprets as "do not start the server instance"). */
export function generate_server(dm) {
	const log_level = ((dm.server || {}).settings || {}).log_level || 'warn';

	const config = {
		log: {
			disabled: false,
			level: log_level,
			output: '/var/run/homeproxy-pro/sing-box-s.log',
			timestamp: true
		},
		inbounds: []
	};

	for (let inbound in ((dm.server || {}).inbounds || [])) {
		if (!inbound.enabled)
			continue;

		/* create() dies on a broken section, which is the previous
		 * behaviour too: the old code would emit a sing-box config
		 * that `sing-box check` then rejected, and the runtime's
		 * candidate/known-good path caught it. Failing here instead
		 * names the offending section in the log. */
		push(config.inbounds, InboundFactory.create(inbound));
	}

	if (length(config.inbounds) === 0)
		return null;

	config['$schema'] = 'https://sing-box.sagernet.org/schema.json';

	return config;
};
