module("luci.controller.minigate", package.seeall)

function index()
    entry({"admin","services","minigate"}, alias("admin","services","minigate","general"), "MiniGate", 60).dependent=false
    entry({"admin","services","minigate","general"}, cbi("minigate/general"), "总览", 10)
    entry({"admin","services","minigate","ddns"}, cbi("minigate/ddns"), "动态DNS", 20)
    entry({"admin","services","minigate","acme"}, cbi("minigate/acme"), "SSL 证书", 30)
    entry({"admin","services","minigate","proxy"}, cbi("minigate/proxy"), "反向代理", 40)
    entry({"admin","services","minigate","log"}, template("minigate/log"), "日志", 50)
    entry({"admin","services","minigate","status"}, call("action_status")).leaf=true
    entry({"admin","services","minigate","get_log"}, call("action_get_log")).leaf=true
    entry({"admin","services","minigate","acme_install"}, call("action_acme_install")).leaf=true
    entry({"admin","services","minigate","acme_issue"}, call("action_acme_issue")).leaf=true
    entry({"admin","services","minigate","ddns_sync"}, call("action_ddns_sync")).leaf=true
    entry({"admin","services","minigate","proxy_access"}, call("action_proxy_access")).leaf=true
    entry({"admin","services","minigate","geo_lookup"}, call("action_geo_lookup")).leaf=true
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
            cert_expiry=uci:get("minigate","acme","cert_expiry")or""
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
    local cmd="/bin/sh /usr/lib/minigate/acme.sh issue"; if d~=""then cmd=cmd.." '"..d.."'"end
    sys.call(cmd.." 2>&1")
    local uci=require"luci.model.uci".cursor(); local st=uci:get("minigate","acme","status")or"unknown"
    luci.http.prepare_content("application/json"); luci.http.write_json({success=(st=="ok"),message=(st=="ok")and"签发成功！"or"签发失败，查看日志"})
end

function action_ddns_sync()
    local sys=require"luci.sys"; local sec=luci.http.formvalue("section")or""
    if sec~=""then sys.call("/bin/sh /usr/lib/minigate/ddns.sh single '"..sec.."' 2>&1")
    else sys.call("/bin/sh /usr/lib/minigate/ddns.sh force 2>&1") end
    local uci=require"luci.model.uci".cursor()
    local st=sec~=""and(uci:get("minigate",sec,"status")or"unknown")or"done"
    local ip=sec~=""and(uci:get("minigate",sec,"last_ip")or"")or""
    local ip6=sec~=""and(uci:get("minigate",sec,"last_ip6")or"")or""
    luci.http.prepare_content("application/json"); luci.http.write_json({success=(st=="ok"or st=="partial"),status=st,ip=ip,ip6=ip6})
end

function action_proxy_access()
    local sys = require "luci.sys"
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

    -- 取前 30 个
    local result = {}
    local now = os.time()
    for i = 1, math.min(#order, 30) do
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
    local ip = luci.http.formvalue("ip") or ""
    -- 安全校验：只允许 IP 地址字符
    if not ip:match("^[%d%.%:a-fA-F]+$") then
        luci.http.prepare_content("application/json")
        luci.http.write_json({ ip = ip, geo = "无效IP" })
        return
    end

    local geo = nil

    -- API 1: ip9.com.cn（UTF-8，国内快）
    if not geo then
        local raw = sys.exec("curl -s --connect-timeout 3 --max-time 5 'https://ip9.com.cn/get?ip=" .. ip .. "' 2>/dev/null")
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
        local raw = sys.exec("curl -s --connect-timeout 3 --max-time 5 'http://ip-api.com/json/" .. ip .. "?lang=zh-CN&fields=status,country,regionName,city,isp' 2>/dev/null")
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
        local raw = sys.exec("curl -s --connect-timeout 3 --max-time 5 'https://whois.pconline.com.cn/ipJson.jsp?ip=" .. ip .. "&json=true' 2>/dev/null | iconv -f gbk -t utf-8 2>/dev/null")
        if raw and raw ~= "" then
            local addr = raw:match('"addr":"([^"]*)"')
            if addr and addr ~= "" then geo = addr:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "") end
        end
    end

    luci.http.prepare_content("application/json")
    luci.http.write_json({ ip = ip, geo = geo or "未知" })
end
