/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * parse_uri() used to do its host/port
 * check inline at the end of the dispatcher, just before returning the
 * config. Per the guidance doc (section 八, Parse -> Normalize ->
 * Validate three-layer separation), the post-parse checks belong in
 * their own module so:
 *
 *   - failures are categorised (host / port / credential / tls /
 *     scheme), so the orchestrator's log line can name the failure
 *     instead of dumping the whole config;
 *   - new rules (REQUIRED_CREDENTIALS, TLS sanity) can land without
 *     touching the dispatcher or the per-scheme parsers;
 *   - tests can exercise the validator without going through any
 *     scheme-specific parser.
 *
 * Today only the original two checks (host / port) are implemented,
 * so the categorisation is mostly plumbing. Adding REQUIRED_CREDENTIALS
 * in a follow-up is now a one-place change.
 */

'use strict';

import { validation } from '../homeproxy.uc';

/* Each entry carries a stable `kind` (so callers / tests can branch on
 * it) and a `message` for the log line. Adding a new rule is:
 *
 *   { kind: 'missing_credential', field: 'uuid',
 *     message: sprintf('%s requires %s', type, field) }
 */
export function validate(config, log) {
	let errors = [];

	if (!validation('host', config.address)) {
		errors = [...errors, {
			kind: 'invalid_host',
			message: sprintf('Skipping invalid %s node: %s.',
				config.type, config.label || 'NULL')
		}];
	}

	if (!validation('port', config.port)) {
		errors = [...errors, {
			kind: 'invalid_port',
			message: sprintf('Skipping invalid %s node: %s.',
				config.type, config.label || 'NULL')
		}];
	}

	if (length(errors)) {
		/* Stay log-compatible with the old code path: one warn line
		 * per failure. The orchestrator already swallows `null`
		 * returns from parse_uri(), so it does not need to learn
		 * about the categorised shape yet. */
		for (let err in errors)
			log(err.message);
		return null;
	}

	return config;
};

/* Exposed for tests so they can assert categorisation without going
 * through the full dispatcher. Returns the (possibly empty) array of
 * error descriptors that `validate()` would log, but does not log
 * anything itself. */
export function check(config) {
	let errors = [];

	if (!validation('host', config.address))
		errors = [...errors, { kind: 'invalid_host', type: config.type, address: config.address }];

	if (!validation('port', config.port))
		errors = [...errors, { kind: 'invalid_port', type: config.type, port: config.port }];

	return errors;
};