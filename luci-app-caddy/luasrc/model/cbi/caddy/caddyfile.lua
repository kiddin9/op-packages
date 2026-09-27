local m, s, o

-- 手动 Caddyfile 编辑: 路径从 UCI caddy_file 取 (默认 /etc/caddy/Caddyfile),
-- 与 init.d 里 G_FILE 一致, 避免用户在 [状态] 页改 bin_dir/log_dir 后此处仍写死路径.
local uci = require("luci.model.uci").cursor()
-- get_first 返回的是 section name 而非字段值, 必须用 get(cfg, section, key) 取字段
local cf_file = uci:get("caddy", "caddy", "caddy_file") or "/etc/caddy/Caddyfile"

local cur_caddyfile
local cfh = io.open(cf_file, "r")
if cfh then
	cur_caddyfile = cfh:read("*a")
	cfh:close()
end

m = Map("caddy", translate("Caddy 配置 (手动)"),
	translate("直接编辑 当前 Caddyfile (" .. cf_file .. "). 默认载入当前文件. 注意: 在 [主机] 页重启 Caddy 时会按表单重新生成并覆盖此页内容"))

s = m:section(TypedSection, "caddy")
s.addremove = false
s.anonymous = true

o = s:option(TextValue, "caddyfile", translate("Caddyfile"),
	translate("完整 Caddyfile. 要 Caddy 的任何功能 (forward_proxy / encode / basicauth / reverse_proxy ...) 都写在这里<br/>"
	.. "如需设置密码, 用命令生成 hash:  caddy hash-password --plaintext 新密码"))
o.default = cur_caddyfile
o.rows = 25
o.wrap = "off"

o = s:option(Button, "apply_caddyfile", translate("写入并重启 Caddy"))
o.inputtitle = translate("写入并重启 Caddy")
o.description = translate("把上方内容写入当前 Caddyfile 并重启 Caddy (下次 [主机] 页重启 Caddy 会覆盖)")
o.inputstyle = "apply"
o.write = function(_, value)
	-- 经 /tmp 中转, 避免写一半坏掉 Caddyfile; 写完 mv 原子替换
	local tmp = "/tmp/caddyfile_manual.tmp"
	local f = io.open(tmp, "w")
	if f then
		f:write(value or "")
		f:close()
		os.execute(string.format("cp '%s' '%s' && rm -f '%s' && /etc/init.d/caddy restart", tmp, cf_file, tmp))
	end
end

return m
