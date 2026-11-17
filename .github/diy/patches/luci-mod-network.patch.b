--- a/luci-mod-network/root/usr/share/ucitrack/luci-mod-network-dnsmasq.json
+++ b/luci-mod-network/root/usr/share/ucitrack/luci-mod-network-dnsmasq.json
@@ -1,7 +1,4 @@
 {
 	"config": "dhcp",
-	"init": "dnsmasq",
-	"affects": [
-		"odhcpd"
-	]
+	"init": "dnsmasq"
 }

--- a/luci-mod-network/htdocs/luci-static/resources/view/network/dns.js
+++ b/luci-mod-network/htdocs/luci-static/resources/view/network/dns.js
@@ -437,6 +442,9 @@ return view.extend({
 		so.rmempty = false;
 		so.datatype = 'ipaddr("nomask")';
 
+		so = ss.option(form.Value, 'comments', _('Comments'));
+		so.rmempty  = true;
+
 		const ipaddrs = {};
 
 		Object.keys(hosts).forEach(function(mac) {
