/* SPDX-License-Identifier: Apache-2.0 */
(function() {
	'use strict';

	function init() {
		var menu = document.getElementById('topmenu');
		if (!menu)
			return;

		var nav = menu.parentElement;
		var mobile = window.matchMedia('(max-width: 599px)');
		var desktop = window.matchMedia('(min-width: 900px)');
		var scheduled = false;
		var restoringFocus = false;

		function groups() {
			return menu.querySelectorAll(':scope > li.dropdown');
		}

		function decorateLinks() {
			var icons = { dashboard: 'layout-grid', status: 'activity-heartbeat', system: 'router', services: 'terminal-2', network: 'network', vpn: 'shield-lock', logout: 'logout' };
			var sprite = document.body.getAttribute('data-rmm-icons') || '/luci-static/rmm/icons.svg';
			menu.querySelectorAll(':scope > li > a').forEach(function(link) {
				if (link.querySelector('.rmm-nav-icon')) return;
				var destination = link.getAttribute('href') === '#' ? link.parentElement.querySelector('.dropdown-menu a[href]') : link;
				var section = '';
				try { section = new URL(destination && destination.getAttribute('href') || '', location.href).pathname.match(/\/admin\/([^/]+)/)?.[1] || ''; } catch (_) {}
				var label = link.textContent.trim();
				var text = document.createElement('span');
				text.className = 'rmm-nav-label';
				while (link.firstChild) text.appendChild(link.firstChild);
				var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
				svg.classList.add('rmm-nav-icon');
				svg.setAttribute('viewBox', '0 0 24 24');
				svg.setAttribute('aria-hidden', 'true');
				svg.setAttribute('focusable', 'false');
				var use = document.createElementNS('http://www.w3.org/2000/svg', 'use');
				use.setAttribute('href', sprite + '#icon-' + (icons[section] || 'layout-grid'));
				svg.appendChild(use);
				link.append(svg, text);
				link.setAttribute('aria-label', label);
				link.setAttribute('title', label);
				link.classList.add('rmm-nav-icon-link');
			});
		}

		function positionFlyout(group) {
			if (!desktop.matches || !group.classList.contains('rmm-open')) return;
			var trigger = group.querySelector(':scope > a.menu');
			var submenu = group.querySelector(':scope > .dropdown-menu');
			if (!trigger || !submenu) return;
			var available = Math.max(0, window.innerHeight - 24);
			var height = Math.min(submenu.scrollHeight, available);
			var top = Math.max(12, Math.min(trigger.getBoundingClientRect().top, window.innerHeight - height - 12));
			submenu.style.setProperty('--rmm-flyout-top', top + 'px');
		}

		function updateNavHeight() {
			if (mobile.matches)
				document.documentElement.style.setProperty('--rmm-mobile-nav-height', Math.ceil(nav.getBoundingClientRect().height) + 'px');
			else
				document.documentElement.style.removeProperty('--rmm-mobile-nav-height');
		}

		function closeGroups(restoreFocus) {
			var open = menu.querySelector(':scope > li.rmm-open');
			groups().forEach(function(group) {
				group.classList.remove('rmm-open');
				var trigger = group.querySelector(':scope > a.menu');
				if (trigger)
					trigger.setAttribute('aria-expanded', 'false');
			});
			if (restoreFocus && open) {
				restoringFocus = true;
				open.querySelector(':scope > a.menu')?.focus();
				restoringFocus = false;
			}
		}

		function update() {
			scheduled = false;
			decorateLinks();
			menu.classList.toggle('rmm-nav-many', menu.children.length > 5);
			var current = location.pathname.replace(/\/+$/, '');
			// The dispatcher resolves firstchild/alias entry URLs without redirecting.
			var route = document.body.getAttribute('data-rmm-route');
			if (route) {
				try {
					var resolved = new URL(route, location.href);
					if (resolved.origin === location.origin)
						current = resolved.pathname.replace(/\/+$/, '');
				}
				catch (_) { /* Keep the visible URL when the route is malformed. */ }
			}
			var best = null;
			var bestLength = -1;

			menu.querySelectorAll('.rmm-current').forEach(function(link) {
				link.classList.remove('rmm-current');
				link.removeAttribute('aria-current');
			});
			menu.querySelectorAll('.rmm-active').forEach(function(group) {
				group.classList.remove('rmm-active');
			});

			menu.querySelectorAll('a[href]').forEach(function(link) {
				if (link.getAttribute('href') === '#')
					return;
				var url;
				try { url = new URL(link.href, location.href); }
				catch (_) { return; }
				if (url.origin !== location.origin)
					return;
				var path = url.pathname.replace(/\/+$/, '');
				if ((current === path || current.startsWith(path + '/')) && path.length > bestLength) {
					best = link;
					bestLength = path.length;
				}
			});

			if (best) {
				best.classList.add('rmm-current');
				best.setAttribute('aria-current', 'page');
				best.closest('li.dropdown')?.classList.add('rmm-active');
			}

			groups().forEach(function(group, index) {
				var trigger = group.querySelector(':scope > a.menu');
				var submenu = group.querySelector(':scope > .dropdown-menu');
				if (!trigger || !submenu)
					return;
				if (!submenu.id)
					submenu.id = 'rmm-submenu-' + index;
				trigger.setAttribute('aria-controls', submenu.id);
				trigger.setAttribute('aria-expanded', group.classList.contains('rmm-open') ? 'true' : 'false');
				positionFlyout(group);
			});
			updateNavHeight();
		}

		function scheduleUpdate() {
			if (!scheduled) {
				scheduled = true;
				Promise.resolve().then(update);
			}
		}

		menu.addEventListener('click', function(event) {
			var trigger = event.target.closest('li.dropdown > a.menu');
			if (!trigger || !menu.contains(trigger))
				return;
			event.preventDefault();
			var group = trigger.parentElement;
			var wasOpen = group.classList.contains('rmm-open');
			closeGroups(false);
			group.classList.toggle('rmm-open', !wasOpen);
			trigger.setAttribute('aria-expanded', wasOpen ? 'false' : 'true');
			positionFlyout(group);
		});
		menu.addEventListener('keydown', function(event) {
			var primary=Array.from(menu.querySelectorAll(':scope > li > a'));
			var index=primary.indexOf(event.target);
			if(index>=0 && ['ArrowLeft','ArrowRight','Home','End'].includes(event.key)){
				event.preventDefault();var next=event.key==='Home'?0:event.key==='End'?primary.length-1:(index+(event.key==='ArrowLeft'?-1:1)+primary.length)%primary.length;primary[next].focus();return;
			}
			if(index>=0 && event.key==='ArrowDown' && event.target.matches('a.menu')){
				event.preventDefault();if(!event.target.parentElement.classList.contains('rmm-open'))event.target.click();event.target.parentElement.querySelector('.dropdown-menu a')?.focus();return;
			}
			if ((event.key === ' ' || event.key === 'Enter') && event.target.matches('li.dropdown > a.menu')) {
				event.preventDefault();
				event.target.click();
			}
		});

		// Tablet and desktop submenus open when their trigger receives keyboard focus.
		menu.addEventListener('focusin', function(event) {
			if (mobile.matches || restoringFocus)
				return;
			if (event.target.matches('a.menu') && !event.target.matches(':focus-visible'))
				return;
			var group = event.target.closest('li.dropdown');
			if (!group || !menu.contains(group))
				return;
			closeGroups(false);
			group.classList.add('rmm-open');
			group.querySelector(':scope > a.menu')?.setAttribute('aria-expanded', 'true');
			positionFlyout(group);
		});
		menu.addEventListener('focusout', function(event) {
			if (mobile.matches)
				return;
			var group = event.target.closest('li.dropdown');
			if (group && (!event.relatedTarget || !group.contains(event.relatedTarget)))
				closeGroups(false);
		});
		document.addEventListener('click', function(event) {
			if (!menu.contains(event.target))
				closeGroups(false);
		});
		document.addEventListener('keydown', function(event) {
			if (event.key === 'Escape' && menu.querySelector('.rmm-open')) {
				event.preventDefault();
				closeGroups(true);
			}
		});
		window.addEventListener('resize', function() {
			closeGroups(false);
			scheduleUpdate();
		});
		window.addEventListener('scroll', function() { groups().forEach(positionFlyout); }, { capture: true, passive: true });
		if (window.ResizeObserver)
			new ResizeObserver(updateNavHeight).observe(nav);
		new MutationObserver(scheduleUpdate).observe(menu, { childList: true, subtree: true });
		update();
		document.body.classList.add('rmm-nav-enhanced');
	}

	if (document.readyState === 'loading')
		document.addEventListener('DOMContentLoaded', init, { once: true });
	else
		init();
})();
