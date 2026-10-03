/*
 * luci-theme-shadcnui — sidebar.js
 *
 * Sidebar is always visible on desktop. On mobile (≤768px) the burger button
 * in the topbar toggles a slide-in drawer; the dark overlay closes it.
 *
 * Section toggle and active-link highlighting are handled by menu-shadcnui.js
 * because that module is responsible for rendering the menu DOM.
 */
(function () {
	'use strict';

	var app = document.getElementById('shadcn-app');
	if (!app) return;     // login page or other unrelated layout

	function applyState(state) {
		// state: 'expanded' (mobile closed / desktop default) | 'open' (mobile drawer)
		app.setAttribute('data-sidebar', state);
	}

	applyState('expanded');

	var toggle = document.getElementById('shadcn-sidebar-toggle');
	if (toggle) {
		toggle.addEventListener('click', function (e) {
			e.preventDefault();
			var current = app.getAttribute('data-sidebar') || 'expanded';
			applyState(current === 'open' ? 'expanded' : 'open');
		});
	}

	var overlay = document.getElementById('shadcn-overlay');
	if (overlay) {
		overlay.addEventListener('click', function () {
			applyState('expanded');
		});
	}

	// Close the drawer if the viewport grows past the breakpoint.
	window.addEventListener('resize', function () {
		if (window.matchMedia('(min-width: 769px)').matches &&
		    app.getAttribute('data-sidebar') === 'open') {
			applyState('expanded');
		}
	});
})();
