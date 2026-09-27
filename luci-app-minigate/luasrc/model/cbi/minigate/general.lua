local m, s, o
local sys = require "luci.sys"

m = Map("minigate", "MiniGate 轻网关", "轻量级网关管理：动态域名解析（IPv4/IPv6双栈）、SSL 证书签发、反向代理。")

m.on_after_commit = function(self)
    local en = self.uci:get("minigate", "global", "enabled")
    if en == "1" then
        sys.call("/etc/init.d/minigate restart >/dev/null 2>&1 &")
    else
        sys.call("/etc/init.d/minigate stop >/dev/null 2>&1 &")
    end
end

s = m:section(NamedSection, "global", "global", "服务状态")
s.anonymous = true
s:tab("status", "总览")

local su = luci.dispatcher.build_url("admin/services/minigate/status")

o = s:taboption("status", DummyValue, "_status")
o.rawhtml = true
o.cfgvalue = function()
    local su = luci.dispatcher.build_url("admin/services/minigate/status")
    local au = luci.dispatcher.build_url("admin/services/minigate/proxy_access")
    local gu = luci.dispatcher.build_url("admin/services/minigate/geo_lookup")
    return [[
<div id="mg" style="display:grid;grid-template-columns:repeat(3,1fr);gap:12px">
<div id="mg-ddns-card" style="background:#f8f9fa;border-radius:8px;padding:15px;border-left:4px solid #4caf50">
<div style="font-size:12px;color:#666">动态DNS</div>
<div id="mg-d1" style="font-size:16px;font-weight:bold;margin:5px 0">--</div>
<div id="mg-d2" style="font-size:12px;color:#888"></div>
</div>
<div style="background:#f8f9fa;border-radius:8px;padding:15px;border-left:4px solid #2196f3">
<div style="font-size:12px;color:#666">SSL/TLS 证书</div>
<div id="mg-a1" style="font-size:16px;font-weight:bold;margin:5px 0">--</div>
<div id="mg-a2" style="font-size:12px;color:#888"></div>
</div>
<div style="background:#f8f9fa;border-radius:8px;padding:15px;border-left:4px solid #ff9800">
<div style="font-size:12px;color:#666">反向代理</div>
<div id="mg-p1" style="font-size:16px;font-weight:bold;margin:5px 0">--</div>
<div id="mg-p2" style="font-size:12px;color:#888"></div>
</div>
</div>

<div id="mg-visitors" style="margin-top:16px;background:#f8f9fa;border-radius:8px;padding:15px;border-left:4px solid #9c27b0">
<div style="font-size:12px;color:#666;margin-bottom:8px">访问记录 <span id="mg-v-count" style="color:#9c27b0"></span></div>
<div id="mg-v-list" style="font-size:12px;color:#888">加载中...</div>
</div>

<script type="text/javascript">
var _geoCache={};

function fmtT(iso){
    if(!iso)return'--';
    var m=iso.match(/(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/);
    return m?(m[2]+'-'+m[3]+' '+m[4]+':'+m[5]+':'+m[6]):iso;
}

function queryGeo(ip,cb){
    if(_geoCache[ip]){cb(_geoCache[ip]);return;}
    XHR.get(']] .. gu .. [[',{ip:ip},function(x,d){
        if(d&&d.geo){_geoCache[ip]=d.geo;cb(d.geo);}
        else{_geoCache[ip]='未知';cb('未知');}
    });
}

function loadVisitors(){
    XHR.get(']] .. au .. [[',null,function(x,d){
        var el=document.getElementById('mg-v-list');
        var ct=document.getElementById('mg-v-count');
        if(!d||!d.visitors||d.visitors.length===0){
            el.innerHTML='<span style="color:#999">暂无访问记录</span>';
            ct.textContent='';
            return;
        }
        ct.textContent='('+d.visitors.length+' 个IP)';
        var h='<table style="width:100%;border-collapse:collapse">';
        h+='<tr style="border-bottom:1px solid #e0e0e0;color:#666"><td style="padding:4px 8px">状态</td><td style="padding:4px 8px">IP 地址</td><td style="padding:4px 8px">归属地</td><td style="padding:4px 8px">最后访问</td><td style="padding:4px 8px">域名</td><td style="padding:4px 8px">次数</td></tr>';
        for(var i=0;i<d.visitors.length;i++){
            var v=d.visitors[i];
            var dot=v.online
                ?'<span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:#4caf50;margin-right:4px" title="在线"></span>'
                :'<span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:#ccc;margin-right:4px" title="离线"></span>';
            var stxt=v.online?'<span style="color:#4caf50;font-size:11px">在线</span>':'<span style="color:#999;font-size:11px">离线</span>';
            h+='<tr style="border-bottom:1px solid #f0f0f0">';
            h+='<td style="padding:5px 8px;white-space:nowrap">'+dot+stxt+'</td>';
            h+='<td style="padding:5px 8px"><code style="background:#e8eaf6;padding:1px 6px;border-radius:3px;font-size:12px">'+v.ip+'</code></td>';
            h+='<td style="padding:5px 8px" id="geo-'+i+'"><span style="color:#bbb;font-size:11px">查询中...</span></td>';
            h+='<td style="padding:5px 8px;white-space:nowrap;font-size:11px">'+fmtT(v.last_time)+'</td>';
            h+='<td style="padding:5px 8px;font-size:11px">'+v.domain+'</td>';
            h+='<td style="padding:5px 8px;font-size:11px">'+v.count+'</td>';
            h+='</tr>';
        }
        h+='</table>';
        el.innerHTML=h;
        // 逐个查询归属地（避免并发太多）
        var qi=0;
        function nextGeo(){
            if(qi>=d.visitors.length)return;
            var idx=qi;qi++;
            queryGeo(d.visitors[idx].ip,function(loc){
                var ge=document.getElementById('geo-'+idx);
                if(ge)ge.innerHTML='<span style="font-size:11px">'+loc+'</span>';
                setTimeout(nextGeo,150);
            });
        }
        nextGeo();
    });
}

XHR.poll(6,']] .. su .. [[',null,function(x,d){
if(!d)return;
var d1=document.getElementById('mg-d1'),d2=document.getElementById('mg-d2');
var card=document.getElementById('mg-ddns-card');
if(d.ddns_list&&d.ddns_list.length>0){
var e=d.ddns_list[0];
var c=e.status=='ok'?'#4caf50':(e.status=='partial'?'#ff9800':(e.enabled=='1'?'#f44336':'#999'));
var l=e.status=='ok'?'\u2713 \u8fd0\u884c\u4e2d':(e.status=='partial'?'\u26a0 \u90e8\u5206\u6210\u529f':(e.enabled=='1'?'\u26a0 \u5f02\u5e38':'\u672a\u542f\u7528'));
card.style.borderLeftColor=c;
d1.innerHTML='<span style="color:'+c+'">'+l+'</span>';
var info=(e.domain||'')+'\n';
if(e.last_ip)info+='A: '+e.last_ip+'\n';
if(e.last_ip6)info+='AAAA: '+e.last_ip6+'\n';
if(e.status_msg)info+=e.status_msg+'\n';
if(e.last_update)info+='\u66f4\u65b0: '+e.last_update+'\n';
if(e.next_sync)info+='\u4e0b\u6b21: '+e.next_sync;
if(d.ddns_list.length>1)info+='\n(+'+(d.ddns_list.length-1)+' \u6761\u8bb0\u5f55)';
d2.innerHTML=info.replace(/\n/g,'<br>');
}else{d1.innerHTML='<span style="color:#999">\u672a\u914d\u7f6e</span>';d2.textContent='';card.style.borderLeftColor='#999';}

var a1=document.getElementById('mg-a1'),a2=document.getElementById('mg-a2');
if(d.acme&&d.acme.enabled=='1'){
a1.innerHTML=d.acme.status=='ok'?'<span style="color:#2196f3">\u2713 \u6709\u6548</span>':'<span style="color:#f44336">'+d.acme.status+'</span>';
a2.innerHTML=(d.acme.last_domain||'')+(d.acme.cert_expiry?'<br>\u8fc7\u671f: '+d.acme.cert_expiry:'');
}else{a1.innerHTML='<span style="color:#999">\u672a\u542f\u7528</span>';a2.textContent='';}

var p1=document.getElementById('mg-p1'),p2=document.getElementById('mg-p2');
p1.innerHTML=d.proxy_running?'<span style="color:#ff9800">\u2713 \u8fd0\u884c\u4e2d</span>':'<span style="color:#999">\u5df2\u505c\u6b62</span>';
var pinfo='';
if(d.proxy_rules&&d.proxy_rules.length>0){
for(var i=0;i<d.proxy_rules.length;i++){
var r=d.proxy_rules[i];
var url=r.scheme+'://'+r.domain+(r.listen_port!='443'&&r.listen_port!='80'?':'+r.listen_port:'');
var v6tag=r.ipv6_listen=='1'?' <span style="color:#2196f3;font-size:10px">[IPv6]</span>':'';
pinfo+='<div style="font-size:11px;margin-top:3px"><span style="color:#4caf50">'+url+'</span>'+v6tag+' \u2192 '+r.target+'</div>';
}}else if(d.proxy_running){pinfo='Nginx \u8fd0\u884c\u4e2d';}
p2.innerHTML=pinfo;
});

loadVisitors();
setInterval(loadVisitors,15000);
</script>
]] end

s = m:section(NamedSection, "global", "global", "全局设置")
s.anonymous = true
o = s:option(Flag, "enabled", "启用 MiniGate")
o.description = "总开关。关闭后停止 DDNS 定时任务、ACME 续期和反向代理。保存后立即生效。"
o.rmempty = false

o = s:option(Flag, "ipv6_listen", "反向代理监听 IPv6")
o.description = "开启后，Nginx 反向代理将同时监听 IPv4 和 IPv6 地址（listen [::]:port）。"
o.rmempty = false
o.default = "0"

return m
