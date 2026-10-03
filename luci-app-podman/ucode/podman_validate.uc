// Copyright 2026 Christopher Söllinger
// Licensed to the public under the Apache License 2.0.
//
// Shared parameter validators for the rpcd plugin, the LuCI streaming
// controller and the podman-api CLI helper.
//
// Convention: every exported validator returns an error message **string**
// on failure and `null` on success, so call sites can chain with || :
//
//     let err = require_param('name', v) || validate_name(v);
//     if (err) return { error: err };

'use strict';

const VALID_RESTART_POLICIES = { 'no': true, 'always': true, 'on-failure': true, 'unless-stopped': true };

const CONTAINER_BODY_KEYS = {
	cpu: true, memory: true, blockIO: true, devices: true,
	hugepageLimits: true, network: true, pids: true, rdma: true, unified: true,
	BlkIOWeightDevice: true,
	DeviceReadBPs: true, DeviceReadIOPs: true,
	DeviceWriteBPs: true, DeviceWriteIOPs: true,
	Env: true, UnsetEnv: true,
	health_cmd: true, health_interval: true, health_log_destination: true,
	health_max_log_count: true, health_max_log_size: true,
	health_on_failure: true, health_retries: true, health_start_period: true,
	health_startup_cmd: true, health_startup_interval: true,
	health_startup_retries: true, health_startup_success: true,
	health_startup_timeout: true, health_timeout: true,
	no_healthcheck: true
};

/** @param {string} id */
export function validate_id(id) {
	if (!id || type(id) !== 'string' || !match(id, /^[a-zA-Z0-9][a-zA-Z0-9_.:-]*$/))
		return 'Invalid id format';
};

/** @param {string} name */
export function validate_name(name) {
	if (!name || type(name) !== 'string' || !match(name, /^[a-zA-Z0-9_.-]+$/))
		return 'Invalid name format';
};

/** @param {string} ref */
export function validate_image_ref(ref) {
	if (!ref || type(ref) !== 'string' || !match(ref, /^[a-zA-Z0-9_.:\/@-]+$/))
		return 'Invalid image reference';
};

/** @param {string} query */
export function validate_query_params(query) {
	if (!query || type(query) !== 'string' || !match(query, /^[a-zA-Z0-9=&_.,-]+$/))
		return 'Invalid query parameters';
};

/** @param {string} policy */
export function validate_restart_policy(policy) {
	if (policy && !(policy in VALID_RESTART_POLICIES))
		return 'Invalid restart policy';
};

/** @param {string} val */
export function validate_int(val) {
	if (!val || type(val) !== 'string' || !match(val, /^[0-9]+$/))
		return 'Invalid number';
};

/**
 * @param {string} name
 * @param {any} value
 */
export function require_param(name, value) {
	if (value == null || value === ''
		|| (type(value) === 'object' && length(keys(value)) === 0))
		return `Missing required parameter: ${name}`;
};

export const BODY_KEYS = CONTAINER_BODY_KEYS;
