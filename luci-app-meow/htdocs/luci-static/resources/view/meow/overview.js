'use strict';
'require view';
'require dom';
'require fs';
'require poll';
'require ui';
'require uci';
'require tools.meow as meow';

var MODES = ['rule', 'global', 'direct'];
var MODE_HELP = {
	rule: _('Traffic follows your rules.'),
	global: _('All traffic goes through the proxy selected in the GLOBAL group.'),
	direct: _('All traffic bypasses the proxies.')
};

function badge(text) {
	return E('span', { class:'label', style:'color:#fff; padding:2px 8px; border-radius:3px; background:#2e7d32;' }, text);
}
function row(label, value) {
	return E('tr', { class:'tr' }, [
		E('td', { class:'td left', width:'33%' }, label),
		E('td', { class:'td left' }, value)
	]);
}
function tabLink(tab, text) {
	return E('a', { href:L.url('admin/services/meow', tab) }, text);
}

return view.extend({
	load: function() { return uci.load('meow'); },
	gatewayActive: function() {
		return fs.exec('/usr/share/meow/gateway.sh', ['status']).then(function(res) {
			return res.code === 0;
		}).catch(function() { return false; });
	},
	refresh: function(nodes) {
		var self = this;
		var enabled = uci.get('meow', 'main', 'enabled') === '1';
		return Promise.all([
			meow.serviceRunning(),
			L.resolveDefault(meow.api('GET', '/version'), null),
			L.resolveDefault(meow.api('GET', '/configs'), null),
			L.resolveDefault(meow.api('GET', '/connections'), null),
			this.gatewayActive()
		]).then(function(r) {
			var running=r[0], version=r[1], cfg=r[2], conns=r[3], gateway=r[4], now=Date.now();
			dom.content(nodes.banner, running ? '' : E('div', {class:'alert-message notice'}, [
				E('strong', {}, enabled ? _('meow is stopped.') : _('meow is disabled.')),
				' ', enabled ? _('Check the Log tab if it did not stop intentionally.') : _('Enable the service to start it.')
			]));
			dom.content(nodes.service, running ? [badge(_('Running')), ' ', version ? 'v'+String(version.version).replace(/^v/,'') : ''] : _('Not running'));
			var tproxy = uci.get('meow','tproxy','enabled') === '1';
			dom.content(nodes.gateway, !tproxy ? E('em',{},_('Off')) : (gateway ? badge(_('Active')) : _('Waiting')));
			var mode = cfg && cfg.mode;
			nodes.modeButtons.forEach(function(btn) {
				var active = mode === btn.getAttribute('data-mode');
				btn.classList.toggle('cbi-button-positive', active);
				btn.disabled = !cfg;
			});
			dom.content(nodes.modeHelp, MODE_HELP[mode] || (running ? '' : _('Available while meow is running.')));
			nodes.actions.start.style.display = running ? 'none' : '';
			nodes.actions.stop.style.display = running ? '' : 'none';
			nodes.actions.restart.style.display = running ? '' : 'none';
			if (conns) {
				var up=conns.uploadTotal||0, down=conns.downloadTotal||0;
				if (self.last) {
					var dt=(now-self.last.t)/1000;
					dom.content(nodes.rate,'↑ %s/s   ↓ %s/s'.format(meow.formatBytes(Math.max(0,up-self.last.up)/dt),meow.formatBytes(Math.max(0,down-self.last.down)/dt)));
				}
				self.last={t:now,up:up,down:down};
				dom.content(nodes.totals,'↑ %s   ↓ %s'.format(meow.formatBytes(up),meow.formatBytes(down)));
				dom.content(nodes.conns,String((conns.connections||[]).length));
			} else {
				self.last=null; dom.content(nodes.rate,'-'); dom.content(nodes.totals,'-'); dom.content(nodes.conns,'-');
			}
		});
	},
	handleMode: function(mode) {
		return meow.api('PATCH','/configs',{mode:mode}).then(L.bind(function(){return this.refresh(this.nodes);},this))
			.catch(function(e){ui.addNotification(null,E('p',_('Failed to switch mode: %s').format(e.message)),'error');});
	},
	service: function(action) {
		var self=this, want=action!=='stop';
		return fs.exec('/etc/init.d/meow',[action]).then(function(res){
			if(res.code!==0) throw new Error(res.stderr||_('Command failed'));
			return new Promise(function(resolve){setTimeout(resolve,1500);});
		}).then(function(){return meow.serviceRunning();}).then(function(running){
			if(running!==want) throw new Error(want? _('meow did not start; see the Log tab.') : _('meow is still running.'));
		}).catch(function(e){ui.addNotification(null,E('p',e.message),'error');}).then(function(){return self.refresh(self.nodes);});
	},
	handleStart:function(){return this.service('start');},
	handleStop:function(){return this.service('stop');},
	handleRestart:function(){return this.service('restart');},
	handleEnable:function(){
		var self=this;
		uci.set('meow','main','enabled','1');
		return uci.save().then(function(){return uci.apply();}).then(function(){return self.service('start');});
	},
	render:function(){
		var self=this;
		function action(name,cls,text){return E('button',{class:'cbi-button '+cls,style:'display:none;',click:ui.createHandlerFn(self,name)},text);}
		var nodes=this.nodes={
			banner:E('div'), service:E('span',{},_('Collecting data…')), gateway:E('span',{},'-'),
			modeHelp:E('div',{style:'margin-top:.4em; color:#888;'}), rate:E('span',{},'-'), totals:E('span',{},'-'), conns:E('span',{},'-'),
			modeButtons:MODES.map(function(mode){return E('button',{class:'cbi-button','data-mode':mode,disabled:true,click:ui.createHandlerFn(self,'handleMode',mode)},mode);}),
			actions:{start:action('handleStart','cbi-button-positive',_('Start')),stop:action('handleStop','cbi-button-negative',_('Stop')),restart:action('handleRestart','cbi-button-apply',_('Restart'))}
		};
		poll.add(function(){return self.refresh(nodes);},3);
		return E('div',{class:'cbi-map'},[
			E('h2',{},_('meow')),
			E('div',{class:'cbi-map-descr'},_('Rule-based proxy compatible with mihomo (Clash Meta) configurations.')),
			nodes.banner,
			E('div',{class:'cbi-section'},[E('table',{class:'table'},[
				row(_('Service'),nodes.service),row(_('Transparent proxy'),nodes.gateway),
				row(_('Proxy mode'),E('div',{},[E('div',{class:'cbi-page-actions'},nodes.modeButtons),nodes.modeHelp])),
				row(_('Current speed'),nodes.rate),row(_('Total traffic'),nodes.totals),row(_('Active connections'),nodes.conns)
			])]),
			E('div',{class:'cbi-page-actions'},[
				meow.secret()?E('a',{class:'cbi-button cbi-button-action',href:meow.panelURL(),target:'_blank',rel:'noopener'},_('Open panel')):
				E('a',{class:'cbi-button cbi-button-action',href:L.url('admin/services/meow/panel')},_('Open panel')),
				' ',nodes.actions.start,' ',nodes.actions.stop,' ',nodes.actions.restart
			])
		]);
	}
});
