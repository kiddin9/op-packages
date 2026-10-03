'use strict';
'require view';
'require form';
'require fs';
'require ui';

return view.extend({
  load: function() {
    return L.resolveDefault(fs.exec('/usr/bin/cf-dns-speedtest', [ 'ui' ]), {
      stdout: 'status=idle\nbest_ip=-\nenabled=0\nlast_run=-\nscheduled=0\n'
    });
  },

  render: function(data) {
    var m, s, o;
    m = new form.Map('cf_dns_speedtest', _('Cloudflare DNS 优选'),
      _('测速后仅将指定域名交给独立 mosdns 实例返回优选 IP；其他 DNS 查询继续使用原有链路。'));
    s = m.section(form.TypedSection, 'main', _('设置'));
    s.anonymous = true;
    o = s.option(form.Flag, 'enabled', _('启用'));
    o.rmempty = false;
    o = s.option(form.DynamicList, 'domains', _('Cloudflare 域名'));
    o.datatype = 'hostname';
    o.placeholder = 'www.cloudflare.com';
    o = s.option(form.Value, 'listen_port', _('mosdns 旁路端口'));
    o.datatype = 'port'; o.default = '5335';
    o = s.option(form.Value, 'schedule', _('定时任务'));
    o.placeholder = '0 5 * * *';
    o.description = _('标准 cron 表达式，留空则不定时测速。保存后请点击“应用 DNS 配置”。');
    o = s.option(form.Value, 'threads', _('测速线程'));
    o.datatype = 'range(1,64)'; o.default = '4';
    o = s.option(form.Value, 'probes', _('延迟测速次数'));
    o.datatype = 'range(1,20)'; o.default = '4';
    o = s.option(form.Value, 'download_count', _('下载测速数量'));
    o.datatype = 'range(1,20)'; o.default = '5';
    o = s.option(form.Value, 'timeout', _('单项超时（秒）'));
    o.datatype = 'range(1,30)'; o.default = '5';
    o = s.option(form.Value, 'max_latency', _('最大延迟（毫秒）'));
    o.datatype = 'range(1,9999)'; o.default = '300';
    o = s.option(form.Value, 'min_speed', _('最低速度（MB/s）'));
    o.datatype = 'ufloat'; o.default = '1';
    o = s.option(form.Value, 'test_url', _('测速 URL'));
    o.datatype = 'string';

    s = m.section(form.NamedSection, 'runtime', 'runtime', _('运行状态'));
    s.render = function() {
      var lines = String(data.stdout || '').trim().split('\n');
      var status = (lines.shift() || 'status=idle').replace(/^status=/, '');
      var ip = (lines.shift() || 'best_ip=-').replace(/^best_ip=/, '');
      var enabled = (lines.shift() || 'enabled=0').replace(/^enabled=/, '');
      var lastRun = (lines.shift() || 'last_run=-').replace(/^last_run=/, '');
      var scheduled = (lines.shift() || 'scheduled=0').replace(/^scheduled=/, '');
      var rows = lines.filter(function(line) { return line.length; }).map(function(line) { return line.split(','); });
      var widths = [ '20%', '10%', '10%', '10%', '15%', '20%', '15%' ];
      var resultTable = rows.length ? E('div', { style: 'width:100%;overflow-x:auto;margin-top:1rem' }, [
        E('table', { style: 'display:table;width:100%;min-width:620px;table-layout:fixed;border-collapse:collapse' }, [
          E('thead', {}, E('tr', {}, rows[0].map(function(cell, index) {
            return E('th', { style: 'width:' + widths[index] + ';padding:.65rem .6rem;text-align:left;white-space:nowrap;border-bottom:1px solid var(--border-color-medium,#444)' }, cell);
          }))),
          E('tbody', {}, rows.slice(1).map(function(row) {
            return E('tr', {}, row.map(function(cell, index) {
              return E('td', { style: 'width:' + widths[index] + ';padding:.65rem .6rem;text-align:left;white-space:nowrap;border-bottom:1px solid var(--border-color-low,#222)' }, cell);
            }));
          }))
        ])
      ]) : E('p', { style: 'margin-top:1rem' }, _('尚无测速结果'));
      function card(label, value) {
        return E('div', { style: 'padding:.8rem;border:1px solid var(--border-color-medium,#333);border-radius:6px' }, [
          E('small', {}, label), E('div', { style: 'margin-top:.3rem;font-weight:600' }, value)
        ]);
      }
      return E('div', { class: 'cbi-section' }, [
        E('div', { style: 'display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:.75rem;margin-bottom:1rem' }, [
          card(_('状态'), status), card(_('当前优选 IP'), ip),
          card(_('DNS 应用'), enabled === '1' ? _('已启用') : _('未启用')),
          card(_('上次测速'), lastRun), card(_('定时任务'), scheduled !== '0' ? _('已生效') : _('未生效'))
        ]),
        E('div', { style: 'display:flex;flex-wrap:wrap;gap:.5rem;align-items:center' }, [
          E('button', { class: 'btn cbi-button-action', click: ui.createHandlerFn(this, function() {
            return fs.exec('/usr/bin/cf-dns-speedtest', [ 'start' ]).then(function() {
              ui.addNotification(null, E('p', _('测速已在后台启动。')));
              window.setTimeout(function() { location.reload(); }, 1500);
            });
          }) }, _('立即测速')),
          E('button', { class: 'btn cbi-button-negative', click: ui.createHandlerFn(this, function() {
            return fs.exec('/usr/bin/cf-dns-speedtest', [ 'stop' ]).then(function() { location.reload(); });
          }) }, _('停止测速')),
          E('button', { class: 'btn cbi-button-apply', click: ui.createHandlerFn(this, function() {
            return fs.exec('/usr/bin/cf-dns-speedtest', [ 'apply' ]).then(function() { location.reload(); });
          }) }, _('应用 DNS 配置')),
          E('button', { class: 'btn', click: function() { location.reload(); } }, _('刷新状态'))
        ]),
        resultTable
      ]);
    };
    return m.render();
  }
});
