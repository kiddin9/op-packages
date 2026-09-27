local m,s,o
local sys=require"luci.sys"
local fs=require"nixio.fs"
local uc=require"luci.model.uci".cursor()

local dd={}
uc:foreach("minigate","ddns",function(sec) if sec.domain and sec.domain~=""then dd[#dd+1]=sec.domain end end)

m=Map("minigate","MiniGate - SSL 证书","ACME（Let's Encrypt）自动签发。域名和令牌自动关联「动态DNS」。")

s=m:section(NamedSection,"acme","acme","ACME 设置"); s.anonymous=true

o=s:option(Flag,"enabled","启用 ACME"); o.rmempty=false

o=s:option(Value,"email","账户邮箱"); o.placeholder="admin@example.com"; o.rmempty=true
o.description="可选。"

o=s:option(ListValue,"key_type","密钥类型")
o:value("ec-256","ECC P-256（推荐）"); o:value("ec-384","ECC P-384"); o:value("rsa-2048","RSA 2048"); o:value("rsa-4096","RSA 4096")
o.default="ec-256"

o=s:option(Flag,"staging","测试模式"); o.rmempty=false; o.default="1"
o.description="正式使用请关闭。"

-- 证书列表
o=s:option(DummyValue,"_certs","已签发证书"); o.rawhtml=true
o.cfgvalue=function()
    local cd="/etc/minigate/certs"
    local h='<table class="table"><tr class="tr table-titles"><th class="th">域名</th><th class="th">过期时间</th><th class="th">路径</th></tr>'
    local found=false
    if fs.dir(cd)then
        for entry in fs.dir(cd)do
            local fp=cd.."/"..entry
            -- lstat 返回 table，检查 type 字段
            local st=fs.lstat(fp)
            if st and st.type=="dir"then
                local cert=fp.."/fullchain.pem"
                if fs.access(cert)then
                    found=true
                    local exp=""
                    local f=io.popen("openssl x509 -in '"..cert.."' -noout -enddate 2>/dev/null")
                    if f then local l=f:read("*l"); if l then exp=l:gsub("notAfter=","") end; f:close() end
                    local dn=entry:gsub("_wildcard_%.", "*.")
                    h=h..'<tr class="tr"><td class="td"><strong>'..dn..'</strong></td><td class="td">'..exp..'</td><td class="td"><code>'..fp..'/</code></td></tr>'
                end
            end
        end
    end
    if not found then h=h..'<tr class="tr"><td class="td" colspan="3" style="text-align:center;color:#999;padding:15px">暂无证书</td></tr>' end
    return h..'</table>'
end

o=s:option(DummyValue,"_ast","acme.sh 状态"); o.rawhtml=true
o.cfgvalue=function()
    if fs.access("/etc/minigate/acme/data/acme.sh")and fs.access("/etc/minigate/acme/data/dnsapi/dns_cf.sh")then return'<span style="color:#4caf50">&#10003; 已安装</span>'
    elseif fs.access("/etc/minigate/acme/data/acme.sh")then return'<span style="color:#ff9800">&#9888; 缺DNS插件</span>'
    else return'<span style="color:#f44336">&#10007; 未安装</span>'end
end

-- 操作
s=m:section(NamedSection,"acme","acme","操作"); s.anonymous=true
o=s:option(DummyValue,"_act"," "); o.rawhtml=true
o.cfgvalue=function()
    local iu=luci.dispatcher.build_url("admin/services/minigate/acme_install")
    local su=luci.dispatcher.build_url("admin/services/minigate/acme_issue")
    local opts=""
    for _,d in ipairs(dd)do opts=opts..'<option value="'..d..'">'..d..'</option>' end
    return[[
<div style="margin-bottom:15px"><button class="cbi-button cbi-button-reload" id="bi" onclick="doI()" style="min-width:220px">下载并安装 acme.sh</button></div>
<div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin-bottom:10px">
<label>签发域名：</label>
<select id="sd" style="padding:5px 10px;border-radius:4px;border:1px solid #ccc;min-width:250px">]]..
(opts~=""and opts or'<option value="">请先配置动态DNS</option>')..[[</select>
<button class="cbi-button cbi-button-apply" id="bs" onclick="doS()">立即签发 / 续期</button></div>
<div id="ap" style="margin-top:12px;display:none"><div style="background:#f0f0f0;border-radius:4px;padding:10px 15px;font-size:13px"><span style="display:inline-block;animation:sp 1s linear infinite;margin-right:8px">&#9203;</span><span id="am">处理中...</span></div></div>
<div id="ar" style="margin-top:12px;display:none"><div id="ai" style="border-radius:4px;padding:10px 15px;font-size:13px"></div></div>
<style>@keyframes sp{from{transform:rotate(0deg)}to{transform:rotate(360deg)}}</style>
<script type="text/javascript">
function sP(m){document.getElementById('ap').style.display='block';document.getElementById('ar').style.display='none';document.getElementById('am').textContent=m}
function sR(ok,m){document.getElementById('ap').style.display='none';document.getElementById('ar').style.display='block';var e=document.getElementById('ai');e.style.background=ok?'#e8f5e9':'#ffebee';e.style.color=ok?'#2e7d32':'#c62828';e.textContent=m}
function doI(){document.getElementById('bi').disabled=true;sP('下载安装中（约30秒）...');XHR.get(']]..iu..[[',null,function(x,d){document.getElementById('bi').disabled=false;d?sR(d.success,d.message):sR(false,'失败');if(d&&d.success)setTimeout(function(){location.reload()},2000)})}
function doS(){var d=document.getElementById('sd').value;if(!d){sR(false,'请选择域名');return}document.getElementById('bs').disabled=true;sP('签发 '+d+'（约1-2分钟）...');XHR.get(']]..su..[[',{domain:d},function(x,r){document.getElementById('bs').disabled=false;r?sR(r.success,r.message):sR(false,'超时');if(r&&r.success)setTimeout(function(){location.reload()},2000)})}
</script>]]
end

return m
