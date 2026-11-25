// Render a Carbon theme template the way LuCI's runtime does (template mode)
// with stubbed LuCI globals. Usage: ucode render-template.uc <file.ut> <lang> [login]
const path = ARGV[0], lang = ARGV[1] ?? 'en', login = ARGV[2] == 'login';
const scope = {
	ubus: { call: (obj, method, args) => {
		if (obj == 'uci' && method == 'get' && args.config == 'carbon' && args.section == 'traffic' && args.option == 'source')
			return { value: ARGV[3] };
		if (obj == 'uci' && method == 'get' && args.config == 'carbon' && args.section == 'dashboard')
			return ARGV[4] ? { values: { hero: '1', sections: 'tiles monitor details', monitor: ARGV[4], tiles: 'wifi temp', details: 'clients' } } : null;
		if (obj == 'uci' && method == 'get' && args.config == 'carbon' && args.section == 'simple_menu')
			return ARGV[5] ? { values: { common: ARGV[5], system: 'system/package-manager system/reboot' } } : null;
		return { hostname: 'OpenWrt<b>', model: 'Test Router', rootfs_type: 'squashfs' };
	} },
	http: { prepare_content: (type) => null },
	dispatcher: {
		lang: lang,
		build_url: (...parts) => '/cgi-bin/luci/' + join('/', parts),
		lookup: (path) => true
	},
	ctx: { request_path: [ 'admin', 'status', 'overview' ], path: [ 'admin', 'status', 'overview' ] },
	node: { title: 'Overview' }, dispatched: null, duser: login ? 'root' : null,
	blank_page: false, css: null,
	media: '/luci-static/carbon', resource: '/luci-static/resources',
	version: { distname: 'OpenWrt', distversion: '24.10', disturl: 'https://openwrt.org', luciname: 'LuCI', luciversion: 'test' },
	_: (s) => s,
	striptags: (s) => replace(s, /<[^>]*>/g, ''),
	entityencode: (s) => replace(s, /[<>&"]/g, (c) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;' })[c])
};
const fn = loadfile(path, {
	raw_mode: false,
	module_search_path: [ '/source/tests/ucode-stubs/*.uc', '/usr/lib/ucode/*.so', '/usr/share/ucode/*.uc' ]
});
call(fn, null, scope);
