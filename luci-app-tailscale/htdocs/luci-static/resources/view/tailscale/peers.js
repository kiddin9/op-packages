/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Copyright (C) 2026
 */

'use strict';
'require dom';
'require fs';
'require poll';
'require view';

var PROBE_MAX_ATTEMPTS = 5;
var PROBE_RETRY_DELAY_MS = 350;
var PEER_PAGE_SIZE_DEFAULT = 25;
var PEER_PAGE_SIZE_OPTIONS = [25, 50, 100, 0];

function formatLastSeen(value) {
	if (!value)
		return '-';

	value = String(value);
	if (value.indexOf('0001-01-01') === 0)
		return '-';

	var date = new Date(value);
	if (isNaN(date.getTime()))
		return value;

	return date.toLocaleString();
}

function parseStatus(stdout) {
	var losslessJson = String(stdout || '{}').replace(/("UserID"\s*:\s*)(\d+)/g, '$1"$2"');
	var parsed = JSON.parse(losslessJson);
	var peerEntries = parsed && parsed.Peer ? parsed.Peer : {};
	var userEntries = parsed && parsed.User ? parsed.User : {};
	var peers = [];

	function appendPeer(peerId, peer, isSelf) {
		peer = peer || {};
		var ip = Array.isArray(peer.TailscaleIPs) ? (peer.TailscaleIPs[0] || '') : '';
		var dnsName = String(peer.DNSName || '').replace(/\.$/, '');
		var shortDnsName = dnsName ? dnsName.split('.')[0] : '';
		var hostName = String(peer.HostName || '');
		var displayName = (shortDnsName && hostName && shortDnsName !== hostName)
			? shortDnsName + ' (' + hostName + ')'
			: (shortDnsName || hostName || dnsName || ip || peerId);
		var routes = Array.isArray(peer.PrimaryRoutes) ? peer.PrimaryRoutes.filter(Boolean) : [];
		var userKey = peer.UserID != null ? String(peer.UserID) : '';
		var user = userKey ? (userEntries[userKey] || {}) : {};
		var userDisplayName = String(user.DisplayName || '').trim();
		var userLoginName = String(user.LoginName || '').trim();

		peers.push({
			id: peerId,
			name: displayName,
			ip: ip,
			userKey: userKey || 'unknown',
			userName: userDisplayName || userLoginName || '',
			userLoginName: userLoginName,
			online: !!peer.Online,
			lastSeen: formatLastSeen(peer.LastSeen),
			exitNode: !!peer.ExitNodeOption,
			routes: routes,
			hasSubnetRoutes: routes.length > 0,
			probeTarget: ip || hostName || dnsName || shortDnsName,
			isSelf: !!isSelf
		});
	}

	if (parsed && parsed.Self) {
		var self = parsed.Self;
		var selfId = self.ID || self.PublicKey || self.HostName || 'self';

		appendPeer(selfId, self, true);
	}

	Object.keys(peerEntries).forEach(function(peerId) {
		appendPeer(peerId, peerEntries[peerId], false);
	});

	peers.sort(function(a, b) {
		return String(a.name || '').localeCompare(String(b.name || ''));
	});

	return peers;
}

function buildPeerGroups(peers) {
	var groupMap = Object.create(null);
	var groups = [];

	peers.forEach(function(peer) {
		var userKey = peer.userKey || 'unknown';
		var group = groupMap[userKey];

		if (!group) {
			group = groupMap[userKey] = {
				key: userKey,
				name: peer.userName || _('Unknown user'),
				loginName: peer.userLoginName || '',
				peers: []
			};
			groups.push(group);
		}

		group.peers.push(peer);
	});

	groups.sort(function(a, b) {
		return String(a.name || '').localeCompare(String(b.name || ''));
	});

	groups.forEach(function(group) {
		group.peers.sort(function(a, b) {
			return String(a.name || '').localeCompare(String(b.name || ''));
		});
	});

	return groups;
}

function cloneGroupWithPeers(group, peers) {
	return {
		key: group.key,
		name: group.name,
		loginName: group.loginName,
		peers: peers
	};
}

function countPagePeers(groups) {
	return groups.reduce(function(count, group) {
		return count + group.peers.length;
	}, 0);
}

function paginatePeerGroups(groups, pageSize, requestedPageIndex) {
	var total = countPagePeers(groups);
	var pages = [];
	var currentGroups = [];
	var currentCount = 0;

	if (!total || pageSize === 0) {
		pages = total ? [{ groups: groups, count: total }] : [];
	} else {
		var pushCurrent = function() {
			if (!currentGroups.length)
				return;

			pages.push({
				groups: currentGroups,
				count: currentCount
			});
			currentGroups = [];
			currentCount = 0;
		};

		groups.forEach(function(group) {
			var peers = group.peers || [];

			/* split oversized groups into dedicated pages; do not mix their tail with other users */
			if (peers.length > pageSize) {
				pushCurrent();

				for (var i = 0; i < peers.length; i += pageSize) {
					var chunk = peers.slice(i, i + pageSize);
					pages.push({
						groups: [cloneGroupWithPeers(group, chunk)],
						count: chunk.length
					});
				}
				return;
			}

			if (currentCount > 0 && currentCount + peers.length > pageSize)
				pushCurrent();

			currentGroups.push(group);
			currentCount += peers.length;
		});

		pushCurrent();
	}

	var pageCount = Math.max(pages.length, 1);
	var pageIndex = Math.min(Math.max(Number(requestedPageIndex) || 0, 0), pageCount - 1);
	var start = 0;

	for (var j = 0; j < pageIndex; j++)
		start += pages[j].count;

	return {
		groups: pages[pageIndex] ? pages[pageIndex].groups : [],
		pageIndex: pageIndex,
		pageCount: pageCount,
		pageSize: pageSize,
		total: total,
		start: total ? start + 1 : 0,
		end: total ? start + (pages[pageIndex] ? pages[pageIndex].count : 0) : 0
	};
}

function parseProbeResult(stdout, errorMessage) {
	var fallback = {
		ok: false,
		path: 'failed',
		summary: errorMessage || _('Probe failed'),
		raw: ''
	};

	if (!stdout)
		return fallback;

	try {
		var parsed = JSON.parse(String(stdout));
		return parsed && typeof parsed === 'object' ? parsed : fallback;
	} catch (e) {
		fallback.summary = errorMessage || String(e.message || e);
		return fallback;
	}
}

function stripProbeSummary(path, summary) {
	summary = String(summary || '').trim();

	if (!summary)
		return '';

	if (path === 'direct')
		return summary.replace(/^direct\b[\s:-]*/i, '');

	if (path === 'derp')
		return summary.replace(/^DERP\b[\s:-]*/i, '');

	return summary;
}

function renderProbeResult(result) {
	if (!result)
		return E('span', { style: 'color:#94a3b8' }, _('Not probed'));

	var path = result.path || 'unknown';
	var label = path === 'direct' ? _('Direct')
		: (path === 'derp' ? _('DERP')
			: (path === 'failed' ? _('Failed') : _('Unknown')));
	var color = path === 'direct' ? '#166534'
		: (path === 'derp' ? '#a16207'
			: (path === 'failed' ? '#b91c1c' : '#475569'));
	var summary = stripProbeSummary(path, result.summary);

	return E('span', { style: 'color:%s'.format(color) }, [
		E('strong', {}, label),
		summary ? ' - ' + summary : ''
	]);
}

function appendProbeSummary(result, suffix) {
	var next = {
		ok: result && result.ok,
		path: result && result.path,
		latency_ms: result && result.latency_ms,
		relay: result && result.relay,
		raw: result && result.raw,
		summary: result && result.summary ? String(result.summary) : ''
	};

	next.summary = next.summary
		? next.summary + ' - ' + suffix
		: suffix;

	return next;
}

function sleep(ms) {
	return new Promise(function(resolve) {
		window.setTimeout(resolve, ms);
	});
}

function renderBadge(text) {
	return E('span', {
		style: 'display:inline-block;margin:0 4px 4px 0;padding:1px 6px;border-radius:3px;background:#eef2f7;color:#334155;font-size:12px;line-height:1.4'
	}, text);
}

function renderStatusLabel(online) {
	return E('span', {
		style: 'font-weight:600;color:%s'.format(online ? '#166534' : '#64748b')
	}, online ? _('Online') : _('Offline'));
}

function renderRoleBadges(peer) {
	var badges = [];

	if (peer.exitNode)
		badges.push(renderBadge(_('Exit node')));

	if (peer.hasSubnetRoutes)
		badges.push(renderBadge(_('Advertising subnets')));

	return badges.length ? badges : '-';
}

function getScrollState() {
	if (typeof document === 'undefined' || typeof window === 'undefined')
		return null;

	var scrollElement = document.querySelector('.main-right') || document.scrollingElement || document.documentElement;

	return {
		scrollElement: scrollElement,
		scrollLeft: scrollElement ? scrollElement.scrollLeft || 0 : window.scrollX || 0,
		scrollTop: scrollElement ? scrollElement.scrollTop || 0 : window.scrollY || 0,
		windowScrollX: window.scrollX || 0,
		windowScrollY: window.scrollY || 0
	};
}

function restoreScrollState(state) {
	if (!state || typeof window === 'undefined')
		return;

	var restore = function() {
		var scrollElement = state.scrollElement;

		if (scrollElement) {
			scrollElement.scrollLeft = state.scrollLeft;
			scrollElement.scrollTop = state.scrollTop;
		} else if (window.scrollTo) {
			window.scrollTo(state.windowScrollX, state.windowScrollY);
		}
	};

	restore();

	if (window.requestAnimationFrame)
		window.requestAnimationFrame(restore);
	else
		setTimeout(restore, 0);
}

async function loadPeerState() {
	try {
		var res = await fs.exec('/usr/sbin/tailscale', ['status', '--json']);
		var code = Number(res && res.code);

		if (Number.isFinite(code) && code !== 0) {
			var statusError = String((res && (res.stderr || res.stdout || res.message)) || _('Unable to load Tailscale peer status')).trim();

			return {
				ok: false,
				peers: [],
				error: statusError || _('Unable to load Tailscale peer status')
			};
		}

		return {
			ok: true,
			peers: parseStatus(res.stdout),
			error: ''
		};
	} catch (e) {
		return {
			ok: false,
			peers: [],
			error: String((e && (e.message || e.stderr || e.stdout)) || _('Unable to load Tailscale peer status'))
		};
	}
}

return view.extend({
	load: loadPeerState,

	render: function(data) {
		var state = {
			peers: (data && data.peers) || [],
			error: (data && data.error) || '',
			probeResults: Object.create(null),
			probing: Object.create(null)
		};
		var filterMode = 'all';
		var pageIndex = 0;
		var pageSize = PEER_PAGE_SIZE_DEFAULT;
		var tbody = E('tbody');
		var statusBox = E('div');
		var paginationBox = E('div');
		var filterSelect = E('select', {
			id: 'filterMode',
			change: function(ev) {
				filterMode = ev.target.value;
				pageIndex = 0;
				renderRows();
			}
		}, [
			E('option', { value: 'all' }, _('All')),
			E('option', { value: 'online' }, _('Online')),
			E('option', { value: 'subnets' }, _('Advertising subnets'))
		]);
		var pageSizeSelect = E('select', {
			id: 'pageSize',
			change: function(ev) {
				pageSize = Number(ev.target.value);
				pageIndex = 0;
				renderRows();
			}
		}, PEER_PAGE_SIZE_OPTIONS.map(function(size) {
			return E('option', {
				value: String(size),
				selected: size === pageSize ? 'selected' : null
			}, size ? String(size) : _('All peers'));
		}));

		function filterPeers(peers) {
			if (filterMode === 'online')
				return peers.filter(function(peer) { return peer.online; });

			if (filterMode === 'subnets')
				return peers.filter(function(peer) { return peer.hasSubnetRoutes; });

			return peers;
		}

		function renderPagination(page) {
			if (!page.total) {
				dom.content(paginationBox, '');
				return;
			}

			dom.content(paginationBox, E('div', {
				class: 'peer-pagination-bar',
				style: 'display:flex;align-items:center;justify-content:space-between;gap:12px;margin:10px 0 0 0;flex-wrap:wrap'
			}, [
				E('div', {
					class: 'peer-pagination-summary',
					style: 'display:flex;align-items:center;gap:10px;color:#64748b;flex:1 1 auto;min-width:220px;flex-wrap:wrap'
				}, [
					E('span', {}, _('Showing %d-%d of %d peers').format(page.start, page.end, page.total)),
					E('span', {}, _('Page %d / %d').format(page.pageIndex + 1, page.pageCount))
				]),
				E('div', {
					class: 'peer-pagination-controls',
					style: 'display:flex;align-items:center;justify-content:flex-end;gap:10px;margin-left:auto;flex-wrap:wrap'
				}, [
					E('label', { for: 'pageSize' }, _('Items per page')),
					pageSizeSelect,
					E('button', {
						type: 'button',
						class: 'btn cbi-button',
						disabled: page.pageIndex <= 0 ? 'disabled' : null,
						click: function(ev) {
							if (ev) {
								ev.preventDefault();
								ev.stopPropagation();
							}
							pageIndex = Math.max(pageIndex - 1, 0);
							renderRows(true);
						}
					}, _('Previous')),
					E('button', {
						type: 'button',
						class: 'btn cbi-button',
						disabled: page.pageIndex >= page.pageCount - 1 ? 'disabled' : null,
						click: function(ev) {
							if (ev) {
								ev.preventDefault();
								ev.stopPropagation();
							}
							pageIndex = Math.min(pageIndex + 1, page.pageCount - 1);
							renderRows(true);
						}
					}, _('Next'))
				])
			]));
		}

		function renderRows(keepScroll) {
			var filtered = filterPeers(state.peers);
			var page = paginatePeerGroups(buildPeerGroups(filtered), pageSize, pageIndex);
			var rows;
			var scrollState = keepScroll ? getScrollState() : null;

			pageIndex = page.pageIndex;
			renderPagination(page);

			if (state.error) {
				dom.content(statusBox, E('div', {
					style: 'margin-bottom:10px;padding:8px 10px;border-left:3px solid #d97706;background:#fff7ed;color:#9a3412'
				}, state.error));
			} else {
				dom.content(statusBox, '');
			}

			if (!filtered.length) {
				rows = [
					E('tr', { class: 'tr' },
						E('td', {
							class: 'td left',
							colspan: '7'
						}, state.peers.length ? _('No peers match the selected filter.') : _('No peers found'))
					)
				];
			} else {
				rows = [];
				page.groups.forEach(function(group) {
					rows.push(E('tr', { class: 'tr peer-group-header' },
						E('td', {
							class: 'td left',
							colspan: '7',
							style: 'background:#f1f5f9;border-left:4px solid #64748b;font-weight:600;padding-top:10px;padding-bottom:10px'
						}, E('div', {
							style: 'display:flex;align-items:baseline;gap:10px;flex-wrap:wrap'
						}, [
							E('span', {
								class: 'peer-group-title',
								style: 'font-size:16px;font-weight:700;color:#1e293b'
							}, group.name),
							group.loginName && group.loginName !== group.name
								? E('span', { style: 'font-weight:400;color:#64748b;font-size:13px' }, group.loginName)
								: '',
							E('span', { style: 'font-weight:400;color:#64748b;font-size:13px' }, String(group.peers.length))
						]))
					));

					group.peers.forEach(function(peer) {
						var probeCell;

						if (peer.isSelf) {
							probeCell = E('span', { style: 'font-weight:600;color:#475569' }, _('Current device'));
						} else {
							var result = state.probeResults[peer.id];
							var probing = !!state.probing[peer.id];
							var button = E('button', {
								type: 'button',
								class: 'btn cbi-button cbi-button-action',
								disabled: probing || !peer.online ? 'disabled' : null,
								click: function(ev) {
									if (ev) {
										ev.preventDefault();
										ev.stopPropagation();
									}

									return probePeer(peer);
								}
							}, probing ? _('Probing...') : _('Probe'));
							var resultNode = !peer.online
								? E('span', { style: 'color:#94a3b8' }, _('Offline peers cannot be probed'))
								: (result ? renderProbeResult(result) : (probing
									? E('span', { style: 'color:#64748b' }, _('Probing...'))
									: renderProbeResult(result)));

							probeCell = E('div', {
								style: 'display:flex;align-items:center;gap:8px;flex-wrap:wrap'
							}, [
								button,
								resultNode
							]);
						}

						rows.push(E('tr', {
							class: 'tr',
							style: peer.online ? '' : 'opacity:0.62'
						}, [
							E('td', { class: 'td left' }, peer.name),
							E('td', { class: 'td left' }, peer.ip || '-'),
							E('td', { class: 'td left' }, renderStatusLabel(peer.online)),
							E('td', { class: 'td left' }, peer.lastSeen || '-'),
							E('td', { class: 'td left' }, renderRoleBadges(peer)),
							E('td', { class: 'td left' }, peer.routes.length ? peer.routes.join(', ') : '-'),
							E('td', { class: 'td left' }, probeCell)
						]));
					});
				});
			}

			dom.content(tbody, rows);

			restoreScrollState(scrollState);
		}

		async function refreshPeers() {
			var next = await loadPeerState();
			if (next.ok) {
				state.peers = next.peers;
				state.error = '';
			} else {
				state.peers = [];
				state.error = next.error;
			}
			renderRows(true);
		}

		async function probeOnce(target) {
			var res = await fs.exec('/usr/sbin/tailscale_peer_probe', [target]);

			return parseProbeResult(
				res && res.stdout,
				res && (res.stderr || res.message || '')
			);
		}

		async function probePeer(peer) {
			var target = peer.probeTarget;
			var attempt;

			if (peer.isSelf || !peer.online)
				return;

			if (!target) {
				state.probeResults[peer.id] = {
					ok: false,
					path: 'failed',
					summary: _('No probe target available'),
					raw: ''
				};
				renderRows(true);
				return;
			}

			state.probing[peer.id] = true;
			renderRows(true);

			try {
				for (attempt = 1; attempt <= PROBE_MAX_ATTEMPTS; attempt++) {
					var result = await probeOnce(target);

					if (result.path === 'derp' && attempt < PROBE_MAX_ATTEMPTS) {
						state.probeResults[peer.id] = appendProbeSummary(
							result,
							_('Continuing probe %d/%d').format(attempt, PROBE_MAX_ATTEMPTS)
						);
						renderRows(true);
						await sleep(PROBE_RETRY_DELAY_MS);
						continue;
					}

					if (result.path === 'derp') {
						state.probeResults[peer.id] = appendProbeSummary(
							result,
							_('%d probes; direct connection not established').format(PROBE_MAX_ATTEMPTS)
						);
					} else {
						state.probeResults[peer.id] = result;
					}

					renderRows(true);
					break;
				}
			} catch (e) {
				state.probeResults[peer.id] = parseProbeResult('', String((e && (e.message || e.stderr || e.stdout)) || _('Probe failed')));
			} finally {
				state.probing[peer.id] = false;
				renderRows(true);
			}
		}

		poll.add(async function() {
			await refreshPeers();
		});

		renderRows();

		return E('div', { class: 'cbi-map' }, [
			E('h2', { class: 'content' }, _('Tailscale Peers')),
			E('div', { class: 'cbi-map-descr' }, _('View all peers and manually probe whether traffic is direct or relayed through DERP.')),
			statusBox,
			E('div', {
				style: 'display:flex;align-items:center;gap:8px;margin-bottom:10px;flex-wrap:wrap'
			}, [
				E('label', { for: 'filterMode' }, _('Filter')),
				filterSelect
			]),
			E('table', {
				class: 'table',
				style: 'table-layout:fixed;width:100%'
			}, [
				E('thead', {}, E('tr', { class: 'tr table-titles' }, [
					E('th', { class: 'th left' }, _('Name')),
					E('th', { class: 'th left' }, _('Tailnet IP')),
					E('th', { class: 'th left' }, _('Status')),
					E('th', { class: 'th left' }, _('Last Seen')),
					E('th', { class: 'th left' }, _('Role')),
					E('th', { class: 'th left' }, _('Advertised Subnets')),
					E('th', { class: 'th left' }, _('Probe'))
				])),
				tbody
			]),
			paginationBox
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
