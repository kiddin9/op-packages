'use strict';
'require baseclass';
'require fs';
'require overview-manager.shared as common';

var helper = '/usr/libexec/overview-manager';
var self = '00_overview-manager.js';

/* luci-mod-status builds the widget sections once and only replaces their
 * content on later poll cycles, and the saved layout cannot change while the
 * Overview page stays loaded. Reading the layout once per page load keeps the
 * poll cycle free of two extra helper invocations every five seconds. */
var cached = null;

function installedFiles(text) {
	return (text || '').replace(/\r/g, '').split('\n').map(function(name) {
		return name.trim();
	}).filter(function(name) {
		return /\.js$/.test(name);
	}).sort(common.compareWidgets);
}

function orderedFiles(files, configured) {
	var known = {};
	files.forEach(function(name) { known[name] = true; });
	var result = [ self ];

	(configured || []).forEach(function(name) {
		if (name !== self && known[name] && result.indexOf(name) < 0)
			result.push(name);
	});
	files.forEach(function(name) {
		if (result.indexOf(name) < 0)
			result.push(name);
	});
	return result;
}

function applyLayout(marker, files, layout, attempts) {
	var ownSection = marker.closest('.cbi-section');
	var parent = ownSection && ownSection.parentNode;
	var sections = parent ? Array.prototype.filter.call(parent.children, function(node) {
		return node.classList && node.classList.contains('cbi-section');
	}) : [];

	if (!parent || sections.length !== files.length) {
		if (attempts < 8)
			window.setTimeout(function() {
				applyLayout(marker, files, layout, attempts + 1);
			}, 25);
		return;
	}

	var byName = {};
	var mapped = sections.every(function(node) {
		var name = node.getAttribute('data-overview-widget');
		return name && files.indexOf(name) >= 0 && !byName[name] &&
			(byName[name] = node);
	});
	if (!mapped) {
		byName = {};
		files.forEach(function(name, index) {
			byName[name] = sections[index];
			sections[index].setAttribute('data-overview-widget', name);
		});
	}

	var wanted = orderedFiles(files, layout.order);
	var moved = wanted.some(function(name, index) {
		return sections[index] !== byName[name];
	});

	/* Re-appending every section on each poll is what makes the page flicker,
	 * so only touch the DOM when the effective order really changed. */
	if (moved)
		wanted.forEach(function(name) {
			if (byName[name])
				parent.appendChild(byName[name]);
		});

	var hidden = {};
	layout.hidden.forEach(function(name) { hidden[name] = true; });

	/* Toggle in place. Dropping the class first and re-adding it would reveal
	 * every hidden widget for one frame on each poll cycle. */
	files.forEach(function(name) {
		if (byName[name])
			byName[name].classList.toggle('overview-manager-hidden',
				name === self || hidden[name] === true);
	});
}

return baseclass.extend({
	/* luci-mod-status uses the title as the localStorage key for its own Hide
	 * button, so an empty one would claim the empty key and collide with any
	 * other untitled include. This section is hidden by the stylesheet below
	 * and never displays the title. It stays untranslated on purpose: a
	 * translated title would change the key whenever the language changes. */
	title: 'Overview Manager',

	load: function() {
		if (cached)
			return Promise.resolve(cached);

		return Promise.all([
			L.resolveDefault(fs.exec(helper, [ 'files' ]), { stdout: '' }),
			L.resolveDefault(fs.exec(helper, [ 'layout' ]), { stdout: '' })
		]).then(function(data) {
			/* Keep retrying on the next poll when the helper was unreachable
			 * instead of caching an empty widget list for the whole session. */
			if (data[0].stdout)
				cached = data;
			return data;
		});
	},

	render: function(data) {
		var files = installedFiles(data[0].stdout);
		var layout = common.parseLayout(data[1].stdout);
		var marker = E('span', {
			'data-overview-manager-marker': '1',
			'style': 'display:none'
		});

		window.requestAnimationFrame(function() {
			window.requestAnimationFrame(function() {
				applyLayout(marker, files, layout, 0);
			});
		});

		return E('div', {}, [
			E('style', {}, [
				'.overview-manager-hidden{display:none!important}'
			]),
			marker
		]);
	}
});
