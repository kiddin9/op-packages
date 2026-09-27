module("luci.controller.caddy", package.seeall)

local DL_DEFAULT = "https://github.com/andangel/luci-app-caddy/releases/latest/download/caddy_linux_arm64"
local DL_API     = "https://api.github.com/repos/andangel/luci-app-caddy/releases/latest"

function index()
	entry({"admin", "network", "caddy"}, alias("admin", "network", "caddy", "basic"), _("Caddy"), 30)
	entry({"admin", "network", "caddy", "basic"}, cbi("caddy/caddy"), _("状态"), 1).leaf = true
	entry({"admin", "network", "caddy", "domain"}, cbi("caddy/domain"), _("域名"), 2).leaf = true
	entry({"admin", "network", "caddy", "host"}, cbi("caddy/host"), _("主机"), 3).leaf = true
	entry({"admin", "network", "caddy", "caddyfile"}, cbi("caddy/caddyfile"), _("配置"), 4).leaf = true
	entry({"admin", "network", "caddy", "log"}, cbi("caddy/caddy_log"), _("日志"), 5).leaf = true
	entry({"admin", "network", "caddy", "caddy_status"}, call("caddy_status")).leaf = true
	entry({"admin", "network", "caddy", "get_log"}, call("get_log")).leaf = true
	entry({"admin", "network", "caddy", "clear_log"}, call("clear_log")).leaf = true
	entry({"admin", "network", "caddy", "admin_info"}, call("admin_info")).leaf = true
	entry({"admin", "network", "caddy", "download"}, call("download")).leaf = true
	entry({"admin", "network", "caddy", "download_status"}, call("download_status")).leaf = true
	entry({"admin", "network", "caddy", "download_ctl"}, call("download_ctl")).leaf = true
end

function caddy_status()
	local e={}
	local uci  = require "luci.model.uci".cursor()
	-- Web 界面按钮地址: 取第一个 proxy host 的 域名:端口, 没有则留空
	local weburl = ""
	local pname = uci:get_first("caddy", "proxy")
	if pname then
		local pdom = uci:get("caddy", pname, "domain")
		local pprt = uci:get("caddy", pname, "port")
		if pdom then
			weburl = "http://" .. pdom .. (pprt and (":" .. pprt) or "")
		end
	end
	e.weburl = weburl
		    e.running=luci.sys.call("pidof caddy >/dev/null")==0
	local tagfile = io.open("/tmp/caddy_time", "r")
        if tagfile then
	local tagcontent = tagfile:read("*all")
	tagfile:close()
	if tagcontent and tagcontent ~= "" then
        os.execute("start_time=$(cat /tmp/caddy_time) && time=$(($(date +%s)-start_time)) && day=$((time/86400)) && [ $day -eq 0 ] && day='' || day=${day}天 && time=$(date -u -d @${time} +'%H小时%M分%S秒') && echo $day $time > /tmp/command_caddy 2>&1")
        local command_output_file = io.open("/tmp/command_caddy", "r")
        if command_output_file then
            e.caddysta = command_output_file:read("*all")
            command_output_file:close()
	    if e.caddysta == "" then
               e.caddysta = "unknown"
            end
        end
	end
	end

         local command2 = io.popen('test ! -z "`pidof caddy`" && (top -b -n1 | grep -E "$(pidof caddy)" 2>/dev/null | grep -v grep | awk \'{for (i=1;i<=NF;i++) {if ($i ~ /caddy/) break; else cpu=i}} END {print $cpu}\')')
                   e.caddycpu = command2:read("*all")
                   command2:close()
                   if e.caddycpu == "" then
                   e.caddycpu = "unknown"
                   end
  
         local command3 = io.popen("test ! -z `pidof caddy` && (cat /proc/$(pidof caddy | awk '{print $NF}')/status | grep -w VmRSS | awk '{printf \"%.2f MB\", $2/1024}')")
                   e.caddyram = command3:read("*all")
                   command3:close()
                   if e.caddyram == "" then
                   e.caddyram = "unknown"
                   end
  
-- 官方 CLI: caddy version (输出形如 v2.11.4 h1:xxx, 取版本号段)
         local command4 = io.popen("$(uci -q get caddy.@caddy[0].bin_dir) version 2>/dev/null | awk '{print $1}'")
                   e.caddytag = command4:read("*all")
                   command4:close()
                   if e.caddytag == "" then
                   e.caddytag = "unknown"
                   end
  
         local command5 = io.popen("([ -s /tmp/caddynew.tag ] && cat /tmp/caddynew.tag ) || ( curl -L -k -s --connect-timeout 3 --user-agent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36' https://api.github.com/repos/caddyserver/caddy/releases/latest | grep tag_name | sed 's/[^0-9.]*//g' >/tmp/caddynew.tag && cat /tmp/caddynew.tag )")
                   e.caddynewtag = command5:read("*all")
                   command5:close()
                   if e.caddynewtag == "" then
                   e.caddynewtag = "unknown"
                   end
	luci.http.prepare_content("application/json")
	luci.http.write_json(e)
end

function get_log()
	luci.http.write(luci.sys.exec("[ -s $(uci -q get caddy.@caddy[0].log_dir) ] && cat $(uci -q get caddy.@caddy[0].log_dir)"))
end

function clear_log()
	luci.sys.call("cat /dev/null > $(uci -q get caddy.@caddy[0].log_dir)")
end

function admin_info()
	-- HOME=/root 兜底: LuCI CGI (uhttpd) 环境没 $HOME/$XDG_CONFIG_HOME,
	-- caddy validate 会 warn "unable to determine directory for user configuration; falling back to current directory".
	-- 显式给个家目录就没这条 warn; --config 已显式传, 结果不受 HOME 影响.
	local validate = luci.sys.exec("env HOME=/root $(uci -q get caddy.@caddy[0].bin_dir) validate --config /etc/caddy/Caddyfile --adapter caddyfile 2>&1")
	luci.http.prepare_content("application/json")
	luci.http.write_json({ validate = validate })
end

function download_status()
	local st = { state = "idle", size = 0, total = 0, speed = 0, msg = "" }
	local f = io.open("/tmp/caddy_dl.status", "r")
	if f then
		for line in f:lines() do
			local k, v = line:match("^([%a_]+)=(.*)$")
			if k then st[k] = v end
		end
		f:close()
	end
	st.size  = tonumber(st.size) or 0
	st.total = tonumber(st.total) or 0
	st.speed = tonumber(st.speed) or 0
	-- 看门狗: 活动状态下 status 由下载进程每秒刷新一次并带 ts 时间戳 (该 lua 桥无 os.stat, 不靠文件 mtime),
	-- 若 >60s 没刷新说明进程已丢失 (被 OOM/清理 SIGKILL 不执行 trap), 状态文件残留会导致 UI 永远下载中
	local actives = { downloading = 1, paused = 1, verifying = 1 }
	local ts = tonumber(st.ts) or 0
	if actives[st.state] and ts > 0 and os.time() - ts > 60 then
		st.state = "lost"
		st.speed = 0
		st.msg = (st.size > 0) and "下载进程已丢失 (保留进度, 点[下载并重启]续传)" or "状态异常 (点[下载并重启]重新开始)"
	end
	luci.http.prepare_content("application/json")
	luci.http.write_json(st)
end

-- 暂停/继续/停止: 写一个控制命令到 /tmp/caddy_dl.ctl, 下载进程每秒轮询处理.
-- 暂停=SIGSTOP 冻结 curl (连接仍挂着, 不额外撞 GitHub); 继续=SIGCONT; 停止=杀 curl 留已下部分.
function download_ctl()
	-- 本 runtime (Luci openwrt-25.12 / ucode 桥) 的 luci.http 不提供 readrequest, 用 formvalue 读 POST 字段
	local act  = tostring(luci.http.formvalue("act") or "")
	local ok, msg = false, ""
	if act == "pause" or act == "resume" or act == "stop" then
		local f = io.open("/tmp/caddy_dl.ctl", "w")
		if f then f:write(act .. "\n"); f:close(); ok = true; msg = "ok" end
	else
		msg = "unknown act: " .. act
	end
	luci.http.prepare_content("application/json")
	luci.http.write_json({ ok = ok, msg = msg })
end

function download()
	local uci = require "luci.model.uci".cursor()
	local bin = uci:get("caddy", "caddy", "bin_dir") or "/usr/sbin/caddy"
	local u   = uci:get("caddy", "caddy", "download_url")
	local url = (u and u ~= "") and u or DL_DEFAULT
	local use_sha = (url == DL_DEFAULT) and "1" or "0"

	local sq = function(s) return s:gsub("'", "'\\''") end
	local L = {
		"#!/bin/sh",
		"URL='" .. sq(url) .. "'",
		"TMP='/tmp/caddy.dl'",
		"STATUS='/tmp/caddy_dl.status'",
		"CTL='/tmp/caddy_dl.ctl'",
		"BIN='" .. sq(bin) .. "'",
		"USE_SHA=" .. use_sha,
		"API='" .. DL_API .. "'",
		"RECEIPT='/tmp/caddy_dl.done'",
		"CURLPID=0; PAUSED=0; STOPTED=0",
		"rm -f \"$CTL\"",
		"",
		"# 写临时文件再原子 mv, 防状态端点读到半截文件而把 UI 误渲染成 idle",
		"ws(){ printf 'state=%s\\nsize=%s\\ntotal=%s\\nspeed=%s\\nmsg=%s\\nts=%s\\n' \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" $(date +%s) > \"$STATUS.tmp\"; mv -f \"$STATUS.tmp\" \"$STATUS\"; }",
		"",
		"PIDFILE='/tmp/caddy_dl.pid'",
		"# 去重锁: 已有存活实例则直接退出 (防清理漏杀导致多实例竞争写同一文件 / 互相覆盖 status)",
		"if [ -f \"$PIDFILE\" ]; then OLD=$(cat \"$PIDFILE\" 2>/dev/null); if [ -n \"$OLD\" ] && kill -0 \"$OLD\" 2>/dev/null; then exit 0; fi; fi",
		"echo $$ > \"$PIDFILE\"",
		"trap 'rm -f \"$PIDFILE\"' EXIT",
		"",
		"# 取总大小: 发 Range bytes=0-0 只下 1 字节, 从 Content-Range: bytes 0-0/TOTAL 抽分母 (比完整 HEAD 稳); GitHub 抖则重试 3 次",
		"TOT=0",
		"i=0",
		'while [ "$i" -lt 3 ]; do',
		"TOT=$(curl -s -L -r 0-0 --connect-timeout 10 -D - -o /dev/null \"$URL\" 2>/dev/null | tr -d '\\r' | grep -i 'Content-Range:' | grep -oE '[0-9]+/[0-9]+' | awk -F/ '{print $2}' | head -1)",
		"if [ -n \"$TOT\" ] && [ \"$TOT\" -gt 0 ] 2>/dev/null; then break; fi",
		"i=$((i+1)); sleep 2",
		"done",
		"ws downloading $(wc -c < \"$TMP\" 2>/dev/null || echo 0) \"$TOT\" 0 \"\"",
		"",
		"# 已下载收据: 上次下载且 SHA 通过时, 记下当时的期望 sha (写入在成功替换后). 收据在 /tmp, 重启即清空 → 重启后再点会重新下载(拉到新版).",
		"# 本次点击若 API 最新 sha == 收据 == 当前二进制 sha, 说明盘上的就是刚下载的版本 → 不重复下载, 直接重启",
		"SKIP=0",
		"BINSIZE=$(wc -c < \"$BIN\" 2>/dev/null || echo 0)",
		"if [ \"$USE_SHA\" -eq 1 ] && [ -f \"$RECEIPT\" ]; then",
		"ws verifying \"$BINSIZE\" \"$BINSIZE\" 0 '核对已下载版本...'",
		"API_NOW=$(curl -L -sS --connect-timeout 10 --max-time 20 \"$API\" | grep -oE 'sha256:[0-9a-f]{64}' | head -1 | sed 's/sha256://')",
		"BIN_SHA=$(sha256sum \"$BIN\" 2>/dev/null | awk '{print $1}')",
		"if [ \"${#API_NOW}\" -ge 64 ] && [ \"${#BIN_SHA}\" -ge 64 ] && [ \"$(cat \"$RECEIPT\" 2>/dev/null)\" = \"$API_NOW\" ] && [ \"$BIN_SHA\" = \"$API_NOW\" ]; then SKIP=1; fi",
		"fi",
		"if [ $SKIP -eq 1 ]; then /etc/init.d/caddy restart >/dev/null 2>&1; ws done \"$BINSIZE\" \"$BINSIZE\" 0 '已是上次下载的最新版, 无需重复下载, 已直接重启 Caddy'; exit 0; fi",
		"",
		"# 直接后台运行 curl (不经函数包一层), 使 $! 即真实 curl pid, 暂停/停止(信号)才能直接作用于 curl",
		"# GitHub 直连不稳: 除网络类错误外, HTTP/2 reset / -C 续传冲突等瞬时错误也按 --retry 自动再来",
		"# speed-limit/speed-time: 低于 ~100B/s 持续 45s 视为假死, 触发重试 (比干等 5 分钟超时快)",
		"curl -L -C - -sS --retry 4 --retry-delay 8 --retry-all-errors --connect-timeout 20 --speed-limit 100 --speed-time 45 -o \"$TMP\" \"$URL\" >> /tmp/caddy_dl.log 2>&1 &",
		"CURLPID=$!; RC=",
		"LAST=$(wc -c < \"$TMP\" 2>/dev/null || echo 0); LTIME=$(date +%s)",
		"# 主循环: 每秒刷新进度 + 处理暂停/继续/停止控制命令 (与下载解耦, 控制端点只写 $CTL 文件)",
		'while kill -0 "$CURLPID" 2>/dev/null; do',
		'if [ -f "$CTL" ]; then',
		'  CMD=$(cat "$CTL" 2>/dev/null); rm -f "$CTL"',
		'  if [ "$CMD" = "pause" ] && [ $PAUSED -eq 0 ]; then kill -STOP $CURLPID 2>/dev/null; PAUSED=1',
		'  elif [ "$CMD" = "resume" ] && [ $PAUSED -eq 1 ]; then kill -CONT $CURLPID 2>/dev/null; PAUSED=0',
		'  elif [ "$CMD" = "stop" ]; then kill $CURLPID 2>/dev/null; STOPTED=1',
		'  fi',
		'fi',
		'if [ $PAUSED -eq 1 ]; then ws paused $(wc -c < "$TMP" 2>/dev/null || echo 0) "$TOT" 0 ""; sleep 1; continue; fi',
		'SZ=$(wc -c < "$TMP" 2>/dev/null || echo 0)',
		'NOW=$(date +%s); DT=$((NOW - LTIME)); SP=0',
		'if [ "$DT" -gt 0 ]; then SP=$(( (SZ - LAST) / DT )); fi',
		'LAST=$SZ; LTIME=$NOW',
		'ws downloading "$SZ" "$TOT" "$SP" ""',
		"# 僵尸检测: curl 死掉但未 wait 收尸时 kill -0 仍成功会卡死主循环, /proc 状态 Z 即已死; 已下满按成功, 否则按失败",
		'CS=$(awk "{print $3}" /proc/$CURLPID/stat 2>/dev/null)',
		'if [ "$CS" = "Z" ]; then if [ "$TOT" -gt 0 ] 2>/dev/null && [ "$SZ" -ge "$TOT" ] 2>/dev/null; then RC=0; else RC=128; fi; break; fi',
		"sleep 1",
		"done",
		"# 主循环已判定 (z 检测设了 RC) 则不覆盖; 否则 wait 收尸取真实退出码",
		'if [ -z "$RC" ]; then wait $CURLPID 2>/dev/null; RC=$?; fi',
		'SZ=$(wc -c < "$TMP" 2>/dev/null || echo 0)',
		"if [ $STOPTED -eq 1 ]; then ws stopped \"$SZ\" \"$TOT\" 0 '已停止 (保留已下载部分, 点[下载并重启]可续传)'; exit 0; fi",
		"if [ \"$RC\" -ne 0 ]; then ws error \"$SZ\" \"$TOT\" 0 '下载失败 (GitHub 波动/网络), 点[下载并重启]可自动续传重试'; exit 0; fi",
		"if [ \"$USE_SHA\" -eq 1 ]; then",
		"API_SHA=$(curl -L -sS --connect-timeout 10 --max-time 20 \"$API\" | grep -oE 'sha256:[0-9a-f]{64}' | head -1 | sed 's/sha256://')",
		"LOC_SHA=$(sha256sum \"$TMP\" 2>/dev/null | awk '{print $1}')",
		'if [ "${#API_SHA}" -ge 64 ] && [ "${#LOC_SHA}" -ge 64 ] && [ "$API_SHA" != "$LOC_SHA" ]; then',
		'rm -f "$TMP"; ws error "$SZ" "$TOT" 0 "SHA256 不匹配, 文件可能损坏, 已丢弃, 请重试"; exit 0',
		"fi",
		"fi",
		"# curl -o 落盘不带可执行位, -h 前先 chmod, 否则任何架构 (包括正确 arm64) 都会 Permission denied",
		"chmod +x \"$TMP\" 2>/dev/null",
		"if ! \"$TMP\" -h >/dev/null 2>&1; then rm -f \"$TMP\"; ws error \"$SZ\" \"$TOT\" 0 '文件无法执行, 可能架构不匹配 (应为 linux/arm64 静态二进制)'; exit 0; fi",
		"if ! mv -f \"$TMP\" \"$BIN\"; then ws error \"$SZ\" \"$TOT\" 0 '替换 $BIN 失败'; exit 0; fi",
		"# 写收据: 本版本已在盘上, 下次点击命中 SKIP 不再重复下载 (仅默认 URL 有 API_SHA)",
		"[ \"$USE_SHA\" -eq 1 ] && echo \"$API_SHA\" > \"$RECEIPT\" 2>/dev/null",
		"if /etc/init.d/caddy restart >/dev/null 2>&1; then ws done \"$SZ\" \"$TOT\" 0 '下载完成, 已替换并重启 Caddy'; else ws done \"$SZ\" \"$TOT\" 0 '下载完成并已替换, 但重启 Caddy 失败, 请手动 /etc/init.d/caddy restart'; fi",
	}
	local f = io.open("/tmp/caddy_dl.sh", "w")
	f:write(table.concat(L, "\n") .. "\n")
	f:close()
	os.execute("chmod +x /tmp/caddy_dl.sh")
	-- 先清掉旧的下载进程 (脚本本体 + 它遗留的写 caddy.dl 的 curl 子进程, 否则多实例互相覆盖 status)
	-- ps 会截断命令行导致漏杀 curl, 故直接扫 /proc/*/cmdline; 用 [.] 自转义 glob 避免匹配到本命令自身
	os.execute("for p in /proc/[0-9]*; do c=$(tr '\\0' ' ' < $p/cmdline 2>/dev/null); case \"$c\" in *caddy_dl[.]sh*|*caddy[.]dl*) kill ${p##*/} 2>/dev/null;; esac; done; sleep 1; rm -f /tmp/caddy_dl.status")
	-- nohup 脱离 CGI, 页面刷新也不中断
	os.execute("nohup sh /tmp/caddy_dl.sh >/dev/null 2>&1 &")
	luci.http.prepare_content("application/json")
	-- 注意: call 端点内 _ 未注入 (只在 index 阶段有), 这里用字面量; 该消息仅作启动占位, 随即被进度轮询覆盖
	luci.http.write_json({ ok = true, msg = "已开始后台下载 (支持断点续传), 自动刷新进度..." })
end

