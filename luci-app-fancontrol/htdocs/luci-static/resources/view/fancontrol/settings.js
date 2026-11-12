'use strict';
'require view';
'require form';

return view.extend({
	render: function() {
		var m, s, o;

		m = new form.Map('fancontrol', _('风扇控制') + ' - ' + _('温控配置'),
			_('配置香蕉派 BPI-R4 的 PWM 智能风扇调速策略与温度响应区间。'));

		s = m.section(form.NamedSection, 'global', 'fancontrol', _('参数设置'));
		s.anonymous = false;

		o = s.option(form.Flag, 'enabled', _('启用服务'),
			_('开启风扇温控自动守护服务。'));
		o.rmempty = false;
		o.default = '1';

		o = s.option(form.ListValue, 'mode', _('工作模式'),
			_('选择风扇的控制策略模式。'));
		o.value('auto', _('阶梯温控模式'));
		o.value('manual', _('手动定速模式'));
		o.value('kernel', _('内核接管模式'));
		o.default = 'auto';

		o = s.option(form.Value, 'interval', _('检测周期 (秒)'),
			_('温度轮询检测的时间间隔，推荐 3 到 10 秒。'));
		o.datatype = 'range(1, 60)';
		o.default = '5';
		o.depends('mode', 'auto');

		o = s.option(form.Flag, 'start_spin', _('启动自检清洁'),
			_('服务启动时全速转动 2 秒，清洁积灰并确保轴承起步运转。'));
		o.default = '1';
		o.depends('mode', 'auto');
		o.depends('mode', 'manual');

		// 手动模式档位
		o = s.option(form.ListValue, 'manual_level', _('手动常开档位'),
			_('指定风扇持续运转的固定档位。'));
		o.value('0', _('0 级 [停转 0%]'));
		o.value('1', _('1 级 [低速 31%]'));
		o.value('2', _('2 级 [中速 50%]'));
		o.value('3', _('3 级 [全速 100%]'));
		o.default = '2';
		o.depends('mode', 'manual');

		// 阶梯模式各档温度
		o = s.option(form.Value, 'temp_low', _('1 级低速触发温度 (°C)'),
			_('温度达到此数值时启动 1 级低速 (约 31% 占空比)，低于该值停转。'));
		o.datatype = 'range(30, 90)';
		o.default = '45';
		o.depends('mode', 'auto');

		o = s.option(form.Value, 'temp_med', _('2 级中速触发温度 (°C)'),
			_('温度达到此数值时提升至 2 级中速 (约 50% 占空比)。'));
		o.datatype = 'range(35, 100)';
		o.default = '60';
		o.depends('mode', 'auto');

		o = s.option(form.Value, 'temp_high', _('3 级全速触发温度 (°C)'),
			_('温度达到此数值时提升至 3 级全速 (100% 占空比)。'));
		o.datatype = 'range(40, 110)';
		o.default = '75';
		o.depends('mode', 'auto');

		o = s.option(form.Value, 'hysteresis', _('换挡回差温度 (°C)'),
			_('降温换挡的滞后温差。例如 60°C 升至中速，需降至 57°C 才会降回低速，防止临界点频繁启停。'));
		o.datatype = 'range(1, 10)';
		o.default = '3';
		o.depends('mode', 'auto');

		return m.render();
	}
});
