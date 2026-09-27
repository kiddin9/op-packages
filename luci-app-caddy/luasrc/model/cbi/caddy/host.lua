local m, s, gs, o

m = Map("caddy", translate("Caddy Host"),
	translate("反向代理 Host 列表 (增删改查). 每条 Host 对应 Caddyfile 里一段 域名:端口 { ... }"))

----------------------------------------------------------------------
-- 通用开关 (全局, 单例 @caddy[0]). 放在 Host 列表上方: 跨所有 Host 生效,
-- 不是某一条 Host 的属性. 后续全局项 (如日志开关) 也加在这个 section 里
----------------------------------------------------------------------
gs = m:section(TypedSection, "caddy")
gs.addremove = false
gs.anonymous = true
gs.nodeps = true

o = gs:option(Flag, "disable_redirect", translate("保留 HTTP (禁用自动跳转 HTTPS)"),
	translate("勾选 = Caddyfile 写 auto_https disable_redirects; 不勾 = 不写, Caddy 默认 HTTP 自动 301 到 HTTPS"))
o.default = 1

o = gs:option(Flag, "log_on", translate("请求日志"),
	translate("勾选 = 各 Host 写访问日志到 [状态] 页的 日志 路径; 不勾 = Caddyfile 不生成 log 块, 不写日志, 省资源"))
o.default = 1

----------------------------------------------------------------------
-- Host (多条) - 增删改查, NPM 的 Proxy Hosts
----------------------------------------------------------------------
s = m:section(TypedSection, "proxy")
s.addremove = true
s.anonymous = true
s.nodeps = true
s.cfgtitle = "name"

o = s:option(Value, "name", translate("名称"),
	translate("给这条 Host 起个名, 便于区分"))
o.rmempty = false

o = s:option(Flag, "enabled", translate("启用"))
o.default = 1

o = s:option(ListValue, "domain", translate("监听域名"),
	translate("从 [Domain] 页的域名列表中选择. 每个域名列两个选项: 裸域 (签 example.com 一张证书, 覆盖裸域) 和 *. 通配符 (签 裸域+通配符 各一张, 覆盖裸域+全部子域, 等价 acme.sh 两条 -d). 只要 Domain 页填了 AK 就一律走 DNS-01, 不依赖 80/443 入站. 需先在 Domain 页创建域名"))
o.rmempty = false
-- 从 UCI 文件读 domain_name: 直接读 /etc/config/caddy, 匹配有引号和没引号两种风格.
-- 比 grep + sed 更稳 (不靠 shell pipeline 转义), 比 uci cursor 更简单 (不依赖 cursor API 版本差异).
local f = io.open("/etc/config/caddy", "r")
if f then
	for line in f:lines() do
		local dn = line:match("option%s+domain_name%s+'([^']+)'")
			or line:match("option%s+domain_name%s+([%w%.%-]+)")
		if dn and #dn > 0 then
			o:value(dn)
			o:value("*." .. dn)
		end
	end
	f:close()
end

o = s:option(Value, "port", translate("监听端口"),
	translate("非标端口可防指纹扫描, 例如 443 / 8443"))
o.datatype = "and(port,min(1))"
o.default = "443"

o = s:option(Value, "target", translate("转发目标"),
	translate("内网后端地址, 形如 192.168.1.x:8080"))
o.rmempty = false

o = s:option(ListValue, "tls_cert", translate("TLS 证书"),
	translate("auto = Caddy 自动签发+自动续签 (Domain 页填了 AK 走 DNS-01, 不依赖 80/443 入站); off = 纯 HTTP 不加密 (内网调试用)"))
o.default = "auto"
o:value("auto")
o:value("off")

o = s:option(Value, "api_key", translate("API Key (可选)"),
	translate("留空 = Caddy 不做 key 校验 (交给后端); 填值 = Caddy 层校验 Authorization: Bearer <key>"))

o = s:option(TextValue, "extra", translate("自定义指令 (可选)"),
	translate("Caddyfile 语法, 原样插入此 Host 块末尾. 用于 path 路由 / rate_limit / encode / basicauth / handle 等表单没覆盖的指令"))
o.rows = 6
o.wrap = "off"

return m
