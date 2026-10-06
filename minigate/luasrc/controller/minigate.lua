module("luci.controller.minigate", package.seeall)

local function shellquote(value)
    value = tostring(value or "")
    return "'" .. value:gsub("'", "'\"'\"'") .. "'"
end

local function update_response(command)
    local sys = require "luci.sys"
    local jsonc = require "luci.jsonc"
    local fs = require "nixio.fs"
    local raw = sys.exec("/bin/sh /usr/lib/minigate/update.sh " .. command .. " 2>/dev/null") or ""
    local ok, data = pcall(jsonc.parse, raw)
    if not ok or type(data) ~= "table" then
        data = {
            status = "error",
            progress = 0,
            current = "",
            latest = "",
            available = false,
            running = false,
            success = false,
            message = "更新服务返回了无效结果"
        }
    end

    local release_raw = fs.readfile("/tmp/minigate-update-release.json")
    if release_raw and data.latest and data.latest ~= "" then
        local release_ok, release = pcall(jsonc.parse, release_raw)
        if release_ok and type(release) == "table" then
            local tag = tostring(release.tag_name or ""):gsub("^v", "")
            if tag == tostring(data.latest) then
                local title = type(release.name) == "string" and release.name or ("minigate v" .. tag)
                local notes = type(release.body) == "string" and release.body or ""
                data.release_title = title
                data.release_notes = notes
            end
        end
    end
    luci.http.prepare_content("application/json")
    luci.http.write_json(data)
end

function index()
    entry({"admin","services","minigate"}, alias("admin","services","minigate","general"), "minigate", 60).dependent=false
    entry({"admin","services","minigate","general"}, cbi("minigate/general"), "总览", 10)
    entry({"admin","services","minigate","ddns"}, cbi("minigate/ddns"), "动态DNS", 20)
    entry({"admin","services","minigate","acme"}, cbi("minigate/acme"), "SSL 证书", 30)
    entry({"admin","services","minigate","proxy"}, cbi("minigate/proxy"), "反向代理", 40)
    entry({"admin","services","minigate","login_guard"}, cbi("minigate/login_guard"), "登录防护", 45)
    entry({"admin","services","minigate","log"}, template("minigate/log"), "日志", 50)
    entry({"admin","services","minigate","status"}, call("action_status")).leaf=true
    entry({"admin","services","minigate","get_log"}, call("action_get_log")).leaf=true
    entry({"admin","services","minigate","acme_install"}, call("action_acme_install")).leaf=true
    entry({"admin","services","minigate","acme_issue"}, call("action_acme_issue")).leaf=true
    entry({"admin","services","minigate","ddns_sync"}, call("action_ddns_sync")).leaf=true
    entry({"admin","services","minigate","ddns_history"}, call("action_ddns_history")).leaf=true
    entry({"admin","services","minigate","proxy_access"}, call("action_proxy_access")).leaf=true
    entry({"admin","services","minigate","geo_lookup"}, call("action_geo_lookup")).leaf=true
    entry({"admin","services","minigate","lg_status"}, call("action_lg_status")).leaf=true
    entry({"admin","services","minigate","lg_ban"}, call("action_lg_ban")).leaf=true
    entry({"admin","services","minigate","lg_unban"}, call("action_lg_unban")).leaf=true
    entry({"admin","services","minigate","lg_flush"}, call("action_lg_flush")).leaf=true
    entry({"admin","services","minigate","update_status"}, call("action_update_status")).leaf=true
    entry({"admin","services","minigate","update_auto"}, call("action_update_auto")).leaf=true
    entry({"admin","services","minigate","update_check"}, call("action_update_check")).leaf=true
    entry({"admin","services","minigate","update_apply"}, post("action_update_apply")).leaf=true
    entry({"admin","services","minigate","uninstall"}, post("action_uninstall")).leaf=true
end

function action_update_status()
    update_response("status")
end

function action_update_auto()
    update_response("auto")
end

function action_update_check()
    update_response("check")
end

function action_update_apply()
    local sys = require "luci.sys"
    local fs = require "nixio.fs"
    local version = luci.http.formvalue("version")
    local ok = false

    if type(version) ~= "string" or #version > 32 or not (
        version:match("^%d+%.%d+%.%d+$") or version:match("^%d+%.%d+%.%d+%-%d+$")) then
        luci.http.status(400, "Bad Request")
        luci.http.prepare_content("application/json")
        luci.http.write_json({success = false, message = "请先查看更新内容并确认版本"})
        return
    end

    if fs.access("/usr/lib/minigate/update.sh") then
        ok = sys.call("runner=$(mktemp /tmp/minigate-update-run.XXXXXX)" ..
            " && cp /usr/lib/minigate/update.sh \"$runner\" && chmod 700 \"$runner\"" ..
            " && ( ( /bin/sh \"$runner\" apply " .. shellquote(version) ..
            "; rm -f \"$runner\" ) >/dev/null 2>&1 & )") == 0
    end

    luci.http.prepare_content("application/json")
    luci.http.write_json({
        success = ok,
        message = ok and "更新任务已启动" or "无法启动更新任务"
    })
end

function action_uninstall()
    local sys = require "luci.sys"
    local fs = require "nixio.fs"
    local confirm = luci.http.formvalue("confirm")
    local purge = luci.http.formvalue("purge")
    local ok = false

    if confirm ~= "uninstall-minigate" or (purge ~= "0" and purge ~= "1") then
        luci.http.status(400, "Bad Request")
        luci.http.prepare_content("application/json")
        luci.http.write_json({success = false, message = "卸载确认无效，请重新操作"})
        return
    end

    if fs.access("/usr/lib/minigate/uninstall.sh") then
        ok = sys.call("runner=$(mktemp /tmp/minigate-uninstall.XXXXXX)" ..
            " && cp /usr/lib/minigate/uninstall.sh \"$runner\" && chmod 700 \"$runner\"" ..
            " && ( ( sleep 1; /bin/sh \"$runner\" " .. shellquote(purge) ..
            "; rm -f \"$runner\" ) >/dev/null 2>&1 & )") == 0
    end

    luci.http.prepare_content("application/json")
    luci.http.write_json({
        success = ok,
        message = ok and "卸载任务已启动" or "无法启动卸载任务"
    })
end

function action_status()
    local uci=require"luci.model.uci".cursor()
    local pr=false
    local f=io.open("/var/run/minigate-nginx.pid","r")
    if f then local p=f:read("*l"); f:close()
        if p and tonumber(p) then pr=(os.execute("kill -0 "..p.." 2>/dev/null")==0) end
    end
    local al={}
    for _,lf in ipairs({"/var/log/minigate-ddns.log","/var/log/minigate-acme.log","/var/log/minigate-proxy.log"}) do
        local fh=io.open(lf,"r"); if fh then for l in fh:lines() do al[#al+1]=l end; fh:close() end
    end
    local st=#al-19; if st<1 then st=1 end
    local ll={}; for i=st,#al do ll[#ll+1]=al[i] end
    local ca=false; local cf=io.open("/etc/crontabs/root","r")
    if cf then local c=cf:read("*a"); cf:close(); ca=c:find("minigate")~=nil end
    local dl={}
    uci:foreach("minigate","ddns",function(s)
        dl[#dl+1]={
            name=s[".name"],
            enabled=s.enabled or"0",
            domain=s.domain or"",
            ip_version=s.ip_version or"ipv4",
            status=s.status or"unknown",
            status_msg=s.status_msg or"",
            last_ip=s.last_ip or"",
            last_ip6=s.last_ip6 or"",
            last_update=s.last_update or"",
            next_sync=s.next_sync or""
        }
    end)

    -- 全局 IPv6 监听状态
    local ipv6_listen = uci:get("minigate","global","ipv6_listen") or "0"

    -- 收集代理规则信息
    local proxy_rules = {}
    local wc_ports = {}
    uci:foreach("minigate","proxy_wildcard",function(s)
        if (s.enabled == "1" or s.enabled == true) and s.domain then
            local base = (s.domain or ""):gsub("^%*%.","")
            local ssl_val = tostring(s.ssl or "0")
            wc_ports[base] = {port=s.listen_port or "443", ssl=ssl_val}
        end
    end)
    uci:foreach("minigate","subproxy",function(s)
        local parent = s.parent_domain or ""
        local prefix = s.prefix or ""
        local taddr = s.target_addr or ""
        local tport = s.target_port or "80"
        if prefix ~= "" and parent ~= "" then
            local wc = wc_ports[parent] or {}
            local lport = wc.port or "443"
            local ssl_val = wc.ssl or "0"
            local scheme = (ssl_val == "1" or ssl_val == "true") and "https" or "http"
            proxy_rules[#proxy_rules+1] = {domain=prefix.."."..parent, target=taddr..":"..tport, listen_port=lport, scheme=scheme, ipv6_listen=ipv6_listen}
        end
    end)
    uci:foreach("minigate","proxy",function(s)
        if (s.enabled == "1" or s.enabled == true) and s.domain and s.target_addr then
            local ssl_val = tostring(s.ssl or "0")
            local scheme = (ssl_val == "1" or ssl_val == "true") and "https" or "http"
            proxy_rules[#proxy_rules+1] = {domain=s.domain, target=(s.target_addr or "")..":"..(s.target_port or "80"), listen_port=s.listen_port or "443", scheme=scheme, ipv6_listen=ipv6_listen}
        end
    end)

    luci.http.prepare_content("application/json")
    luci.http.write_json({
        enabled=uci:get("minigate","global","enabled")or"0",
        ipv6_listen=ipv6_listen,
        proxy_running=pr,
        cron_active=ca,
        recent_log=table.concat(ll,"\n"),
        ddns_list=dl,
        proxy_rules=proxy_rules,
        acme={
            enabled=uci:get("minigate","acme","enabled")or"0",
            status=uci:get("minigate","acme","status")or"unknown",
            last_domain=uci:get("minigate","acme","last_domain")or"",
            last_issue=uci:get("minigate","acme","last_issue")or"",
            cert_expiry=uci:get("minigate","acme","cert_expiry")or"",
            last_error=uci:get("minigate","acme","last_error")or""
        }
    })
end

function action_get_log()
    local sys=require"luci.sys"; local s=luci.http.formvalue("source")or"all"
    local fs={ddns="/var/log/minigate-ddns.log",acme="/var/log/minigate-acme.log",proxy="/var/log/minigate-proxy.log /var/log/minigate-nginx-error.log"}
    local cmd=s=="all"and"cat /var/log/minigate-*.log 2>/dev/null|tail -200"or"cat "..(fs[s]or"").." 2>/dev/null|tail -200"
    luci.http.prepare_content("application/json"); luci.http.write_json({log=sys.exec(cmd)or""})
end

function action_acme_install()
    local sys=require"luci.sys"; sys.call("/bin/sh /usr/lib/minigate/acme.sh install 2>&1")
    local fs=require"nixio.fs"; local ok=fs.access("/etc/minigate/acme/data/acme.sh")and fs.access("/etc/minigate/acme/data/dnsapi/dns_cf.sh")
    luci.http.prepare_content("application/json"); luci.http.write_json({success=ok,message=ok and"安装成功"or"安装失败"})
end

function action_acme_issue()
    local sys=require"luci.sys"; local d=luci.http.formvalue("domain")or""
    local cmd="/bin/sh /usr/lib/minigate/acme.sh issue"; if d~=""then cmd=cmd.." "..shellquote(d)end
    sys.call(cmd.." 2>&1")
    local uci=require"luci.model.uci".cursor(); local st=uci:get("minigate","acme","status")or"unknown"
    local le=uci:get("minigate","acme","last_error")or""
    local msg=(st=="ok" and le~="")and"现有证书有效；最近一次签发失败，已保留有效证书"or((st=="ok")and"签发成功！"or"签发失败，查看日志")
    luci.http.prepare_content("application/json"); luci.http.write_json({success=(st=="ok"),message=msg})
end

function action_ddns_sync()
    local sys=require"luci.sys"; local sec=luci.http.formvalue("section")or""
    if sec~=""then sys.call("/bin/sh /usr/lib/minigate/ddns.sh single "..shellquote(sec).." 2>&1")
    else sys.call("/bin/sh /usr/lib/minigate/ddns.sh force 2>&1") end
    local uci=require"luci.model.uci".cursor()
    local st=sec~=""and(uci:get("minigate",sec,"status")or"unknown")or"done"
    local ip=sec~=""and(uci:get("minigate",sec,"last_ip")or"")or""
    local ip6=sec~=""and(uci:get("minigate",sec,"last_ip6")or"")or""
    luci.http.prepare_content("application/json"); luci.http.write_json({success=(st=="ok"or st=="partial"),status=st,ip=ip,ip6=ip6})
end

local function history_section_name(value)
    return tostring(value or ""):gsub("[^%w_%-]", "_")
end

local function history_ip_valid(family, ip)
    if family == "ipv4" then
        return ip:match("^%d+%.%d+%.%d+%.%d+$") ~= nil
    end
    return ip:match("^[%x:]+$") ~= nil and ip:find(":", 1, true) ~= nil
end

local function read_history_events(path, family, now)
    local events = {}
    local file = io.open(path, "r")
    if not file then return events end

    for line in file:lines() do
        local raw_ts, ip = line:match("^(%d+)\t([^\t\r\n]+)$")
        local ts = tonumber(raw_ts)
        if ts and ts > 0 and ts <= now + 300 and history_ip_valid(family, ip or "") then
            local previous = events[#events]
            if not previous or previous.ip ~= ip then
                events[#events + 1] = {timestamp=ts, ip=ip}
            end
        end
    end
    file:close()
    table.sort(events, function(a, b) return a.timestamp < b.timestamp end)
    return events
end

function action_ddns_history()
    local uci = require "luci.model.uci".cursor()
    local history_dir = os.getenv("MINIGATE_HISTORY_DIR") or "/etc/minigate/ddns-history"
    local requested = luci.http.formvalue("section") or ""
    local now = os.time()
    local cutoff = now - 86400
    local rows = {}
    local sections = {}

    if #requested > 64 or (requested ~= "" and not requested:match("^[%w_%-]+$")) then
        luci.http.status(400, "Bad Request")
        luci.http.prepare_content("application/json")
        luci.http.write_json({success=false, message="DDNS 记录参数无效"})
        return
    end

    uci:foreach("minigate", "ddns", function(section)
        local name = section[".name"] or ""
        if name ~= "" and (requested == "" or requested == name) then
            sections[#sections + 1] = {
                name=name,
                domain=section.domain or name,
                enabled=(section.enabled == "1" or section.enabled == true),
                ip_version=section.ip_version or "ipv4"
            }
        end
    end)

    for _, section in ipairs(sections) do
        if section.enabled then
            local families = {}
            if section.ip_version == "ipv4" or section.ip_version == "dual" then families[#families + 1] = "ipv4" end
            if section.ip_version == "ipv6" or section.ip_version == "dual" then families[#families + 1] = "ipv6" end

            for _, family in ipairs(families) do
                local path = history_dir .. "/" .. history_section_name(section.domain) .. "." .. family .. ".tsv"
                local events = read_history_events(path, family, now)
                for index, event in ipairs(events) do
                    local next_event = events[index + 1]
                    local end_time = next_event and next_event.timestamp or now
                    if end_time > cutoff and event.timestamp <= now then
                        rows[#rows + 1] = {
                            section=section.name,
                            domain=section.domain,
                            family=family,
                            ip=event.ip,
                            start_time=event.timestamp,
                            end_time=end_time,
                            duration=math.max(0, end_time - event.timestamp),
                            active=(next_event == nil)
                        }
                    end
                end
            end
        end
    end

    table.sort(rows, function(a, b)
        if a.start_time == b.start_time then return a.domain < b.domain end
        return a.start_time > b.start_time
    end)

    luci.http.prepare_content("application/json")
    luci.http.write_json({
        success=true,
        generated_at=now,
        window_start=cutoff,
        window_seconds=86400,
        sections=sections,
        records=rows
    })
end

function action_proxy_access()
    local sys = require "luci.sys"
    local limit = tonumber(luci.http.formvalue("limit") or "5") or 5
    if limit ~= 20 and limit ~= 50 then
        limit = 5
    end
    -- 读取最近 500 条日志，按 IP 聚合
    local raw = sys.exec("tail -n 500 /var/log/minigate-access.log 2>/dev/null") or ""
    local visitors = {}  -- ip -> {last_time, domain, count, first_time}
    local order = {}     -- 保持顺序

    for line in raw:gmatch("[^\n]+") do
        local time   = line:match('"time":"([^"]*)"')
        local domain = line:match('"domain":"([^"]*)"')
        local client = line:match('"client":"([^"]*)"')
        if time and client and client ~= "" then
            if not visitors[client] then
                visitors[client] = { last_time = time, first_time = time, domain = domain or "", count = 1 }
                order[#order + 1] = client
            else
                visitors[client].last_time = time
                visitors[client].count = visitors[client].count + 1
                if domain and domain ~= "" then
                    visitors[client].domain = domain
                end
            end
        end
    end

    -- 按最后访问时间倒序
    table.sort(order, function(a, b)
        return visitors[a].last_time > visitors[b].last_time
    end)

    -- 按前端选择取前 N 个，默认 5 个
    local result = {}
    local now = os.time()
    for i = 1, math.min(#order, limit) do
        local ip = order[i]
        local v = visitors[ip]
        -- 解析 ISO 时间判断是否在线（5分钟内）
        local online = false
        local y,mo,da,h,mi,se = v.last_time:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
        if y then
            local ts = os.time({year=tonumber(y),month=tonumber(mo),day=tonumber(da),hour=tonumber(h),min=tonumber(mi),sec=tonumber(se)})
            online = (now - ts) < 300
        end
        result[#result + 1] = {
            ip = ip,
            last_time = v.last_time,
            domain = v.domain,
            count = v.count,
            online = online
        }
    end

    luci.http.prepare_content("application/json")
    luci.http.write_json({ visitors = result })
end

function action_geo_lookup()
    local sys = require "luci.sys"
    local fs = require "nixio.fs"
    local ip = luci.http.formvalue("ip") or ""
    -- 安全校验：只允许 IP 地址字符
    if not ip:match("^[%d%.%:a-fA-F]+$") then
        luci.http.prepare_content("application/json")
        luci.http.write_json({ ip = ip, geo = "无效IP" })
        return
    end

    local cache_dir = "/tmp/minigate-geo-cache"
    local cache_file = cache_dir .. "/" .. ip:gsub("[^%w%.%-_:]", "_")
    fs.mkdirr(cache_dir)
    local cached = fs.readfile(cache_file)
    if cached and cached ~= "" then
        luci.http.prepare_content("application/json")
        luci.http.write_json({ ip = ip, geo = cached:gsub("%s+$", "") })
        return
    end

    local geo = nil

    -- API 1: ip9.com.cn（UTF-8，国内快）
    if not geo then
        local raw = sys.exec("curl -s --connect-timeout 1 --max-time 2 'https://ip9.com.cn/get?ip=" .. ip .. "' 2>/dev/null")
        if raw and raw ~= "" then
            local country = raw:match('"country":"([^"]*)"') or ""
            local prov = raw:match('"prov":"([^"]*)"') or ""
            local city = raw:match('"city":"([^"]*)"') or ""
            local isp = raw:match('"isp":"([^"]*)"') or ""
            local loc = (country .. prov .. city):gsub("中国", "")
            if isp ~= "" then loc = loc .. " " .. isp end
            loc = loc:gsub("^%s+", ""):gsub("%s+$", "")
            if loc ~= "" then geo = loc end
        end
    end

    -- API 2: ip-api.com（UTF-8，国外覆盖好）
    if not geo then
        local raw = sys.exec("curl -s --connect-timeout 1 --max-time 2 'http://ip-api.com/json/" .. ip .. "?lang=zh-CN&fields=status,country,regionName,city,isp' 2>/dev/null")
        if raw and raw ~= "" then
            local status = raw:match('"status":"([^"]*)"')
            if status == "success" then
                local country = raw:match('"country":"([^"]*)"') or ""
                local region = raw:match('"regionName":"([^"]*)"') or ""
                local city = raw:match('"city":"([^"]*)"') or ""
                local isp = raw:match('"isp":"([^"]*)"') or ""
                local loc = (country .. region .. city):gsub("中国", "")
                if isp ~= "" then loc = loc .. " " .. isp end
                loc = loc:gsub("^%s+", ""):gsub("%s+$", "")
                if loc ~= "" then geo = loc end
            end
        end
    end

    -- API 3: pconline（GBK 需转码）
    if not geo then
        local raw = sys.exec("curl -s --connect-timeout 1 --max-time 2 'https://whois.pconline.com.cn/ipJson.jsp?ip=" .. ip .. "&json=true' 2>/dev/null | iconv -f gbk -t utf-8 2>/dev/null")
        if raw and raw ~= "" then
            local addr = raw:match('"addr":"([^"]*)"')
            if addr and addr ~= "" then geo = addr:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "") end
        end
    end

    fs.writefile(cache_file, geo or "未知")
    luci.http.prepare_content("application/json")
    luci.http.write_json({ ip = ip, geo = geo or "未知" })
end

-- ============== 登录防护 API ==============

function action_lg_status()
    local sys = require "luci.sys"
    local fs = require "nixio.fs"
    local uci = require "luci.model.uci".cursor()

    local watch_limit = tonumber(luci.http.formvalue("watch_limit") or "5") or 5
    if watch_limit ~= 20 and watch_limit ~= 30 then
        watch_limit = 5
    end
    local ban_limit = tonumber(luci.http.formvalue("ban_limit") or "5") or 5
    if ban_limit ~= 20 and ban_limit ~= 30 then
        ban_limit = 5
    end

    local enabled = uci:get("minigate","login_guard","enabled") or "0"
    local threshold = tonumber(uci:get("minigate","login_guard","threshold")) or 3
    local bantime = tonumber(uci:get("minigate","login_guard","bantime")) or 43200
    local window_s = tonumber(uci:get("minigate","login_guard","window")) or 600

    -- 服务是否在跑
    local pid_out = sys.exec("pgrep -f '/usr/lib/minigate/login_guard.sh run' 2>/dev/null")
    local running = (pid_out ~= nil and pid_out:match("%d") ~= nil)

    -- 已封禁列表（解析 nft -j 输出）
    -- 注意：nft -j 在 key 和 value 之间有空格，要用 %s* 匹配
    -- 每个 elem 内 val 在前 expires 在后，分别提取后按序号配对（避免跨 elem 匹配错乱）
    local banned = {}
    local raw = sys.exec("nft -j list set inet fw4 login_banned_v4 2>/dev/null") or ""
    local ips = {}
    for v in raw:gmatch('"val"%s*:%s*"([0-9%.]+)"') do
        ips[#ips+1] = v
    end
    local exps = {}
    for e in raw:gmatch('"expires"%s*:%s*(%d+)') do
        exps[#exps+1] = tonumber(e)
    end
    for i = 1, #ips do
        if exps[i] then
            banned[#banned+1] = { ip = ips[i], remaining = exps[i] }
        end
    end
    -- 按剩余时间倒序
    table.sort(banned, function(a,b) return a.remaining > b.remaining end)
    local banned_total = #banned
    local banned_limited = {}
    for i = 1, math.min(banned_total, ban_limit) do
        banned_limited[#banned_limited + 1] = banned[i]
    end

    -- 失败计数中（读 /var/run/minigate/login-guard/counters/）
    local watching = {}
    local counter_dir = "/var/run/minigate/login-guard/counters"
    local now = os.time()
    local list_out = sys.exec("ls " .. counter_dir .. " 2>/dev/null") or ""
    for ip in list_out:gmatch("[^\n]+") do
        local path = counter_dir .. "/" .. ip
        local fh = io.open(path, "r")
        if fh then
            local line = fh:read("*l") or ""
            fh:close()
            local first, count = line:match("(%d+)%s+(%d+)")
            if first and count then
                local first_time = tonumber(first)
                local stat = fs.stat(path)
                local last_time = (stat and stat.mtime) or first_time
                local age = now - first_time
                if age <= window_s then
                watching[#watching+1] = {
                    ip = ip,
                    count = tonumber(count),
                    age = age,
                    first_time = first_time,
                    last_time = last_time,
                    last_seen = os.date("%Y-%m-%d %H:%M:%S", last_time)
                }
                end
            end
        end
    end
    table.sort(watching, function(a,b)
        return (a.last_time or 0) > (b.last_time or 0)
    end)
    local watching_total = #watching
    local watching_limited = {}
    for i = 1, math.min(watching_total, watch_limit) do
        watching_limited[#watching_limited + 1] = watching[i]
    end

    luci.http.prepare_content("application/json")
    luci.http.write_json({
        enabled = enabled,
        running = running,
        threshold = threshold,
        bantime = bantime,
        window = window_s,
        banned = banned_limited,
        banned_total = banned_total,
        ban_limit = ban_limit,
        watching = watching_limited,
        watching_total = watching_total,
        watch_limit = watch_limit
    })
end

function action_lg_ban()
    local sys = require "luci.sys"
    local ip = luci.http.formvalue("ip") or ""
    if not ip:match("^%d+%.%d+%.%d+%.%d+$") then
        luci.http.prepare_content("application/json")
        luci.http.write_json({success=false, error="无效 IP"})
        return
    end
    local rc = sys.call("/bin/sh /usr/lib/minigate/login_guard.sh ban '" .. ip .. "' >/dev/null 2>&1")
    luci.http.prepare_content("application/json")
    luci.http.write_json({success = (rc == 0), ip = ip})
end

function action_lg_unban()
    local sys = require "luci.sys"
    local ip = luci.http.formvalue("ip") or ""
    if not ip:match("^%d+%.%d+%.%d+%.%d+$") then
        luci.http.prepare_content("application/json")
        luci.http.write_json({success=false, error="无效 IP"})
        return
    end
    local rc = sys.call("/bin/sh /usr/lib/minigate/login_guard.sh unban '" .. ip .. "' >/dev/null 2>&1")
    luci.http.prepare_content("application/json")
    luci.http.write_json({success = (rc == 0), ip = ip})
end

function action_lg_flush()
    local sys = require "luci.sys"
    local rc = sys.call("/bin/sh /usr/lib/minigate/login_guard.sh flush >/dev/null 2>&1")
    luci.http.prepare_content("application/json")
    luci.http.write_json({success = (rc == 0)})
end
