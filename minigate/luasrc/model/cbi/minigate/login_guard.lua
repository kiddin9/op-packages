local m, s, o
local sys = require "luci.sys"
local fs = require "nixio.fs"

m = Map("minigate", "登录防护 (Login Guard)",
    "监控 SSH（dropbear）和 LuCI 网页登录失败，达到阈值自动封禁源 IP。" ..
    "适用于 SSH 端口被映射到公网、防爆破。LAN 私有 IP 自动豁免。")

m.on_after_commit = function(self)
    sys.call("/etc/init.d/minigate reload >/dev/null 2>&1 &")
end

-- ============== 实时状态 ==============
s = m:section(NamedSection, "login_guard", "login_guard", "实时状态")
s.anonymous = true

local lu = luci.dispatcher.build_url("admin/services/minigate/lg_status")
local uu = luci.dispatcher.build_url("admin/services/minigate/lg_unban")
local bu = luci.dispatcher.build_url("admin/services/minigate/lg_ban")
local fu = luci.dispatcher.build_url("admin/services/minigate/lg_flush")
local gu = luci.dispatcher.build_url("admin/services/minigate/geo_lookup")

o = s:option(DummyValue, "_dash")
o.rawhtml = true
o.cfgvalue = function()
    local function esc(v)
        v = tostring(v or "")
        v = v:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
        v = v:gsub('"', "&quot;"):gsub("'", "&#39;")
        return v
    end

    local function fmt_duration(s)
        s = tonumber(s) or 0
        if s >= 3600 then
            return string.format("%dh%dm", math.floor(s / 3600), math.floor((s % 3600) / 60))
        elseif s >= 60 then
            return string.format("%dm%ds", math.floor(s / 60), s % 60)
        end
        return tostring(s) .. "s"
    end

    local threshold = tonumber(m.uci:get("minigate", "login_guard", "threshold")) or 3
    local now = os.time()
    local watching_rows = {}
    local watching_items = {}
    local counter_dir = "/var/run/minigate/login-guard/counters"
    local list_out = sys.exec("ls " .. counter_dir .. " 2>/dev/null") or ""
    for ip in list_out:gmatch("[^\n]+") do
        local path = counter_dir .. "/" .. ip
        local fh = io.open(path, "r")
        if fh then
            local line = fh:read("*l") or ""
            fh:close()
            local first, count = line:match("^(%d+)%s+(%d+)")
            if first and count then
                local stat = fs.stat(path)
                local last_time = (stat and stat.mtime) or tonumber(first)
                watching_items[#watching_items + 1] = {
                    ip = ip,
                    count = tonumber(count) or 0,
                    age = now - tonumber(first),
                    last_time = last_time,
                    last_seen = os.date("%Y-%m-%d %H:%M:%S", last_time)
                }
            end
        end
    end
    table.sort(watching_items, function(a,b)
        return (a.last_time or 0) > (b.last_time or 0)
    end)
    for i = 1, math.min(#watching_items, 30) do
        local item = watching_items[i]
        local style = (i > 5) and ' style="display:none"' or ''
        watching_rows[#watching_rows + 1] =
            '<tr class="lg-watch-row" data-ip="' .. esc(item.ip) .. '" data-index="' .. tostring(i) .. '"' .. style .. '><td><code class="lg-ip">' .. esc(item.ip) .. '</code></td>' ..
            '<td id="lg-watch-geo-initial-' .. tostring(i) .. '"><span style="color:var(--lg-muted)">查询中...</span></td>' ..
            '<td><span style="font-weight:bold">' .. esc(item.count) .. ' / ' .. esc(threshold) .. '</span></td>' ..
            '<td>' .. esc(item.last_seen) .. '</td>' ..
            '<td>' .. esc(fmt_duration(item.age)) .. '</td></tr>'
    end

    local initial_watching = '<div class="lg-empty">无</div>'
    if #watching_rows > 0 then
        initial_watching =
            '<table class="lg-table"><thead><tr><th>IP 地址</th><th>归属地</th><th>失败次数</th><th>最近访问时间</th><th>距首次失败</th></tr></thead><tbody>' ..
            table.concat(watching_rows, "") ..
            '</tbody></table>'
    end

    return [[
<style>
.lg-wrap{display:flex;flex-direction:column;gap:16px;--lg-success:#2f9e44;--lg-warning:#f08c00;--lg-danger:#e03131;--lg-muted:#6b7280;--lg-primary:#5b55c8;--lg-surface:#fff;--lg-surface-muted:#f6f8fb;--lg-surface-alt:#f8fafc;--lg-surface-hover:#eef4ff;--lg-control:#fff;--lg-text:#1f2937;--lg-text-muted:#5f6b7a;--lg-border:#d7dce3;--lg-border-soft:#e6eaf0;--lg-code-bg:#e8edf6;--lg-danger-bg:#fee2e2;--lg-danger-text:#991b1b;--lg-shadow:0 10px 24px rgba(15,23,42,.08)}
.lg-summary{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px}
.lg-card{position:relative;min-height:118px;border-radius:8px;padding:18px;background:var(--lg-surface);border:1px solid var(--lg-border);box-shadow:var(--lg-shadow);overflow:hidden}
.lg-card:before{content:"";position:absolute;left:0;top:0;bottom:0;width:4px;background:var(--accent,#777)}
.lg-card-title{font-size:12px;color:var(--lg-text-muted);margin-bottom:14px}
.lg-card-value{font-size:22px;font-weight:700;line-height:1.25}
.lg-panel{border-radius:8px;background:var(--lg-surface);border:1px solid var(--lg-border);box-shadow:var(--lg-shadow);overflow:hidden}
.lg-panel-head{display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap;padding:14px 16px;border-bottom:1px solid var(--lg-border)}
.lg-panel-title{font-size:13px;font-weight:700;color:var(--lg-text)}
.lg-tools{display:flex;align-items:center;gap:8px;flex-wrap:wrap}
.lg-input{height:30px;min-width:180px;border-radius:6px;border:1px solid var(--lg-border);background:var(--lg-control);color:var(--lg-text);padding:0 10px;font-size:12px;box-sizing:border-box}
.lg-select{height:30px;border-radius:6px;border:1px solid var(--lg-border);background:var(--lg-control);color:var(--lg-text);padding:0 8px;font-size:12px;box-sizing:border-box}
.lg-limit-label{display:flex;align-items:center;gap:6px;color:var(--lg-text-muted);font-size:12px;white-space:nowrap}
.lg-btn{height:30px;border:0;border-radius:6px;padding:0 12px;font-size:12px;color:#fff;cursor:pointer}
.lg-btn-primary{background:var(--lg-primary)}
.lg-btn-danger{background:var(--lg-danger)}
.lg-table-wrap{overflow-x:auto}
.lg-table{width:100%;border-collapse:collapse;min-width:720px}
.lg-table th{padding:10px 12px;color:var(--lg-text-muted);font-size:11px;font-weight:600;text-align:left;border-bottom:1px solid var(--lg-border);background:var(--lg-surface-muted)}
.lg-table td{padding:11px 12px;color:var(--lg-text);font-size:12px;border-bottom:1px solid var(--lg-border-soft);vertical-align:middle}
.lg-table tr:nth-child(even) td{background:var(--lg-surface-alt)}
.lg-table tr:hover td{background:var(--lg-surface-hover)}
.lg-ip{display:inline-block;border-radius:6px;background:var(--lg-code-bg);color:var(--lg-text);padding:2px 7px;font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace;font-size:12px}
.lg-ip-danger{background:var(--lg-danger-bg);color:var(--lg-danger-text)}
.lg-empty{padding:18px 16px;color:var(--lg-text-muted);font-size:12px}
.lg-unban{height:26px;border:1px solid var(--lg-border);border-radius:6px;background:var(--lg-control);color:var(--lg-text);padding:0 10px;font-size:11px;cursor:pointer}
:root[data-darkmode="true"] .lg-wrap{--lg-success:#78c98d;--lg-warning:#d7a64a;--lg-danger:#e58a84;--lg-muted:#9aa7b3;--lg-primary:#8e8add;--lg-surface:var(--background-color-medium,#171e26);--lg-surface-muted:var(--background-color-high,#131a22);--lg-surface-alt:var(--background-color-low,#19212a);--lg-surface-hover:#202a34;--lg-control:var(--background-color-high,#111820);--lg-text:var(--text-color-high,#d5dbe3);--lg-text-muted:var(--text-color-medium,#9aa7b3);--lg-border:var(--border-color-medium,rgba(148,163,184,.18));--lg-border-soft:var(--border-color-low,rgba(148,163,184,.12));--lg-code-bg:var(--background-color-low,#253142);--lg-danger-bg:#42303a;--lg-danger-text:#efb2b0;--lg-shadow:none}
@media(prefers-color-scheme:dark){
:root:not([data-darkmode]) .lg-wrap{--lg-success:#78c98d;--lg-warning:#d7a64a;--lg-danger:#e58a84;--lg-muted:#9aa7b3;--lg-primary:#8e8add;--lg-surface:#171e26;--lg-surface-muted:#131a22;--lg-surface-alt:#19212a;--lg-surface-hover:#202a34;--lg-control:#111820;--lg-text:#d5dbe3;--lg-text-muted:#9aa7b3;--lg-border:rgba(148,163,184,.18);--lg-border-soft:rgba(148,163,184,.12);--lg-code-bg:#253142;--lg-danger-bg:#42303a;--lg-danger-text:#efb2b0;--lg-shadow:none}
}
@media(max-width:900px){.lg-summary{grid-template-columns:1fr}.lg-card{min-height:auto}.lg-input{width:100%;min-width:0}.lg-tools{width:100%}}
</style>

<div class="lg-wrap">
<div id="lg-summary" class="lg-summary">
  <div class="lg-card" style="--accent:var(--lg-success)">
    <div class="lg-card-title">服务状态</div>
    <div id="lg-running" class="lg-card-value">--</div>
  </div>
  <div class="lg-card" style="--accent:var(--lg-danger)">
    <div class="lg-card-title">当前已封禁</div>
    <div id="lg-banned-count" class="lg-card-value" style="color:var(--lg-danger)">--</div>
  </div>
  <div class="lg-card" style="--accent:var(--lg-warning)">
    <div class="lg-card-title">失败计数中</div>
    <div id="lg-watching-count" class="lg-card-value" style="color:var(--lg-warning)">--</div>
  </div>
</div>

<div class="lg-panel">
  <div class="lg-panel-head">
    <div class="lg-panel-title">已封禁 IP 列表</div>
    <div class="lg-tools">
      <label class="lg-limit-label">显示
        <select id="lg-ban-limit" class="lg-select">
          <option value="5">5 条</option>
          <option value="20">20 条</option>
          <option value="30">30 条</option>
        </select>
      </label>
      <input id="lg-ban-input" class="lg-input" type="text" placeholder="输入 IP 手动封禁" />
      <button class="lg-btn lg-btn-primary" onclick="lgManualBan()">封禁</button>
      <button class="lg-btn lg-btn-danger" onclick="lgFlushAll()">清空全部</button>
    </div>
  </div>
  <div id="lg-banned-list" class="lg-table-wrap"><div class="lg-empty">加载中...</div></div>
</div>

<div class="lg-panel">
  <div class="lg-panel-head">
    <div class="lg-panel-title">失败计数中（未达阈值）</div>
    <div class="lg-tools">
      <label class="lg-limit-label">显示
        <select id="lg-watch-limit" class="lg-select">
          <option value="5">5 条</option>
          <option value="20">20 条</option>
          <option value="30">30 条</option>
        </select>
      </label>
    </div>
  </div>
  <div id="lg-watching-list" class="lg-table-wrap">]] .. initial_watching .. [[</div>
</div>

</div>

<script type="text/javascript">
var _lgGeoCache={};
var _lgGeoPending={};
var _lgBanLimit=5;
var _lgWatchLimit=5;

function lgEscHtml(s){
    return String(s||'').replace(/[&<>"']/g,function(c){
        return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];
    });
}

function lgColor(name){
    var root=document.querySelector('.lg-wrap');
    if(!root)return'#999';
    return getComputedStyle(root).getPropertyValue('--lg-'+name).trim()||'#999';
}

function lgQueryGeo(ip,cb){
    if(_lgGeoCache[ip]){cb(_lgGeoCache[ip]);return;}
    if(_lgGeoPending[ip]){
        _lgGeoPending[ip].push(cb);
        return;
    }
    _lgGeoPending[ip]=[cb];
    XHR.get(']] .. gu .. [[',{ip:ip},function(x,d){
        var loc=(d&&d.geo)?d.geo:'未知';
        var list=_lgGeoPending[ip]||[];
        delete _lgGeoPending[ip];
        _lgGeoCache[ip]=loc;
        for(var i=0;i<list.length;i++)list[i](loc);
    });
}

function lgApplyInitialWatchingLimit(){
    var rows=document.querySelectorAll('#lg-watching-list .lg-watch-row');
    for(var i=0;i<rows.length;i++){
        rows[i].style.display=(i<_lgWatchLimit)?'':'none';
    }
}

function lgQueryInitialWatchingGeo(){
    var rows=document.querySelectorAll('#lg-watching-list .lg-watch-row');
    var qi=0;
    function next(){
        while(qi<rows.length && rows[qi].style.display=='none')qi++;
        if(qi>=rows.length)return;
        var row=rows[qi++];
        var ip=row.getAttribute('data-ip')||'';
        var idx=row.getAttribute('data-index')||'';
        if(!ip){setTimeout(next,0);return;}
        lgQueryGeo(ip,function(loc){
            var ge=document.getElementById('lg-watch-geo-initial-'+idx);
            if(ge)ge.innerHTML='<span style="font-size:11px">'+lgEscHtml(loc)+'</span>';
            setTimeout(next,150);
        });
    }
    next();
}

function fmtDuration(s){
    if(s>=3600) return Math.floor(s/3600)+'h'+Math.floor((s%3600)/60)+'m';
    if(s>=60)   return Math.floor(s/60)+'m'+(s%60)+'s';
    return s+'s';
}

function lgUnban(ip,btn){
    if(!confirm('确认解封 '+ip+' ?'))return;
    btn.disabled=true; btn.textContent='...';
    XHR.get(']] .. uu .. [[',{ip:ip},function(x,d){
        if(d&&d.success){lgRefresh();}
        else{btn.disabled=false;btn.textContent='解封';alert('失败');}
    });
}

function lgManualBan(){
    var ip=document.getElementById('lg-ban-input').value.trim();
    if(!ip){alert('请输入 IP');return;}
    if(!ip.match(/^\d+\.\d+\.\d+\.\d+$/)){alert('IP 格式不对');return;}
    XHR.get(']] .. bu .. [[',{ip:ip},function(x,d){
        if(d&&d.success){
            document.getElementById('lg-ban-input').value='';
            lgRefresh();
        }else alert('失败');
    });
}

function lgFlushAll(){
    if(!confirm('确认清空所有封禁？此操作不可撤销。'))return;
    XHR.get(']] .. fu .. [[',null,function(x,d){
        if(d&&d.success)lgRefresh();
    });
}

function lgRenderWatching(watching,threshold){
    var wEl=document.getElementById('lg-watching-list');
    if(!wEl)return;
    watching=watching||[];
    threshold=Number(threshold)||3;
    if(watching.length==0){
        wEl.innerHTML='<div class="lg-empty">无</div>';
        return;
    }
    var h2='<table class="lg-table">';
    h2+='<thead><tr><th>IP 地址</th><th>归属地</th><th>失败次数</th><th>最近访问时间</th><th>距首次失败</th></tr></thead><tbody>';
    for(var j=0;j<watching.length;j++){
        var w=watching[j]||{};
        var ip=w.ip||'--';
        var count=Number(w.count)||0;
        var age=Number(w.age)||0;
        var lastSeen=w.last_seen||'--';
        var pct=Math.min(100,Math.round(count*100/threshold));
        var color=pct>=66?lgColor('danger'):(pct>=33?lgColor('warning'):lgColor('muted'));
        h2+='<tr>';
        h2+='<td><code class="lg-ip">'+lgEscHtml(ip)+'</code></td>';
        h2+='<td id="lg-watch-geo-'+j+'"><span style="color:'+lgColor('muted')+'">查询中...</span></td>';
        h2+='<td><span style="color:'+color+';font-weight:bold">'+count+' / '+threshold+'</span></td>';
        h2+='<td>'+lgEscHtml(lastSeen)+'</td>';
        h2+='<td>'+fmtDuration(age)+'</td>';
        h2+='</tr>';
    }
    h2+='</tbody></table>';
    wEl.innerHTML=h2;
    // 与总览“访问记录”保持一致：逐个查询归属地，避免并发太多。
    var qi=0;
    function nextWatchingGeo(){
        if(qi>=watching.length)return;
        var idx=qi;qi++;
        var row=watching[idx]||{};
        if(!row.ip){
            setTimeout(nextWatchingGeo,0);
            return;
        }
        lgQueryGeo(row.ip,function(loc){
            var ge=document.getElementById('lg-watch-geo-'+idx);
            if(ge) ge.innerHTML='<span style="font-size:11px">'+lgEscHtml(loc)+'</span>';
            setTimeout(nextWatchingGeo,150);
        });
    }
    nextWatchingGeo();
}

function lgApplyStatus(d){
        if(!d){
            var wEl=document.getElementById('lg-watching-list');
            if(wEl)wEl.innerHTML='<div class="lg-empty">刷新失败，请稍后再试</div>';
            return;
        }
        // 服务状态
        var rEl=document.getElementById('lg-running');
        if(d.enabled=='1'){
            if(d.running) rEl.innerHTML='<span style="color:'+lgColor('success')+'">✓ 运行中</span>';
            else rEl.innerHTML='<span style="color:'+lgColor('danger')+'">✗ 未运行</span>';
        }else{
            rEl.innerHTML='<span style="color:'+lgColor('muted')+'">未启用</span>';
        }
        document.getElementById('lg-banned-count').textContent=(d.banned_total!=null)?d.banned_total:(d.banned||[]).length;
        document.getElementById('lg-watching-count').textContent=(d.watching_total!=null)?d.watching_total:(d.watching||[]).length;

        // 已封禁列表
        var listEl=document.getElementById('lg-banned-list');
        if(!d.banned||d.banned.length==0){
            listEl.innerHTML='<div class="lg-empty">暂无封禁</div>';
        }else{
            var h='<table class="lg-table">';
            h+='<thead><tr><th>IP 地址</th><th>归属地</th><th>剩余时间</th><th>操作</th></tr></thead><tbody>';
            for(var i=0;i<d.banned.length;i++){
                var b=d.banned[i];
                h+='<tr>';
                h+='<td><code class="lg-ip lg-ip-danger">'+lgEscHtml(b.ip)+'</code></td>';
                h+='<td id="lg-geo-'+i+'"><span style="color:'+lgColor('muted')+'">查询中...</span></td>';
                h+='<td>'+fmtDuration(b.remaining)+'</td>';
                h+='<td><button class="lg-unban" onclick="lgUnban(\''+b.ip+'\',this)">解封</button></td>';
                h+='</tr>';
            }
            h+='</tbody></table>';
            listEl.innerHTML=h;
            // 异步查归属地
            var qi=0;
            (function next(){
                if(qi>=d.banned.length)return;
                var idx=qi; qi++;
                lgQueryGeo(d.banned[idx].ip,function(loc){
                    var ge=document.getElementById('lg-geo-'+idx);
                    if(ge) ge.innerHTML='<span style="font-size:11px">'+lgEscHtml(loc)+'</span>';
                    setTimeout(next,150);
                });
            })();
        }

        // 失败计数列表
        try{lgRenderWatching(d.watching,d.threshold);}
        catch(e){
            var wEl=document.getElementById('lg-watching-list');
            if(wEl)wEl.innerHTML='<div class="lg-empty">渲染失败：'+lgEscHtml(e.message)+'</div>';
        }

}

function lgRefresh(){
    XHR.get(']] .. lu .. [[',{ban_limit:_lgBanLimit,watch_limit:_lgWatchLimit},function(x,d){
        lgApplyStatus(d);
    });
}

var lgBanLimitSel=document.getElementById('lg-ban-limit');
if(lgBanLimitSel){
    lgBanLimitSel.value=String(_lgBanLimit);
    lgBanLimitSel.onchange=function(){
        var v=parseInt(this.value,10);
        _lgBanLimit=(v==20||v==30)?v:5;
        lgRefresh();
    };
}

var lgWatchLimitSel=document.getElementById('lg-watch-limit');
if(lgWatchLimitSel){
    lgWatchLimitSel.value=String(_lgWatchLimit);
    lgWatchLimitSel.onchange=function(){
        var v=parseInt(this.value,10);
        _lgWatchLimit=(v==20||v==30)?v:5;
        lgApplyInitialWatchingLimit();
        lgQueryInitialWatchingGeo();
        lgRefresh();
    };
}

lgApplyInitialWatchingLimit();
lgQueryInitialWatchingGeo();
lgRefresh();
setInterval(lgRefresh,8000);
</script>
]]
end

-- ============== 设置 ==============
s = m:section(NamedSection, "login_guard", "login_guard", "设置")
s.anonymous = true

o = s:option(Flag, "enabled", "启用登录防护")
o.description = "开启后将自动监控 SSH/LuCI 失败登录。LAN IP 永远不会被封禁。"
o.rmempty = false

o = s:option(Value, "threshold", "失败次数阈值")
o.description = "在「失败窗口」时间内累积达到此次数则封禁。"
o.datatype = "uinteger"
o.default = "3"
o.placeholder = "3"

o = s:option(ListValue, "window", "失败窗口（秒）")
o.description = "在多长时间内累计失败次数。超过此时间未再失败则计数清零。"
o:value("300", "5 分钟")
o:value("600", "10 分钟")
o:value("1800", "30 分钟")
o:value("3600", "1 小时")
o:value("86400", "24 小时")
o.default = "600"

o = s:option(ListValue, "bantime", "封禁时长")
o:value("3600", "1 小时")
o:value("21600", "6 小时")
o:value("43200", "12 小时")
o:value("86400", "24 小时")
o:value("604800", "1 周")
o:value("2592000", "30 天")
o.default = "43200"

o = s:option(DynamicList, "whitelist", "白名单（额外）")
o.description = "除了 LAN 私有段（192.168.x、10.x、127.x、172.16-31.x）默认豁免外，再加这些 IP/CIDR。" ..
                "支持单 IP（如 1.2.3.4）或 /8 /16 /24 /32 子网。"
o.placeholder = "如 8.8.8.8 或 203.0.113.0/24"

return m
