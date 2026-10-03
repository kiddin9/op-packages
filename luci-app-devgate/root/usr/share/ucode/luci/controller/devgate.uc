'use strict';

function get_request_env(http, name) {
	let value = '';

	if (http)
		value = http.getenv(name) || '';

	if (!value)
		value = getenv(name) || '';

	return value;
}

function append_addr(list, value) {
	if (value)
		push(list, value);
}

function remote_addr(env) {
	let http = env && env.http;
	let addr = '';
	let values = [];
	let forwarded_for = get_request_env(http, 'HTTP_X_FORWARDED_FOR');

	if (forwarded_for) {
		append_addr(values, forwarded_for);
		append_addr(values, get_request_env(http, 'HTTP_X_REAL_IP'));
		append_addr(values, get_request_env(http, 'HTTP_CF_CONNECTING_IP'));
		append_addr(values, get_request_env(http, 'HTTP_TRUE_CLIENT_IP'));
		append_addr(values, get_request_env(http, 'HTTP_FORWARDED'));
	} else {
		append_addr(values, get_request_env(http, 'REMOTE_ADDR'));
	}

	for (let value in values)
		addr += value + '\n';

	print(addr);
}

return {
	remote_addr
};
