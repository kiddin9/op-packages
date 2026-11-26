/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * HomeProxy Clash API controller 地址 helper。
 */

'use strict';

import { cursor } from 'uci';

function is_empty(value) {
	return !value || value === 'nil' || (type(value) in ['array', 'object'] && length(value) === 0);
}

export function first_value(value) {
	return (type(value) === 'array') ? value[0] : value;
};

export function strip_cidr(value) {
	return replace(trim(first_value(value) || ''), /\/.*$/, '');
};

export function is_ipv4_address(value) {
	return !!match(value || '', /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/);
};

export function is_portable_bind_host(value) {
	value = lc(trim(value || ''));

	return value === 'localhost' ||
		value === '0.0.0.0' ||
		value === '::' ||
		value === '[::]' ||
		value === '::1' ||
		value === '[::1]' ||
		!!match(value, /^127\./);
};

export function append_ipv4_address(addresses, value) {
	value = strip_cidr(value);

	if (is_ipv4_address(value) && index(addresses, value) === -1)
		push(addresses, value);
};

export function local_ipv4_addresses(command_output) {
	const netuci = cursor();
	let addresses = [];

	netuci.load('network');

	let lan_ipaddr = netuci.get('network', 'lan', 'ipaddr');
	if (type(lan_ipaddr) === 'array') {
		for (let addr in lan_ipaddr)
			append_ipv4_address(addresses, addr);
	} else {
		append_ipv4_address(addresses, lan_ipaddr);
	}

	const ip_addresses = (type(command_output) === 'function')
		? (command_output('/sbin/ip -4 -o addr show scope global') || '')
		: '';
	for (let line in split(ip_addresses, /\n/)) {
		let matched = match(line, /[ \t]inet[ \t]+([0-9.]+)(\/[0-9]+)?[ \t]/);
		if (matched)
			append_ipv4_address(addresses, matched[1]);
	}

	return addresses;
};

export function parse_controller(value, default_port) {
	value = trim(replace(first_value(value) || '', /^https?:\/\//, ''));
	value = replace(value, /\/.*$/, '');

	let matched = match(value, /^\[([^\]]+)\](:([0-9]+))?$/);
	if (matched)
		return { host: matched[1], port: int(matched[3] || default_port) };

	matched = match(value, /^([^:]+):([0-9]+)$/);
	if (matched)
		return { host: matched[1], port: int(matched[2]) };

	return { host: value, port: int(default_port) };
};

export function format_controller(host, port) {
	return sprintf((index(host, ':') >= 0) ? '[%s]:%d' : '%s:%d', host, port);
};

export function normalize_local_controller_option(uci, config, section, local_addresses, fallback_host, option, default_port, set_when_empty) {
	let value = uci.get(config, section, option);

	if (is_empty(value)) {
		if (!set_when_empty)
			return null;

		let next = format_controller(fallback_host, default_port);
		uci.set(config, section, option, next);
		return next;
	}

	let controller = parse_controller(value, default_port),
	    host = controller.host;

	if (is_empty(host))
		host = fallback_host;
	else if (is_portable_bind_host(host))
		return null;
	else if (!is_ipv4_address(host) || index(local_addresses, host) !== -1)
		return null;

	let next = format_controller(fallback_host, controller.port || default_port);
	uci.set(config, section, option, next);
	return next;
};
