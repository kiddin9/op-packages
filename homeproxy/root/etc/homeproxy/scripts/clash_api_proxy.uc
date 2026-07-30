#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Clash API display proxy for HomeProxy dashboards.
 */

'use strict';

import * as socket from 'socket';
import * as uloop from 'uloop';
import { cursor } from 'uci';
import { urldecode, urlencode } from 'luci.http';
import { parse_controller } from '/etc/homeproxy/scripts/clash_api.uc';

const uci = cursor();
const uciconfig = 'homeproxy';
const ucimain = 'config';
const shadowtls_suffix = '-out-shadowtls';
const filter_timeout = 10000;
const fallback_delay_limit = 5;
const upstream_read_timeout = 5;  // 秒；单次上游读取超时

// Resource limits
const MAX_CONNECTIONS = 64;
const MAX_REQUEST_BUFFER_SIZE = 256 * 1024;  // 256KB
const MAX_RESPONSE_BUFFER_SIZE = 8 * 1024 * 1024;  // 8MB
const CLIENT_IDLE_TIMEOUT = 30000;  // 30 seconds

let next_id = 1;
let connections = {};
let target, listen, server;

uci.load(uciconfig);

function isEmpty(value) {
	return !value || value === 'nil' || (type(value) in ['array', 'object'] && length(value) === 0);
}

function toArray(value) {
	if (type(value) === 'array')
		return value;
	else if (isEmpty(value))
		return [];

	return [ value ];
}

function deriveProxyController(target) {
	target = parse_controller(target || '127.0.0.1:9090', 9090);

	if (isEmpty(target.host))
		target.host = '127.0.0.1';

	return { host: target.host, port: 9091 };
}

function sendAll(sock, data) {
	let offset = 0;

	while (offset < length(data)) {
		let sent = sock.send(substr(data, offset));

		if (sent === null || sent <= 0)
			return false;

		offset += sent;
	}

	return true;
}

function recvAvailable(sock) {
	let data = '';
	let eof = false;

	for (let i = 0; i < 32; i++) {
		let chunk = sock.recv(16384);

		if (chunk === null)
			break;

		if (length(chunk) === 0) {
			eof = true;
			break;
		}

		data += chunk;

		if (length(chunk) < 16384)
			break;
	}

	return { data, eof };
}

function contentLength(headers) {
	for (let line in headers) {
		let matched = match(lc(line), /^content-length:[ \t]*([0-9]+)/);

		if (matched)
			return int(matched[1]);
	}

	return null;
}

function headerValue(headers, name) {
	name = lc(name);

	for (let line in headers) {
		let matched = match(line, /^([^:]+):(.*)$/);

		if (matched && lc(trim(matched[1])) === name)
			return trim(matched[2]);
	}

	return null;
}

function pathSegment(value) {
	return replace(urlencode(value), /\+/g, '%20');
}

function parseHttpMessage(raw, body_to_eof) {
	let header_end = index(raw, "\r\n\r\n");

	if (header_end < 0)
		return null;

	let header_text = substr(raw, 0, header_end);
	let headers = split(header_text, "\r\n");
	let body_start = header_end + 4;
	let body_len = contentLength(headers);

	if (body_len === null)
		body_len = body_to_eof ? length(raw) - body_start : 0;

	let complete_len = body_start + body_len;

	if (length(raw) < complete_len)
		return null;

	let request_line = split(headers[0] || '', /[ \t]+/);

	return {
		raw: substr(raw, 0, complete_len),
		headers,
		body: substr(raw, body_start, body_len),
		complete_len,
		method: request_line[0] || '',
		path: request_line[1] || '/'
	};
}

function shouldFilter(method, path) {
	return method === 'GET' && (
		path === '/proxies' ||
		index(path, '/proxies?') === 0 ||
		index(path, '/proxies/') === 0 ||
		path === '/providers/proxies' ||
		index(path, '/providers/proxies?') === 0 ||
		index(path, '/providers/proxies/') === 0
	);
}

function isUpgradeRequest(request) {
	return !!headerValue(request.headers, 'Upgrade') ||
		index(lc(headerValue(request.headers, 'Connection') || ''), 'upgrade') >= 0;
}

function rebuildCloseRequest(request) {
	let headers = [];

	for (let i = 0; i < length(request.headers); i++) {
		let line = request.headers[i],
		    header = lc(line);

		if (i > 0 && match(header, /^(accept-encoding|connection):/))
			continue;

		push(headers, line);
	}

	push(headers, 'Accept-Encoding: identity');
	push(headers, 'Connection: close');

	return join("\r\n", headers) + "\r\n\r\n" + request.body;
}

function isShadowTlsTag(name) {
	return type(name) === 'string' &&
		length(name) > length(shadowtls_suffix) &&
		substr(name, length(name) - length(shadowtls_suffix)) === shadowtls_suffix;
}

function isHiddenProxyTag(name) {
	return isShadowTlsTag(name);
}

function filterProxyItem(item) {
	if (type(item) !== 'object')
		return;

	if (type(item.all) === 'array')
		item.all = filter(item.all, (name) => !isHiddenProxyTag(name));
}

function filterProxyArray(items) {
	return filter(items, (item) => {
		if (type(item) === 'string')
			return !isHiddenProxyTag(item);

		if (type(item) === 'object' && isHiddenProxyTag(item.name))
			return false;

		filterProxyItem(item);
		return true;
	});
}

function filterProxiesPayload(payload) {
	if (type(payload) !== 'object')
		return payload;

	filterProxyItem(payload);

	if (type(payload.proxies) === 'object') {
		for (let name in payload.proxies) {
			if (isHiddenProxyTag(name)) {
				delete payload.proxies[name];
				continue;
			}

			filterProxyItem(payload.proxies[name]);
		}
	}

	if (type(payload.providers) === 'object') {
		for (let name in payload.providers) {
			let provider = payload.providers[name];

			if (type(provider) !== 'object')
				continue;

			if (type(provider.proxies) === 'array')
				provider.proxies = filterProxyArray(provider.proxies);
		}
	}

	return payload;
}

function parseHex(value) {
	let result = 0;
	value = lc(trim(split(value, ';', 2)[0] || ''));

	for (let i = 0; i < length(value); i++) {
		let digit = index('0123456789abcdef', substr(value, i, 1));

		if (digit < 0)
			return null;

		result = result * 16 + digit;
	}

	return result;
}

function decodeChunkedBody(body) {
	let offset = 0;
	let decoded = '';

	while (offset < length(body)) {
		let line_end = index(substr(body, offset), "\r\n");

		if (line_end < 0)
			return null;

		let size = parseHex(substr(body, offset, line_end));
		if (size === null)
			return null;

		offset += line_end + 2;

		if (size === 0)
			return decoded;

		if (length(body) < offset + size + 2)
			return null;

		decoded += substr(body, offset, size);
		offset += size + 2;
	}

	return null;
}

function rebuildResponse(response, body) {
	let headers = [];

	for (let i = 0; i < length(response.headers); i++) {
		let line = response.headers[i];

		if (i > 0 && match(lc(line), /^(content-length|transfer-encoding):/))
			continue;

		push(headers, line);
	}

	push(headers, 'Content-Length: ' + length(body));

	return join("\r\n", headers) + "\r\n\r\n" + body;
}

function filterResponse(raw) {
	let response = parseHttpMessage(raw, true);

	if (response === null)
		return raw;

	let body = response.body;
	if (lc(headerValue(response.headers, 'transfer-encoding') || '') === 'chunked') {
		body = decodeChunkedBody(substr(raw, response.complete_len - length(response.body)));
		if (body === null)
			return raw;
	}

	let payload;

	try {
		payload = json(body);
	} catch (e) {
		return raw;
	}

	if (type(payload) !== 'object')
		return raw;

	payload = filterProxiesPayload(payload);

	return rebuildResponse(response, sprintf('%J', payload));
}

function responseBody(response) {
	if (response === null)
		return null;

	let body = response.body;

	if (lc(headerValue(response.headers, 'transfer-encoding') || '') === 'chunked') {
		body = decodeChunkedBody(response.body);
		if (body === null)
			return null;
	}

	return body;
}

function parseJsonBody(raw) {
	if (raw === null)
		return null;

	let response = parseHttpMessage(raw, true),
	    body = responseBody(response);

	if (body === null)
		return null;

	try {
		return json(body);
	} catch (e) {
		return null;
	}
}

function responseStatus(raw) {
	let response = parseHttpMessage(raw, true);

	if (response === null)
		return 0;

	let matched = match(response.headers[0] || '', /^HTTP\/[0-9.]+[ \t]+([0-9]+)/);

	return matched ? int(matched[1]) : 0;
}

function responseComplete(raw) {
	let header_end = index(raw, "\r\n\r\n");
	if (header_end < 0)
		return false;

	let headers = split(substr(raw, 0, header_end), "\r\n");
	if (lc(headerValue(headers, 'transfer-encoding') || '') === 'chunked')
		return decodeChunkedBody(substr(raw, header_end + 4)) !== null;

	if (contentLength(headers) === null)
		return false;

	return parseHttpMessage(raw) !== null;
}

function closeConnection(conn) {
	if (!conn)
		return;

	if (conn.client_handle) {
		conn.client_handle.delete();
		conn.client_handle = null;
	}

	if (conn.upstream_handle) {
		conn.upstream_handle.delete();
		conn.upstream_handle = null;
	}

	if (conn.timer) {
		conn.timer.cancel();
		conn.timer = null;
	}

	if (conn.idle_timer) {
		conn.idle_timer.cancel();
		conn.idle_timer = null;
	}

	if (conn.client) {
		conn.client.close();
		conn.client = null;
	}

	if (conn.upstream) {
		conn.upstream.close();
		conn.upstream = null;
	}

	delete connections[conn.id];
}

function isEmptyObject(value) {
	return type(value) === 'object' && length(value) === 0;
}

function buildJsonResponse(request, payload) {
	let body = sprintf('%J', payload),
	    headers = [
		'HTTP/1.1 200 OK',
		'Content-Type: application/json',
		'Connection: close'
	    ],
	    origin = headerValue(request.headers, 'Origin');

	if (!isEmpty(origin)) {
		let allowed_origins = toArray(uci.get(uciconfig, ucimain, 'clash_api_allow_origin'));

		if (index(allowed_origins, origin) >= 0) {
			push(headers, 'Access-Control-Allow-Origin: ' + origin);
			push(headers, 'Vary: Origin');
		}
	}

	push(headers, 'Content-Length: ' + length(body));

	return join("\r\n", headers) + "\r\n\r\n" + body;
}

function parseGroupDelayPath(path) {
	let parts = split(path, '?', 2),
	    matched = match(parts[0] || '', /^\/group\/(.+)\/delay$/);

	if (!matched)
		return null;

	return {
		name: urldecode(matched[1]),
		query: (length(parts) > 1) ? ('?' + parts[1]) : ''
	};
}

function upstreamHeader(request, name) {
	let value = headerValue(request.headers, name);
	return isEmpty(value) ? null : value;
}

function upstreamRequest(method, path, request, body) {
	body = body || '';

	let headers = [
		sprintf('%s %s HTTP/1.1', method, path),
		sprintf('Host: %s:%d', target.host, target.port),
		'Accept-Encoding: identity',
		'Connection: close'
	    ],
	    authorization = upstreamHeader(request, 'Authorization'),
	    origin = upstreamHeader(request, 'Origin');

	if (authorization)
		push(headers, 'Authorization: ' + authorization);

	if (origin)
		push(headers, 'Origin: ' + origin);

	if (length(body)) {
		let content_type = upstreamHeader(request, 'Content-Type');

		if (content_type)
			push(headers, 'Content-Type: ' + content_type);

		push(headers, 'Content-Length: ' + length(body));
	}

	return join("\r\n", headers) + "\r\n\r\n" + body;
}

function fetchUpstreamAsync(method, path, request, body, done) {
	let upstream = socket.connect(target.host, target.port, null, 3000);

	if (upstream === null) {
		done(null);
		return null;
	}

	let fetch = {
		upstream: upstream,
		handle: null,
		timer: null,
		raw: '',
		finished: false
	};

	function finish(raw) {
		if (fetch.finished)
			return;

		fetch.finished = true;

		if (fetch.handle) {
			fetch.handle.delete();
			fetch.handle = null;
		}

		if (fetch.timer) {
			fetch.timer.cancel();
			fetch.timer = null;
		}

		if (fetch.upstream) {
			fetch.upstream.close();
			fetch.upstream = null;
		}

		done(raw);
	}

	if (!sendAll(upstream, upstreamRequest(method, path, request, body))) {
		finish(null);
		return fetch;
	}

	fetch.timer = uloop.timer(upstream_read_timeout * 1000, () => finish(null));
	fetch.handle = uloop.handle(upstream, (events, eof, error) => {
		if (events & uloop.ULOOP_READ) {
			let received = recvAvailable(upstream);

			if (length(received.data)) {
				if (length(fetch.raw) + length(received.data) > MAX_RESPONSE_BUFFER_SIZE) {
					warn(sprintf('homeproxy clash api proxy: async fetch response exceeded %d bytes\n', MAX_RESPONSE_BUFFER_SIZE));
					finish(null);
					return;
				}

				fetch.raw += received.data;
			}

			if (responseComplete(fetch.raw) || received.eof) {
				finish(length(fetch.raw) ? fetch.raw : null);
				return;
			}
		}

		if (eof || error)
			finish(length(fetch.raw) ? fetch.raw : null);
	}, uloop.ULOOP_READ);

	return fetch;
}

function fetchVisibleProxyGroupAsync(group_name, request, done) {
	fetchUpstreamAsync('GET', '/proxies', request, null, (raw) => {
		if (raw === null) {
			done(null);
			return;
		}

		let payload = filterProxiesPayload(parseJsonBody(raw));
		if (type(payload) !== 'object' || type(payload.proxies) !== 'object') {
			done(null);
			return;
		}

		let group = payload.proxies[group_name];
		done((type(group) === 'object') ? group : null);
	});
}

function testProxyDelayAsync(proxy_name, query, request, done) {
	fetchUpstreamAsync('GET',
		'/proxies/' + pathSegment(proxy_name) + '/delay' + query,
		request,
		null,
		(raw) => {
			if (raw === null || responseStatus(raw) < 200 || responseStatus(raw) >= 300) {
				done(0);
				return;
			}

			let payload = parseJsonBody(raw);

			if (type(payload) === 'object' && type(payload.delay) === 'double') {
				done(int(payload.delay));
				return;
			}

			if (type(payload) === 'object' && type(payload.delay) === 'int') {
				done(payload.delay);
				return;
			}

			done(0);
		});
}

function fallbackGroupDelayAsync(group_info, request, progress, done) {
	fetchVisibleProxyGroupAsync(group_info.name, request, (group) => {
		if (progress)
			progress();

		if (group === null || type(group.all) !== 'array') {
			done(null);
			return;
		}

		let results = {},
		    candidates = [],
		    truncated = false;

		for (let proxy_name in group.all) {
			if (isShadowTlsTag(proxy_name))
				continue;

			if (length(candidates) >= fallback_delay_limit) {
				truncated = true;
				break;
			}

			push(candidates, proxy_name);
		}

		if (truncated)
			warn(sprintf('homeproxy clash api proxy: fallback delay for group %s limited to first %d visible proxies\n',
				group_info.name, fallback_delay_limit));

		function next(index) {
			if (index >= length(candidates)) {
				done(results);
				return;
			}

			let proxy_name = candidates[index];
			testProxyDelayAsync(proxy_name, group_info.query, request, (delay) => {
				results[proxy_name] = delay;

				if (progress)
					progress();

				next(index + 1);
			});
		}

		next(0);
	});
}

function finishGroupDelay(conn, request, group_info, raw) {
	if (!connections[conn.id])
		return;

	let payload = parseJsonBody(raw),
	    status = raw === null ? 0 : responseStatus(raw);

	if (type(payload) === 'object')
		payload = filterProxiesPayload(payload);

	if (status >= 200 && status < 300 && !isEmptyObject(payload)) {
		sendAll(conn.client, buildJsonResponse(request, payload));
		closeConnection(conn);
		return;
	}

	resetTimer(conn);
	fallbackGroupDelayAsync(group_info, request, () => resetTimer(conn), (fallback_payload) => {
		if (!connections[conn.id])
			return;

		if (fallback_payload !== null) {
			sendAll(conn.client, buildJsonResponse(request, fallback_payload));
			closeConnection(conn);
			return;
		}

		if (raw !== null)
			sendAll(conn.client, raw);

		closeConnection(conn);
	});
}

function handleGroupDelay(conn, request, group_info) {
	if (conn.client_handle) {
		conn.client_handle.delete();
		conn.client_handle = null;
	}

	conn.request_buffer = '';
	conn.timer = uloop.timer(filter_timeout, () => closeConnection(conn));
	fetchUpstreamAsync(request.method, request.path, request, request.body,
		(raw) => finishGroupDelay(conn, request, group_info, raw));
	return true;
}

function resetTimer(conn) {
	if (conn.timer)
		conn.timer.set(filter_timeout);
}

function relayRead(conn, from, to) {
	let received = recvAvailable(from);

	if (length(received.data) && !sendAll(to, received.data)) {
		closeConnection(conn);
		return;
	}

	// Reset idle timer on data activity
	if (conn.idle_timer && length(received.data) > 0) {
		conn.idle_timer.set(CLIENT_IDLE_TIMEOUT);
	}

	if (received.eof)
		closeConnection(conn);
}

function setupRelay(conn) {
	// Set idle timer for relay phase (30s idle timeout)
	conn.idle_timer = uloop.timer(CLIENT_IDLE_TIMEOUT, () => {
		warn(`Connection ${conn.id} idle timeout during relay\n`);
		closeConnection(conn);
	});

	conn.client_handle = uloop.handle(conn.client, (events, eof, error) => {
		if (events & uloop.ULOOP_READ)
			relayRead(conn, conn.client, conn.upstream);

		if (eof || error)
			closeConnection(conn);
	}, uloop.ULOOP_READ);

	conn.upstream_handle = uloop.handle(conn.upstream, (events, eof, error) => {
		if (events & uloop.ULOOP_READ)
			relayRead(conn, conn.upstream, conn.client);

		if (eof || error)
			closeConnection(conn);
	}, uloop.ULOOP_READ);
}

function finishFilteredResponse(conn) {
	sendAll(conn.client, filterResponse(conn.response_buffer));
	closeConnection(conn);
}

function setupFilteredResponse(conn) {
	conn.response_buffer = '';
	conn.timer = uloop.timer(filter_timeout, () => closeConnection(conn));

	conn.upstream_handle = uloop.handle(conn.upstream, (events, eof, error) => {
		if (events & uloop.ULOOP_READ) {
			let received = recvAvailable(conn.upstream);

			if (length(received.data)) {
				// Check response buffer size limit
				if (length(conn.response_buffer) + length(received.data) > MAX_RESPONSE_BUFFER_SIZE) {
					warn(`Connection ${conn.id} response buffer exceeded ${MAX_RESPONSE_BUFFER_SIZE} bytes\n`);
					closeConnection(conn);
					return;
				}
				conn.response_buffer += received.data;
				resetTimer(conn);
			}

			if (responseComplete(conn.response_buffer) || received.eof) {
				finishFilteredResponse(conn);
				return;
			}
		}

		if (eof || error) {
			if (length(conn.response_buffer))
				finishFilteredResponse(conn);
			else
				closeConnection(conn);
		}
	}, uloop.ULOOP_READ);
}

function startUpstream(conn, request) {
	try {
		let group_delay = parseGroupDelayPath(request.path);

		if (request.method === 'GET' && group_delay !== null)
			return handleGroupDelay(conn, request, group_delay);

		if (conn.client_handle) {
			conn.client_handle.delete();
			conn.client_handle = null;
		}

		conn.filter_read = shouldFilter(request.method, request.path);
		conn.upstream = socket.connect(target.host, target.port, null, 3000);

		if (conn.upstream === null) {
			warn(sprintf('homeproxy clash api proxy: connect to %s:%d failed: %s\n',
				target.host, target.port, socket.error()));
			closeConnection(conn);
			return;
		}

		let upstream_request = (conn.filter_read || !isUpgradeRequest(request))
			? rebuildCloseRequest(request)
			: conn.request_buffer;
		if (!sendAll(conn.upstream, upstream_request)) {
			warn('homeproxy clash api proxy: failed to send upstream request\n');
			closeConnection(conn);
			return;
		}

		conn.request_buffer = '';

		if (conn.filter_read)
			setupFilteredResponse(conn);
		else
			setupRelay(conn);
	} catch (e) {
		warn(sprintf('homeproxy clash api proxy: start upstream exception: %J\n', e));
		closeConnection(conn);
	}
}

function onClientRequest(conn, events, eof, error) {
	if (events & uloop.ULOOP_READ) {
		let received = recvAvailable(conn.client);

		if (length(received.data)) {
			// Check request buffer size limit
			if (length(conn.request_buffer) + length(received.data) > MAX_REQUEST_BUFFER_SIZE) {
				warn(`Connection ${conn.id} request buffer exceeded ${MAX_REQUEST_BUFFER_SIZE} bytes\n`);
				closeConnection(conn);
				return;
			}
			conn.request_buffer += received.data;
		}

		let request = parseHttpMessage(conn.request_buffer);
		if (request !== null) {
			// Cancel idle timer when request is complete
			if (conn.idle_timer) {
				conn.idle_timer.cancel();
				delete conn.idle_timer;
			}
			startUpstream(conn, request);
			return;
		}

		if (received.eof) {
			closeConnection(conn);
			return;
		}
	}

	if (eof || error)
		closeConnection(conn);
}

function acceptClients(server) {
	while (true) {
		// Check connection limit
		let active_connections = length(keys(connections));
		if (active_connections >= MAX_CONNECTIONS) {
			// Accept and immediately close to reject (don't leave in backlog)
			let rejected = server.accept();
			if (rejected) {
				rejected.close();
			}
			warn(`Connection limit reached: ${active_connections}/${MAX_CONNECTIONS}\n`);
			break;
		}

		let client = server.accept();

		if (client === null)
			break;

		let conn = {
			id: next_id++,
			client,
			upstream: null,
			client_handle: null,
			upstream_handle: null,
			timer: null,
			request_buffer: '',
			response_buffer: '',
			created_at: time()
		};

		connections[conn.id] = conn;

		// Set idle timeout (uloop.timer signature: timeout_ms, callback)
		conn.idle_timer = uloop.timer(CLIENT_IDLE_TIMEOUT, () => {
			warn(`Connection ${conn.id} idle timeout\n`);
			closeConnection(conn);
		});

		conn.client_handle = uloop.handle(client, (events, eof, error) => onClientRequest(conn, events, eof, error), uloop.ULOOP_READ);
	}
}

const clash_api_enabled = uci.get(uciconfig, ucimain, 'clash_api_enabled') || '0';

if (clash_api_enabled !== '1')
	exit(0);

target = parse_controller(uci.get(uciconfig, ucimain, 'clash_api_external_controller') || '127.0.0.1:9090', 9090);
listen = isEmpty(uci.get(uciconfig, ucimain, 'clash_api_proxy_external_controller'))
	? deriveProxyController((index(target.host, ':') >= 0 ? '[' + target.host + ']' : target.host) + ':' + target.port)
	: parse_controller(uci.get(uciconfig, ucimain, 'clash_api_proxy_external_controller'), 9091);

if (isEmpty(listen.host))
	listen.host = '127.0.0.1';

server = socket.listen(listen.host, listen.port, null, 128, true);

if (server === null) {
	warn(sprintf('homeproxy clash api proxy: failed to listen on %s:%d: %s\n', listen.host, listen.port, socket.error()));
	exit(1);
}

uloop.init();
uloop.handle(server, () => acceptClients(server), uloop.ULOOP_READ);

warn(sprintf('homeproxy clash api proxy: listening on %s:%d, forwarding to %s:%d\n',
	listen.host, listen.port, target.host, target.port));

uloop.run();
