--- a/luci-app-timewol/luasrc/model/cbi/timewol.lua
+++ b/luci-app-timewol/luasrc/model/cbi/timewol.lua
@@ -48,6 +48,13 @@ for _, device in ipairs(sys.net.devices()) do
 	end
 end
 
+-- wake device
+local btn = s:option(Button, "_awake",translate("Wake Up Host"))
+btn.inputtitle	= translate("Awake")
+btn.inputstyle	= "apply"
+btn.disabled	= false
+btn.template = "timewol/awake"
+
 -- Function to validate cron field values
 local function validate_cron_field(option_name, value, min, max, default)
 	if value == "" then

new file mode 100644
index 0000000..91cd71b
--- /dev/null
+++ b/luci-app-timewol/luasrc/view/timewol/awake.htm
@@ -0,0 +1,3 @@
+<%+cbi/valueheader%>
+	<input class="cbi-button cbi-input-<%=self.inputstyle or "button" %>" style="font-size: 100%;" type="button" onclick="onclick_awake(this.id)" <%=attr("name", section) .. attr("id", cbid) .. attr("value", self.inputtitle)%> />
+<%+cbi/valuefooter%>

--- a/luci-app-timewol/luasrc/controller/timewol.lua
+++ b/luci-app-timewol/luasrc/controller/timewol.lua
@@ -11,6 +11,7 @@ function index()
 	page.acl_depends = { "luci-app-timewol" }
 
 	entry({"admin", "control", "timewol", "status"}, call("status")).leaf = true
+	entry({"admin", "control", "timewol", "awake"}, call("awake")).leaf = true
 end
 
 function status()
@@ -19,3 +20,27 @@ function status()
 	luci.http.prepare_content("application/json")
 	luci.http.write_json(e)
 end
+
+function awake(sections)
+	lan = x:get("timewol",sections,"maceth")
+	mac = x:get("timewol",sections,"macaddr")
+    local e = {}
+    cmd = "/usr/bin/etherwake -D -i " .. lan .. " -b " .. mac .. " 2>&1"
+	local p = io.popen(cmd)
+	local msg = ""
+	if p then
+		while true do
+			local l = p:read("*l")
+			if l then
+				if #l > 100 then l = l:sub(1, 100) .. "..." end
+				msg = msg .. l
+			else
+				break
+			end
+		end
+		p:close()
+	end
+	e["data"] = msg
+    luci.http.prepare_content("application/json")
+    luci.http.write_json(e)
+end

--- a/luci-app-timewol/po/zh-cn/timewol.po
+++ b/luci-app-timewol/po/zh-cn/timewol.po
@@ -52,3 +52,5 @@ msgstr "星期"
 msgid "Invalid value for %s: %s. Must be between %d and %d or '*'"
 msgstr "%s: %s 的值无效. 必须在 %d 和 %d 之间，或为 '*'"
 
+msgid "Awake"
+msgstr "立即唤醒"

--- a/luci-app-timewol/luasrc/view/timewol/index.htm
+++ b/luci-app-timewol/luasrc/view/timewol/index.htm
@@ -14,5 +14,23 @@
 			status.innerHTML = result.status?'<%=translate("RUNNING")%>':'<%=translate("NOT RUNNING")%>';
 		}
 	)
+	function _id2section(id) {
+		var x = id.split(".");
+		return x[2];
+	}
+	function onclick_awake(id) {
+		var section = _id2section(id);
+		var btnXHR = new XHR();
+		btnXHR.post('<%=url([[admin]], [[control]], [[timewol]], [[awake]])%>/' + section, { token: '<%=token%>' },
+			function(x, data) {
+				if (x.responseText == "_uncommitted_") {
+					txt="<%:Please [Save & Apply] your changes first%>";
+					alert( txt.replace(new RegExp("<%:&%>", "g"), "&") );
+				} else {
+					alert( JSON.parse(x.response).data );
+				}
+			}
+		);
+	}
 //]]>
 </script>
