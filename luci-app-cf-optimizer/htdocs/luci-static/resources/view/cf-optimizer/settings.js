'use strict';
'require view';
'require form';
'require uci';
'require fs';
'require ui';

return view.extend({
	handleSaveApply: function(ev, mode) {
		return this.handleSave(ev).then(function() {
			ui.showModal(_('应用配置'), [
				E('p', { 'class': 'spinning' }, _('正在下发配置并同步 hosts 域名定向，请稍候...'))
			]);
			return fs.exec_direct('/etc/init.d/cf-optimizer', ['reload']).catch(function() {}).then(function() {
				setTimeout(function() {
					ui.hideModal();
					window.location.reload();
				}, 1500);
			});
		});
	},

	render: function() {
		var m, s, o;

		m = new form.Map('cf-optimizer', _('Cloudflare 优选加速') + ' - ' + _('参数配置'),
			_('配置待优选的 Cloudflare 代理域名、测速周期及采样算法参数。'));

		s = m.section(form.NamedSection, 'settings', 'cf-optimizer', _('基础设置'));
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', _('启用服务'),
			_('开启后守护进程将按设定周期自动执行优选测速，并通过 dnsmasq 内存级重载生效。'));
		o.rmempty = false;

		o = s.option(form.DynamicList, 'domains', _('加速域名列表'),
			_('填入需要优选加速的域名，支持 Cloudflare Tunnel 穿透域名和小黄云代理域名。'));
		o.datatype = 'host';
		o.rmempty = false;

		o = s.option(form.ListValue, 'interval', _('自动优选周期'),
			_('两次自动测速优选之间的休眠间隔时间。'));
		o.value('30', _('30 分钟'));
		o.value('60', _('1 小时'));
		o.value('120', _('2 小时'));
		o.value('240', _('4 小时'));
		o.value('360', _('6 小时'));
		o.value('720', _('12 小时'));
		o.value('1440', _('24 小时'));
		o.default = '120';

		s = m.section(form.NamedSection, 'settings', 'cf-optimizer', _('高级探测参数'));
		s.anonymous = true;

		o = s.option(form.Value, 'sample_count', _('采样探测次数'),
			_('初筛后对候选节点进行连续采样的次数，用于计算平均时延与丢包率，推荐范围 3-10 次。'));
		o.datatype = 'range(2, 20)';
		o.default = '4';

		o = s.option(form.ListValue, 'hysteresis_ms', _('防震荡迟滞阈值'),
			_('新节点平均延迟相比在用节点必须降低超过此绝对时延（毫秒）才触发切换，避免网络微小波动导致局域网长连接频繁重连。'));
		o.value('0', _('关闭 (任意优化均切换)'));
		o.value('10', '10 ms');
		o.value('20', '20 ms');
		o.value('30', '30 ms');
		o.value('50', '50 ms');
		o.value('80', '80 ms');
		o.default = '30';

		o = s.option(form.Value, 'concurrency', _('初筛并发数'),
			_('初筛阶段并发探测的进程数量，推荐范围 5-20。'));
		o.datatype = 'range(2, 30)';
		o.default = '10';

		o = s.option(form.ListValue, 'ip_source', _('候选 IP 来源'),
			_('选择优选测速的候选节点 IP 来源。'));
		o.value('builtin', _('内置优选 IP 池'));
		o.value('custom', _('自定义 IP 或网段'));
		o.value('mixed', _('混合模式'));
		o.default = 'builtin';

		o = s.option(form.DynamicList, 'custom_ips', _('自定义候选 IP 列表'),
			_('填入自定义的 Cloudflare Anycast IP 地址或网段。'));
		o.datatype = 'or(ip4addr, ip4prefix)';
		o.depends('ip_source', 'custom');
		o.depends('ip_source', 'mixed');

		s = m.section(form.NamedSection, 'settings', 'cf-optimizer', _('故障快速倒换'));
		s.anonymous = true;

		o = s.option(form.Flag, 'failover_enabled', _('启用快速故障倒换'),
			_('开启后短周期看门狗将持续监控在用节点健康度，发生严重丢包或阻断时自动秒级倒换至次优备选节点。'));
		o.rmempty = false;
		o.default = '1';

		o = s.option(form.ListValue, 'health_interval', _('健康巡检间隔'),
			_('看门狗对在用节点执行极轻量 HTTP 探活的间隔时间。'));
		o.value('30', _('30 秒'));
		o.value('60', _('60 秒'));
		o.value('120', _('120 秒'));
		o.default = '60';
		o.depends('failover_enabled', '1');

		o = s.option(form.Value, 'fail_threshold', _('连续故障判定阈值'),
			_('探活连续失败达到指定次数后触发次优节点核验与自动倒换，推荐设置为 2 次以避免偶发网络抖动误切换。'));
		o.datatype = 'range(1, 10)';
		o.default = '2';
		o.depends('failover_enabled', '1');

		o = s.option(form.ListValue, 'latency_multiplier', _('延迟劣化容忍倍数'),
			_('当在用节点实测延迟超过基线延迟指定倍数且绝对恶化超过 50ms 时判定为信道拥塞，连续触发将倒换至次优节点。'));
		o.value('1.5', _('1.5 倍'));
		o.value('2.0', _('2.0 倍'));
		o.value('3.0', _('3.0 倍'));
		o.value('0', _('禁用'));
		o.default = '2.0';
		o.depends('failover_enabled', '1');

		s = m.section(form.NamedSection, 'settings', 'cf-optimizer', _('机房区域过滤'));
		s.anonymous = true;

		o = s.option(form.ListValue, 'colo_filter_mode', _('区域过滤模式'),
			_('设置对 Cloudflare 数据中心机房的筛选策略。'));
		o.value('none', _('不限制'));
		o.value('exclude', _('排除指定机房'));
		o.value('include', _('仅限指定机房'));
		o.default = 'none';

		o = s.option(form.MultiValue, 'colo_list', _('目标机房列表'),
			_('选择需要排除或仅保留的 Cloudflare 常用数据中心机房。'));
		o.value('SIN', _('新加坡 SIN'));
		o.value('HKG', _('香港 HKG'));
		o.value('TPE', _('台北 TPE'));
		o.value('NRT', _('东京 NRT'));
		o.value('KIX', _('大阪 KIX'));
		o.value('ICN', _('首尔 ICN'));
		o.value('KUL', _('吉隆坡 KUL'));
		o.value('BKK', _('曼谷 BKK'));
		o.value('SJC', _('圣何塞 SJC'));
		o.value('LAX', _('洛杉矶 LAX'));
		o.value('FRA', _('法兰克福 FRA'));
		o.value('LHR', _('伦敦 LHR'));
		o.depends('colo_filter_mode', 'exclude');
		o.depends('colo_filter_mode', 'include');

		o = s.option(form.DynamicList, 'custom_colos', _('自定义机房代码'),
			_('填入其他三位大写机场代码，例如 SFO、SEA 等。'));
		o.depends('colo_filter_mode', 'exclude');
		o.depends('colo_filter_mode', 'include');

		return m.render();
	}
});
