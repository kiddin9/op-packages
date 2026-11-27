'use strict';
'require baseclass';

var DEFAULT_HOST = '0.0.0.0';
var DEFAULT_PORT = '9527';
var DEFAULT_SECRET = 'daeuniverse114514';

var DASHBOARD_PROFILES = {
	zashboard: {
		name: 'Zashboard',
		label: function() { return _('Zashboard'); },
		apiName: 'Native API',
		defaultPort: DEFAULT_PORT,
		defaultDir: '/etc/daeuniverse/zashboard',
		buildUrl: function(info, targetHost, port, secret, protocol, forceFresh) {
			var hostPart = (targetHost.indexOf(':') !== -1 && targetHost.charAt(0) !== '[') ? '[' + targetHost + ']' : targetHost;
			var query = 'hostname=' + encodeURIComponent(targetHost) +
				'&port=' + encodeURIComponent(port) +
				'&protocol=' + encodeURIComponent(protocol) +
				'&type=dae';
			if (secret) {
				query += '&secret=' + encodeURIComponent(secret);
			}
			var uiQuery = query;
			if (forceFresh) {
				uiQuery += '&_t=' + Date.now();
			}
			return protocol + '://' + hostPart + ':' + port + '/ui/?' + uiQuery + '#/setup?' + query;
		},
		githubRelease: 'https://github.com/Zephyruso/zashboard/releases/latest/download/dist-no-fonts.zip',
		ghfastMirror: 'https://ghfast.top/https://github.com/Zephyruso/zashboard/releases/latest/download/dist-no-fonts.zip',
		ghproxyMirror: 'https://ghproxy.net/https://github.com/Zephyruso/zashboard/releases/latest/download/dist-no-fonts.zip',
		pkgName: 'dist-no-fonts.zip'
	},
	doona: {
		name: 'Doona',
		label: function() { return _('Doona'); },
		apiName: 'Native API',
		defaultPort: DEFAULT_PORT,
		defaultDir: '/etc/daeuniverse/doona',
		buildUrl: function(info, targetHost, port, secret, protocol, forceFresh) {
			var hostPart = (targetHost.indexOf(':') !== -1 && targetHost.charAt(0) !== '[') ? '[' + targetHost + ']' : targetHost;
			var url = protocol + '://' + hostPart + ':' + port + '/ui/';
			if (forceFresh) {
				url += '?_t=' + Date.now();
			}
			return url;
		},
		githubRelease: 'https://github.com/Zakkaus/doona',
		ghfastMirror: 'https://ghfast.top/https://github.com/Zakkaus/doona',
		ghproxyMirror: 'https://ghproxy.net/https://github.com/Zakkaus/doona',
		pkgName: 'doona-*.tar.gz'
	},
	doona_lite: {
		name: 'Doona Lite',
		label: function() { return _('Doona Lite'); },
		apiName: 'Native API',
		defaultPort: DEFAULT_PORT,
		defaultDir: '/etc/daeuniverse/doona-lite',
		buildUrl: function(info, targetHost, port, secret, protocol, forceFresh) {
			var hostPart = (targetHost.indexOf(':') !== -1 && targetHost.charAt(0) !== '[') ? '[' + targetHost + ']' : targetHost;
			var url = protocol + '://' + hostPart + ':' + port + '/ui/';
			if (forceFresh) {
				url += '?_t=' + Date.now();
			}
			return url;
		},
		githubRelease: 'https://github.com/Zakkaus/doona',
		ghfastMirror: 'https://ghfast.top/https://github.com/Zakkaus/doona',
		ghproxyMirror: 'https://ghproxy.net/https://github.com/Zakkaus/doona',
		pkgName: 'doona-lite-*.tar.gz'
	}
};

function exampleConfig(profile, core) {
	if (core === 'dae') {
		return "api {\n    enabled: true\n    listen: '" + DEFAULT_HOST + ":" + profile.defaultPort +
			"'\n    secret: '" + DEFAULT_SECRET +
			"'\n    ui: '" + profile.defaultDir +
			"'\n    config_write: true\n}";
	}
	return "experimental {\n    native_api {\n        enabled: true\n        listen: '" + DEFAULT_HOST + ":" + profile.defaultPort +
		"'\n        secret: '" + DEFAULT_SECRET +
		"'\n        ui: '" + profile.defaultDir +
		"'\n        config_write: true\n    }\n}";
}

function getProfile(type) {
	if (type === 'doona-lite')
		type = 'doona_lite';
	return DASHBOARD_PROFILES[type] || DASHBOARD_PROFILES.zashboard;
}

function getTargetHost(configHost) {
	if (!configHost || configHost === '0.0.0.0' || configHost === '::' || configHost === '[::]') {
		return window.location.hostname;
	}
	return configHost;
}

function buildUrl(type, info, forceFresh) {
	var profile = getProfile(type);
	var targetHost = getTargetHost(info.host);
	var port = info.port || profile.defaultPort;
	var secret = info.secret || '';
	var protocol = 'http';
	return profile.buildUrl(info, targetHost, port, secret, protocol, forceFresh);
}

return baseclass.extend({
	profiles: DASHBOARD_PROFILES,
	defaults: { host: DEFAULT_HOST, port: DEFAULT_PORT, secret: DEFAULT_SECRET },
	exampleConfig: exampleConfig,
	getProfile: getProfile,
	getTargetHost: getTargetHost,
	buildUrl: buildUrl
});
