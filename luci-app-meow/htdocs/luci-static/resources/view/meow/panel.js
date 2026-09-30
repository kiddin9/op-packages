'use strict';
'require view';
'require ui';
'require uci';
'require tools.meow as meow';

function randomSecret() {
	var bytes = new Uint8Array(32);
	window.crypto.getRandomValues(bytes);
	return Array.prototype.map.call(bytes, function(b) { return ('0'+b.toString(16)).slice(-2); }).join('');
}

return view.extend({
	load:function(){return uci.load('meow');},
	handleEnableLan:function(){
		uci.set('meow','main','secret',randomSecret());
		return uci.save().then(function(){return uci.apply();})
			.then(function(){return new Promise(function(r){setTimeout(r,3000);});})
			.then(function(){location.reload();})
			.catch(function(e){ui.addNotification(null,E('p',_('Failed to set the panel password: %s').format(e.message)),'error');});
	},
	renderLocalOnly:function(){
		return E('div',{class:'alert-message notice'},[
			E('p',{},[E('strong',{},_('The panel is only reachable from the router itself.')),' ',_('Set an API secret to open it from this browser.')]),
			E('button',{class:'cbi-button cbi-button-positive',click:ui.createHandlerFn(this,'handleEnableLan')},_('Generate a password and enable the panel'))
		]);
	},
	render:function(){
		var url=meow.panelURL();
		var body;
		if(!meow.secret()) body=this.renderLocalOnly();
		else if(window.location.protocol==='https:')
			body=E('p',{},_('Open the panel in a new tab. The standalone panel uses HTTP.'));
		else body=E('iframe',{src:url,style:'width:100%; min-height:75vh; border:none; border-radius:3px;'});
		return E('div',{class:'cbi-map'},[
			E('h2',{},_('meow Panel')),
			E('div',{class:'cbi-map-descr'},meow.secret()?[_('Built-in web panel served by the meow REST API. '),E('a',{href:url,target:'_blank',rel:'noopener'},_('Open in a new tab'))]:_('Built-in web panel served by the meow REST API.')),
			body
		]);
	}
});
