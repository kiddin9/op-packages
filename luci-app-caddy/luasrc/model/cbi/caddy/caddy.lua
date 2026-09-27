local m, s, o

m = Map("caddy", translate("Caddy 状态"),
	translate("全局配置: 启用 Caddy / 公共开关 / 程序与日志路径. 反向代理 Host 在 [Host] 标签页增删改查") .. "<br/>" ..
	[[<a href="https://github.com/andangel/luci-app-caddy" target="_blank">]] ..
	translate("github.com/andangel/luci-app-caddy") .. "</a>&nbsp;&nbsp;" ..
	[[<a href="https://caddyserver.com/docs/" target="_blank">]] ..
	translate("caddyserver.com/docs/ (Caddy 官方文档)") .. [[</a>]])

m:section(SimpleSection).template = "caddy/caddy_status"

----------------------------------------------------------------------
-- 全局设置 (单例) - JSON 里的 global 对象, 只有一条, 只有"改", 没有增删
----------------------------------------------------------------------
s = m:section(TypedSection, "caddy")
s.addremove = false
s.anonymous = true

o = s:option(Flag, "enabled", translate("启用 Caddy"))
o.rmempty = false
o.default = 1

o = s:option(Button, "restart", translate("重启 Caddy"))
o.inputtitle = translate("重启 Caddy")
o.description = translate("按全局 + Host 配置重新生成 Caddyfile 并重启 Caddy")
o.inputstyle = "apply"
o:depends("enabled", "1")
o.write = function()
	os.execute("/etc/init.d/caddy restart")
end

o = s:option(Button, "validate", translate("检测配置文件"))
o.rawhtml = true
o.template = "caddy/admin_info"

--- 主程序 ---
o = s:option(Value, "bin_dir", translate("主程序"),
	translate("caddy 二进制完整路径"))
o.default = "/usr/sbin/caddy"
o.placeholder = "/usr/sbin/caddy"

o = s:option(Value, "download_url", translate("下载地址(可选)"),
	translate("留空用默认 GitHub latest Release. 填了则用该 URL (可换镜像/固定版本). 下载带重试+SHA256 校验"))
o.placeholder = "https://github.com/andangel/luci-app-caddy/releases/latest/download/caddy_linux_arm64"

o = s:option(Button, "download", translate("下载并重启"))
o.rawhtml = true
o.template = "caddy/download"

--- 日志 ---
o = s:option(Value, "log_dir", translate("日志"),
	translate("各 Host 的访问日志写入此文件, 建议放 /tmp 以免占用闪存"))
o.default = "/tmp/caddy/requests.log"
o.placeholder = "/tmp/caddy/requests.log"

return m
