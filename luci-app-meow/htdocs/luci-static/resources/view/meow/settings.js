'use strict';
'require view';
'require form';
'require dom';
'require fs';
'require tools.meow_settings as settings';
'require poll';
'require uci';
'require tools.meow as meow';

function renderStatus(running) {
	return running ? E('span',{style:'color:#2e7d32; font-weight:bold;'},_('RUNNING')) :
		E('span',{style:'color:#c62828; font-weight:bold;'},_('NOT RUNNING'));
}

return view.extend({
	load:function(){return Promise.all([uci.load('meow'),uci.load('network')]);},
	render:function(){
		var m=new form.Map('meow',_('meow'),
			_('Service and transparent-proxy settings. Saving validates the YAML; use Configuration for raw YAML edits.'));
		var save=m.save;
		m.save=function(callback,silent){
			var rollback;
			return save.call(this,function(){
				return Promise.resolve().then(callback).then(function(){return settings.save();}).then(function(undo){rollback=undo;});
			},silent).catch(function(error){return Promise.resolve(rollback&&rollback()).then(function(){throw error;});});
		};

		var s=m.section(form.NamedSection,'main','meow',_('Service'));
		s.tab('basic',_('Basic')); s.tab('advanced',_('Advanced'));

		var o=s.taboption('basic',form.DummyValue,'_status',_('Status'));
		o.rawhtml=true;
		o.cfgvalue=function(){
			var node=E('span',{},_('Collecting data…'));
			poll.add(function(){return meow.serviceRunning().then(function(r){dom.content(node,renderStatus(r));});});
			return node;
		};

		o=s.taboption('basic',form.Flag,'enabled',_('Enable meow'),_('Start meow now and at boot.'));
		o.rmempty=false;
		o=s.taboption('basic',form.Value,'panel_port',_('Web panel port'),_('Port of the built-in web panel and REST API.'));
		o.datatype='port'; o.default='9090'; o.rmempty=false;
		o=s.taboption('basic',form.Value,'secret',_('Panel password'),_('API secret; leave empty to keep the panel loopback-only.'));
		o.password=true;

		o=s.taboption('advanced',form.Value,'config_file',_('Configuration file'));
		o.default='/etc/meow/config.yaml'; o.readonly=true; o.rmempty=false;
		o=s.taboption('advanced',form.Value,'work_dir',_('Working directory'));
		o.default='/etc/meow'; o.readonly=true; o.rmempty=false;

		s=m.section(form.NamedSection,'tproxy','transparent',_('Transparent proxy'),
			_('Proxy LAN devices without configuring each one.'));
		s.addremove=false; s.tab('basic',_('Basic')); s.tab('advanced',_('Advanced'));

		o=s.taboption('basic',form.DummyValue,'_gateway',_('Status'));
		o.rawhtml=true;
		o.cfgvalue=function(){
			var node=E('span',{},_('Collecting data…'));
			poll.add(function(){return fs.exec('/usr/share/meow/gateway.sh',['status']).catch(function(){return {code:1};}).then(function(res){
				dom.content(node,uci.get('meow','tproxy','enabled')!=='1'?E('em',{},_('Off')):res.code===0?renderStatus(true):E('span',{style:'color:#ef6c00;'},_('Waiting')));
			});});
			return node;
		};
		o=s.taboption('basic',form.Flag,'enabled',_('Proxy LAN devices')); o.rmempty=false;
		o=s.taboption('basic',form.ListValue,'mode',_('Traffic to proxy'));
		o.value('tproxy',_('TCP and UDP')); o.value('redirect',_('TCP only')); o.default='tproxy';
		o=s.taboption('basic',form.ListValue,'interface',_('LAN interface'));
		uci.sections('network','interface',function(sec){if(sec['.name']!=='loopback')o.value(sec['.name']);}); o.default='lan';
		o=s.taboption('basic',form.Flag,'dns_hijack',_('Handle LAN DNS')); o.default='1'; o.rmempty=false;
		o=s.taboption('advanced',form.Value,'tproxy_port',_('Listener port')); o.datatype='port'; o.default='7893';
		o=s.taboption('advanced',form.Value,'dns_port',_('DNS port')); o.datatype='port'; o.default='1053'; o.depends('dns_hijack','1');
		o=s.taboption('advanced',form.Flag,'ipv6',_('Proxy IPv6')); o.rmempty=false; o.depends('mode','redirect');
		o=s.taboption('advanced',form.DynamicList,'bypass',_('Never proxy these destinations')); o.datatype='cidr';

		return m.render();
	}
});
