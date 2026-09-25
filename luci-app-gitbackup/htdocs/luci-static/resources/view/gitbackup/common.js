'use strict';
'require rpc';
'require ui';

// Remote URL parsing mirrors remoteurl.sh: the Settings form reacts to it
// live, so it cannot be an rpc round trip. Plain ES5 for the buildbot's jsmin.c.
//
// Every E() child is passed as an ARRAY: LuCI's dom.append() turns array
// items into text nodes but assigns a bare string to innerHTML, and diff
// bodies, commit subjects and error reasons come off the backup remote.
// tests/dom_text_children.test.mjs enforces this in every view.

var callStatus = rpc.declare({
	object: 'luci.gitbackup',
	method: 'status'
});

var callHistory = rpc.declare({
	object: 'luci.gitbackup',
	method: 'history',
	params: [ 'limit' ]
});

var callTest = rpc.declare({
	object: 'luci.gitbackup',
	method: 'test'
});

// Same three forms as gb_parse_url: https, ssh:// and scp-like.
function gbParseRemote(url) {
	var m;

	url = url || '';

	m = url.match(/^https:\/\/([^/:]+)(?::\d+)?\/([^/]+)\/([^/]+?)(?:\.git)?\/?$/);
	if (!m)
		m = url.match(/^ssh:\/\/(?:[^@/]+@)?([^/:]+)(?::\d+)?\/([^/]+)\/([^/]+?)(?:\.git)?\/?$/);
	if (!m)
		m = url.match(/^(?:[^@/:]+@)?([^/:]+):([^/]+)\/([^/]+?)(?:\.git)?\/?$/);

	return m ? { host: m[1], owner: m[2], repo: m[3] } : null;
}

function gbProvider(url, option) {
	var parsed;

	if (option && option !== 'auto')
		return option;

	parsed = gbParseRemote(url);
	switch (parsed ? parsed.host : '') {
	case 'github.com':
		return 'github';
	case 'gitlab.com':
		return 'gitlab';
	case 'bitbucket.org':
		return 'bitbucket';
	case 'codeberg.org':
		return 'gitea';
	default:
		return 'generic';
	}
}

function gbWebBase(parsed, provider) {
	switch (provider) {
	case 'github':
		return 'https://github.com/' + parsed.owner + '/' + parsed.repo;
	case 'bitbucket':
		return 'https://bitbucket.org/' + parsed.owner + '/' + parsed.repo;
	case 'gitlab':
	case 'gitea':
		return 'https://' + parsed.host + '/' + parsed.owner + '/' + parsed.repo;
	default:
		return null;
	}
}

var GB_DEPLOY_KEY_PATH = {
	github: '/settings/keys/new',
	gitlab: '/-/settings/repository',
	gitea: '/settings/keys',
	bitbucket: '/admin/access-keys/'
};

var GB_COMMIT_PATH = {
	github: '/commit/',
	gitlab: '/-/commit/',
	gitea: '/commit/',
	bitbucket: '/commits/'
};

function gbDeployKeyLink(url, option) {
	var parsed = gbParseRemote(url);
	var provider = gbProvider(url, option);
	var base;

	if (!parsed)
		return { kind: 'unparsed' };

	base = gbWebBase(parsed, provider);
	return base ?
		{ kind: 'link', url: base + GB_DEPLOY_KEY_PATH[provider] } :
		{ kind: 'generic', host: parsed.host };
}

function gbCommitUrl(url, option, sha) {
	var parsed = gbParseRemote(url);
	var provider = gbProvider(url, option);
	var base = (parsed && sha) ? gbWebBase(parsed, provider) : null;

	return base ? base + GB_COMMIT_PATH[provider] + sha : null;
}

var GB_CSS = [
	'.gitbackup-view { container-type: inline-size; }',
	'.gitbackup-view [hidden] { display: none; }',
	'.gitbackup-caption, .gitbackup-card-hint, .gitbackup-hint { font-size: .9em; color: var(--text-color-medium, #666); }',
	'.gitbackup-hint-ok { color: var(--success-color-high, #2e7d32); }',
	'.gitbackup-hint-warn { color: var(--warn-color-high, #b45f06); }',
	'.gitbackup-hint-error { color: var(--error-color-high, #c62828); }',
	'.gitbackup-actions { display: flex; flex-wrap: wrap; gap: .5em; margin: .75em 0; align-items: center; }',
	'.gitbackup-log { max-height: 320px; overflow: auto; background: var(--background-color-low, #f5f5f5); color: var(--text-color-high, #333); border: 1px solid var(--background-color-medium, #ddd); border-radius: 4px; padding: .6em .8em; font-family: monospace; font-size: .85em; white-space: pre-wrap; }',
	'.gitbackup-leak-list { margin: .3em 0; padding-left: 1.2em; color: var(--text-color-high, #333); }',
	'.gitbackup-diff { max-height: 420px; overflow: auto; background: var(--background-color-low, #f5f5f5); border: 1px solid var(--background-color-medium, #ddd); border-radius: 4px; padding: .6em .8em; font-family: monospace; font-size: .85em; white-space: pre-wrap; }',
	'.gitbackup-diffline-add { display: block; color: var(--success-color-high, #2e7d32); }',
	'.gitbackup-diffline-del { display: block; color: var(--error-color-high, #c62828); }',
	'.gitbackup-diffline-change { display: block; color: var(--warn-color-high, #b45f06); }',
	'.gitbackup-diffline-hunk { display: block; color: var(--text-color-medium, #666); }',
	'.gitbackup-diffline-meta { display: block; font-weight: bold; color: var(--text-color-medium, #666); }',
	'.gitbackup-diffline-ctx { display: block; color: var(--text-color-high, #333); }'
];

function gbUnifiedLineClass(line) {
	if (line.indexOf('+++') === 0 || line.indexOf('---') === 0)
		return 'gitbackup-diffline-meta';
	if (line.charAt(0) === '+')
		return 'gitbackup-diffline-add';
	if (line.charAt(0) === '-')
		return 'gitbackup-diffline-del';
	if (line.indexOf('@@') === 0)
		return 'gitbackup-diffline-hunk';
	if (line.indexOf('diff --git') === 0 || line.indexOf('index ') === 0)
		return 'gitbackup-diffline-meta';
	return 'gitbackup-diffline-ctx';
}

function gbManifestLineClass(line) {
	if (line.indexOf('+ ') === 0)
		return 'gitbackup-diffline-add';
	if (line.indexOf('- ') === 0)
		return 'gitbackup-diffline-del';
	if (line.indexOf('~ ') === 0)
		return 'gitbackup-diffline-change';
	return 'gitbackup-diffline-ctx';
}

function gbBuildPre(text, classify) {
	if (!text)
		return E('p', { 'class': 'gitbackup-card-hint' }, [ _('No differences.') ]);

	return E('pre', { 'class': 'gitbackup-diff' }, text.split('\n').map(function(line) {
		return E('span', { 'class': classify(line) }, [ line + '\n' ]);
	}));
}

return L.Class.extend({
	callStatus: callStatus,
	callHistory: callHistory,
	callTest: callTest,

	css: GB_CSS,

	provider: gbProvider,

	deployKeyLink: gbDeployKeyLink,
	commitUrl: gbCommitUrl,

	commitTime: function(subject) {
		var m = (subject || '').match(/^(\d{4}-\d{2}-\d{2} \d{2}:\d{2})/);
		return m ? m[1] : null;
	},

	leakList: function() {
		return E('ul', { 'class': 'gitbackup-leak-list' }, [
			E('li', {}, [ '/etc/shadow' ]),
			E('li', {}, [ _('dropbear private host keys') ]),
			E('li', {}, [ 'authorized_keys' ]),
			E('li', {}, [ _('WPA pre-shared keys (Wi-Fi passwords)') ]),
			E('li', {}, [ _('WireGuard private keys') ]),
			E('li', {}, [ _('PPPoE credentials') ]),
			E('li', {}, [ 'uhttpd.key' ])
		]);
	},

	// ' ' text nodes between buttons match LuCI's own modal spacing.
	modalButtons: function(dismissLabel, actions) {
		var children = [ E('button', { 'class': 'cbi-button', 'click': ui.hideModal }, [ dismissLabel || _('Close') ]) ];

		(actions || []).forEach(function(a) { children.push(' ', a); });
		return E('div', { 'class': 'right' }, children);
	},

	unified: function(text) {
		return gbBuildPre(text, gbUnifiedLineClass);
	},

	manifest: function(text) {
		return gbBuildPre(text, gbManifestLineClass);
	}
});
