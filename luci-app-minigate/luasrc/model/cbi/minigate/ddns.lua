local m,s,o
local sys=require"luci.sys"

m=Map("minigate","MiniGate - 动态DNS","支持多域名、IPv4/IPv6双栈。保存后立即同步。需先启用全局开关。")

m.on_after_commit=function(self)
    sys.call("/bin/sh /usr/lib/minigate/ddns.sh force >/dev/null 2>&1 &")
    local en=self.uci:get("minigate","global","enabled")
    if en=="1"then sys.call("/etc/init.d/minigate restart >/dev/null 2>&1 &") end
end

s=m:section(TypedSection,"ddns","DDNS 记录")
s.anonymous=true; s.addremove=true; s.sortable=true

o=s:option(Flag,"enabled","启用"); o.rmempty=false

o=s:option(Value,"domain","域名"); o.rmempty=false; o.placeholder="*.example.com 或 home.example.com"

o=s:option(Value,"cf_zone_id","Zone ID"); o.rmempty=false; o.placeholder="Cloudflare 区域 ID"

o=s:option(Value,"cf_api_token","API 令牌"); o.rmempty=false; o.password=true

-- ====== 协议版本 ======
o=s:option(ListValue,"ip_version","协议版本")
o:value("ipv4","仅 IPv4（A 记录）")
o:value("ipv6","仅 IPv6（AAAA 记录）")
o:value("dual","双栈（A + AAAA）")
o.default="ipv4"
o.description="选择更新哪种 DNS 记录。双栈模式同时更新 A 和 AAAA 记录。"

o=s:option(ListValue,"ip_source","IP 来源")
o:value("interface","从网卡获取"); o:value("url","从外部URL获取"); o.default="interface"

-- IPv4 网卡
o=s:option(ListValue,"interface","IPv4 网络接口"); o.default="wan"
local uci=require"luci.model.uci".cursor()
uci:foreach("network","interface",function(sec) if sec[".name"]~="loopback"then o:value(sec[".name"],sec[".name"])end end)
o:depends("ip_source","interface")

-- IPv4 URL
o=s:option(ListValue,"ip_url","IPv4 获取地址")
o:value("http://ip.3322.net","ip.3322.net")
o:value("http://members.3322.org/dyndns/getip","members.3322.org")
o:value("http://ns1.dnspod.net:6666","ns1.dnspod.net (腾讯)")
o:value("http://ip.tool.chinaz.com/getip","chinaz.com (站长工具)")
o.default="http://ip.3322.net"
o.description="旁路由/代理环境自动绕过代理直连获取真实公网IP"
o:depends("ip_source","url")

-- IPv6 网卡
o=s:option(ListValue,"interface6","IPv6 网络接口"); o.default="wan6"
o.description="用于获取 IPv6 地址的接口（通常为 wan6）"
uci:foreach("network","interface",function(sec) if sec[".name"]~="loopback"then o:value(sec[".name"],sec[".name"])end end)
o:depends({ip_source="interface",ip_version="ipv6"})
o:depends({ip_source="interface",ip_version="dual"})

-- IPv6 URL
o=s:option(ListValue,"ip_url6","IPv6 获取地址")
o:value("https://api6.ipify.org","api6.ipify.org")
o:value("https://6.ipw.cn","6.ipw.cn")
o:value("https://v6.ident.me","v6.ident.me")
o:value("https://ifconfig.co","ifconfig.co (v6)")
o:value("http://v6.66666.host:66/ip","v6.66666.host")
o.default="https://api6.ipify.org"
o.description="仅通过 IPv6 连接获取地址"
o:depends({ip_source="url",ip_version="ipv6"})
o:depends({ip_source="url",ip_version="dual"})

o=s:option(Value,"check_interval","间隔(秒)"); o.datatype="uinteger"; o.default="300"

-- 状态+手动同步
o=s:option(DummyValue,"_info","运行状态"); o.rawhtml=true
o.cfgvalue=function(self,section)
    local st=m.uci:get("minigate",section,"status")or"unknown"
    local msg=m.uci:get("minigate",section,"status_msg")or""
    local ip=m.uci:get("minigate",section,"last_ip")or""
    local ip6=m.uci:get("minigate",section,"last_ip6")or""
    local lu=m.uci:get("minigate",section,"last_update")or""
    local ns=m.uci:get("minigate",section,"next_sync")or""
    local ver=m.uci:get("minigate",section,"ip_version")or"ipv4"

    local h=""
    if st=="ok"then
        h='<span style="color:#4caf50">&#10003; 正常</span>'
    elseif st=="partial"then
        h='<span style="color:#ff9800">&#9888; 部分成功</span>'
    elseif st=="error"then
        h='<span style="color:#f44336">&#10007; '..(msg~=""and msg or"异常")..'</span>'
    else h='<span style="color:#999">未同步</span>' end

    -- 显示 IP 地址
    if ip~=""then h=h..'<br><span style="font-size:11px;color:#888">A: '..ip..'</span>' end
    if ip6~=""then h=h..'<br><span style="font-size:11px;color:#2196f3">AAAA: '..ip6..'</span>' end
    if msg~=""and st~="error"then h=h..'<br><span style="font-size:11px;color:#888">'..msg..'</span>' end
    if lu~=""then h=h..'<br><span style="font-size:11px;color:#888">更新: '..lu..'</span>' end
    if ns~=""then h=h..'<br><span style="font-size:11px;color:#888">下次: '..ns..'</span>' end

    h=h..'<br><button class="cbi-button cbi-button-action" style="margin-top:4px;font-size:12px;padding:2px 10px" '
    h=h..'onclick="doSync(\''..section..'\',this)">手动同步</button>'
    h=h..'<span id="sr-'..section..'" style="margin-left:8px;font-size:12px"></span>'
    return h
end

-- 注入 JS
s=m:section(NamedSection,"global","global"); s.anonymous=true
o=s:option(DummyValue,"_js"," "); o.rawhtml=true
o.cfgvalue=function()
    local url=luci.dispatcher.build_url("admin/services/minigate/ddns_sync")
    return'<script type="text/javascript">function doSync(s,b){b.disabled=true;b.textContent="同步中...";var e=document.getElementById("sr-"+s);e.textContent="";XHR.get("'..url..'",{section:s},function(x,d){b.disabled=false;b.textContent="手动同步";if(d&&d.success){e.innerHTML=\'<span style="color:#4caf50">\\u2713 \'+d.ip+(d.ip6?\' / \'+d.ip6:\'\')+\'</span>\';setTimeout(function(){location.reload()},1500)}else e.innerHTML=\'<span style="color:#f44336">\\u2717 失败</span>\'})}</script>'
end

return m
