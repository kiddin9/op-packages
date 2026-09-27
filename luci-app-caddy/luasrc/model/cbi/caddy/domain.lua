local m, s, o
local uci = require("luci.model.uci").cursor()

m = Map("caddy", translate("Caddy Domain"),
	translate("域名列表 (增删改查). 每条域名对应一个阿里云账号 (AK), 该域名的 TLS 证书和 DDNS 都用这份 AK"))

--- Domain (多条) - 增删改查, 每条 = 一个域名 + 对应的阿里云 AK + DDNS 参数 ---
--- anonymous: 用户点"添加"即可, 无需填 UCI 标识符 (域名含 . 不合 UCI 命名规范) ---
s = m:section(TypedSection, "domain")
s.addremove = true
s.anonymous = true
s.nodeps = true
s.cfgtitle = "domain_name"

o = s:option(Value, "domain_name", translate("域名"),
	translate("例如 example.com. Host 页的监听域名下拉从这里取"))
o.rmempty = false

o = s:option(Value, "key_id", translate("阿里云 Access Key ID"),
	translate("该域名的 AliDNS 写权限 AK. 需要 AliyunDNS 的 Read/Write 权限"))
o.rmempty = false

o = s:option(Value, "key_secret", translate("阿里云 Access Key Secret"))
o.password = true
o.rmempty = false

--- DDNS 子块: 勾选 ddns_on 才显示以下字段 ---
o = s:option(Flag, "ddns_on", translate("启用 DDNS (更新 A 记录)"),
	translate("勾选 = 生成的 Caddyfile 包含该域名的 aliyun_ddns 块, 定期把公网 IP 写入 A 记录"))
o.default = 0

o = s:option(TextValue, "ddns_records", translate("额外记录名 (每行一条)"),
	translate("每行一个子域名前缀, 用换行分隔, 不要带主域名. 例如填 mail 会更新 mail.example.com, 填 www 会更新 www.example.com. 留空 = 只更新 @ 主域 A 记录"))
o.rows = 3
o.wrap = "off"
o:depends("ddns_on", "1")

o = s:option(ListValue, "ddns_wan_iface", translate("IP 获取方式"),
	translate("public = 公网查询 (api.ipify.org 等取出口 IP); 选接口 = 直读该网卡 IPv4. 一般填 pppoe-wan, 下拉自动列出路由器实际接口"))
o:value("public")
local netf = io.popen("ls /sys/class/net 2>/dev/null")
if netf then
	for line in netf:lines() do
		local name = line:match("%S+")
		-- 只保留 WAN 口 (名字含 wan, 如 pppoe-wan / eth0-wan), 过滤掉 LAN/WiFi/桥等无关设备
		if name and name:lower():find("wan", 1, true) then
			o:value(name)
		end
	end
	netf:close()
end
o.default = "pppoe-wan"
o:depends("ddns_on", "1")

o = s:option(Value, "ddns_check_interval", translate("检查间隔"),
	translate("多久检查一次 A 记录是否需要更新"))
o.default = "5m"
o:depends("ddns_on", "1")

o = s:option(Value, "ddns_ttl", translate("TTL"),
	translate("A 记录 TTL, 影响公网 DNS 生效速度"))
o.default = "60s"
o:depends("ddns_on", "1")

return m
