// SPDX-License-Identifier: GPL-3.0-only

'use strict';
'require baseclass';
'require rpc';

/*
 * "reject: true" makes a failing ubus call raise instead of resolving with
 * an empty object: LuCI replaces a reply that does not match the "expect"
 * shape with a bare "{}", so without it a backend that is not registered
 * looks like a service that is merely disabled.
 */
const callStatus = rpc.declare({ object: 'dae', method: 'status', expect: { '': {} }, reject: true });
const callSecret = rpc.declare({ object: 'dae', method: 'secret', expect: { '': {} }, reject: true });
const callStart = rpc.declare({ object: 'dae', method: 'start', expect: { '': {} }, reject: true });
const callStop = rpc.declare({ object: 'dae', method: 'stop', expect: { '': {} }, reject: true });
const callRestart = rpc.declare({ object: 'dae', method: 'restart', expect: { '': {} }, reject: true });
const callSetListen = rpc.declare({ object: 'dae', method: 'set_listen', params: [ 'url' ], expect: { '': {} }, reject: true });
const callSetWrite = rpc.declare({ object: 'dae', method: 'set_write', params: [ 'value' ], expect: { '': {} }, reject: true });
const callGeoStatus = rpc.declare({ object: 'dae', method: 'geo_status', expect: { '': {} }, reject: true });
const callGeoUpdate = rpc.declare({ object: 'dae', method: 'geo_update', expect: { '': {} }, reject: true });

let pageStylesInstalled = false;

/*
 * The browser keeps a stylesheet in its cache, so a page that is opened
 * after the package was upgraded would still use the stylesheet of the
 * older version. The version on the URL makes it fetch the current one.
 * It has to be raised whenever dae.css changes; the package build stamps
 * the package version in.
 */
const STYLE_VERSION = '20261114-4';

function installStyles() {
	if (pageStylesInstalled || document.getElementById('dae-page-styles'))
		return;

	const stylesheet = document.createElement('link');
	stylesheet.id = 'dae-page-styles';
	stylesheet.rel = 'stylesheet';
	stylesheet.href = L.resource('view/dae/dae.css', '?v=' + STYLE_VERSION);
	document.head.appendChild(stylesheet);
	pageStylesInstalled = true;
}

function isIpLiteral(host) {
	const bare = String(host || '').replace(/^\[|\]$/g, '');
	if (!bare)
		return false;

	if (bare.indexOf(':') >= 0)
		return true;

	const octets = bare.split('.');
	return octets.length === 4 && octets.every(function(part) {
		return /^\d{1,3}$/.test(part) && Number(part) <= 255;
	});
}

function authorityHost(host) {
	const bare = String(host || '').replace(/^\[|\]$/g, '');
	return bare.indexOf(':') >= 0 ? '[' + bare + ']' : bare;
}

function isLoopback(host) {
	const bare = String(host || '').replace(/^\[|\]$/g, '').toLowerCase();
	if (bare === 'localhost' || bare === '::1' || bare === '0:0:0:0:0:0:0:1')
		return true;

	const octets = bare.split('.');
	if (octets.length !== 4 || !octets.every(function(part) { return /^\d{1,3}$/.test(part); }))
		return false;

	// 0.0.0.0 is the unspecified address, not a loopback one.
	if (octets.every(function(part) { return Number(part) === 0; }))
		return false;

	return Number(octets[0]) === 127;
}

function isWildcard(host) {
	const bare = String(host || '').replace(/^\[|\]$/g, '');
	return bare === '0.0.0.0' || bare === '::' || bare === '';
}

// The host part of a "host:port" listener address.
function listenHost(listen) {
	const value = String(listen || '');
	const cut = value.lastIndexOf(':');
	return cut < 0 ? '' : value.slice(0, cut);
}

/*
 * The address the panel is reached at.
 *
 * dae serves the panel from its API listener, so the page has to name the
 * same host the daemon answers on:
 *
 *   - a wildcard bind answers on every address, so the address the browser
 *     already uses for the router is the right one;
 *   - a bind to one address answers there only, so that address is the right
 *     one;
 *   - a loopback bind answers on the router itself, which a browser on
 *     another machine cannot reach.
 *
 * The API checks the Host header: with a wildcard bind it accepts an IP
 * literal or "localhost" only, so a router that was reached by name cannot use
 * the browser's own host. The backend reports a list of candidates then, and
 * the first one that belongs to the network the browser is already talking to
 * is the one to take.
 */
function panelAddress(status) {
	if (!status || typeof status !== 'object')
		return '';

	const port = Number(status.port);
	if (!Number.isInteger(port) || port < 1 || port > 65535)
		return '';

	const host = status.panel_host || '';
	if (host)
		return 'http://' + authorityHost(host) + ':' + port + '/ui/';

	const browserHost = (window.location && window.location.hostname) || '';
	const bound = listenHost(status.listen);
	let fallback;
	if (isWildcard(bound)) {
		fallback = browserHost;
		if (!isIpLiteral(fallback) && fallback !== 'localhost')
			fallback = pickReachableAddress(status, browserHost);
	}
	else {
		fallback = bound;
	}
	return fallback ? 'http://' + authorityHost(fallback) + ':' + port + '/ui/' : '';
}

function panelUrl(status) {
	if (!status || !status.running || !status.panel_available)
		return null;

	const address = panelAddress(status);
	if (!address)
		return null;

	const browserHost = (window.location && window.location.hostname) || '';
	const host = listenHost(address.replace(/^http:\/\//, ''));
	// A loopback address only reaches a browser on the router itself.
	if (isLoopback(host) && !isLoopback(browserHost))
		return null;

	return address;
}

/*
 * Why the panel cannot be opened, or null when it can. The wording tells the
 * operator what to do, not only what is wrong.
 */
function panelReason(status) {
	if (!status || typeof status !== 'object')
		return null;
	if (!status.running) {
		return status.enabled
			? _('The dae service is stopped. Press Start to run it.')
			: _('The dae service is not enabled yet. Press Start to enable and start it.');
	}
	if (!status.panel_available)
		return _('The panel is not installed. Install the doona package.');
	if (!panelUrl(status)) {
		if (isLoopback(listenHost(status.listen)))
			return _('The API listens on the router itself, so the panel is not reachable from another machine.');
		return _('The panel is not reachable from this browser.');
	}
	return null;
}

// The first reported address that is close enough to the browser to be worth
// trying, or the first reported address when none is.
//
// "Close enough" means the same /24: a router answers on several networks, and
// the one the browser sits in is the one it can always reach.
function pickReachableAddress(status, browserHost) {
	const candidates = Array.isArray(status.lan_addresses)
		? status.lan_addresses.filter(isIpLiteral)
		: [];
	if (!candidates.length && status.lan_address)
		candidates.push(status.lan_address);

	if (!candidates.length)
		return '';

	const prefixOf = function(host) {
		const bare = String(host || '').replace(/^\[|\]$/g, '');
		const parts = bare.split('.');
		return parts.length === 4 ? parts.slice(0, 3).join('.') : null;
	};

	const browserPrefix = isIpLiteral(browserHost) ? prefixOf(browserHost) : null;
	if (browserPrefix) {
		const sameNetwork = candidates.find(function(address) {
			return prefixOf(address) === browserPrefix;
		});
		if (sameNetwork)
			return sameNetwork;
	}

	return candidates[0];
}

function statusIssue(token) {
	const messages = {
		started: _('The dae service started.'),
		stopped: _('The dae service stopped.'),
		restarted: _('The dae service restarted.'),
		writes_enabled: _('The panel may now change the configuration.'),
		writes_disabled: _('The panel can only read the configuration now.'),
		start_failed: _('The dae service did not start. Check the system log.'),
		stop_failed: _('The dae service did not stop. Check the system log.'),
		restart_failed: _('The dae service did not restart. Check the system log.'),
		settings_write_failed: _('The settings could not be written. Check the system log.'),
		invalid_operation: _('The operation is not known.'),
		listen_invalid: _('The listener is invalid. Use a numeric address and a port, such as 0.0.0.0:9527.'),
		listen_in_use: _('That port is already in use. Choose another one.'),
		listen_unchanged: _('The listener did not change.'),
		listen_saved: _('The listener was saved and is in effect.'),
		listen_saved_stopped: _('The listener was saved. It takes effect when the service starts.'),
		listen_restart_failed: _('The new listener did not start; the previous address was restored.'),
		listen_rollback_failed: _('The new listener did not start and the previous address could not be restored. Check the system log.'),
		geo_started: _('The update was started.'),
		geo_busy: _('Another update is already running.'),
		geo_unavailable: _('The update script is missing. Reinstall the dae package.'),
		updated: _('The geo data was updated and dae was restarted.'),
		up_to_date: _('The geo data is already up to date.'),
		updated_stopped: _('The geo data was updated. It takes effect the next time dae starts.'),
		download_failed: _('The download or verification failed. The installed files were left untouched.'),
		interrupted: _('The previous update was interrupted.'),
		restart_failed_rollback: _('dae did not come back up after the update; the previous files were restored.'),
		rollback_failed: _('dae is not running and the previous files could not be restored. Check the system log.')
	};

	return messages[token] || token || _('The dae service reported an issue.');
}

function resultMessage(result, fallback) {
	return result && statusIssue(result.message) || fallback;
}

function errorMessage(error, fallback) {
	return error && statusIssue(error.message) || fallback;
}

function ensureOk(result) {
	if (!result || result.ok !== true)
		throw new Error(result && result.message ? result.message : _('The backend did not confirm the operation.'));

	return result;
}

return baseclass.extend({
	status: callStatus,
	secret: callSecret,
	start: callStart,
	stop: callStop,
	restart: callRestart,
	setListen: callSetListen,
	setWrite: callSetWrite,
	writeEnabled: function(status) {
		return !!(status && status.write === true);
	},
	geoStatus: callGeoStatus,
	geoUpdate: callGeoUpdate,
	panelAddress: panelAddress,
	panelUrl: panelUrl,
	panelReason: panelReason,
	statusIssue: statusIssue,
	resultMessage: resultMessage,
	errorMessage: errorMessage,
	ensureOk: ensureOk,
	installStyles: installStyles
});
