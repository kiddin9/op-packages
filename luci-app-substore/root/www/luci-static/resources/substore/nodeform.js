/* nodeform.js — 节点动态字段表单（local_form.htm / node_edit.htm 共用）
 * 依赖页面在引入本文件前定义：
 *   var FIELD_LABELS = { "name": "...", "group": "...", ... };   // 字段标签（模板用 <%:...%> 渲染）
 *   var NODEFORM_I18N = { node: "...", defaultOpt: "..." };      // 界面文本（同上）
 * 提供：SUBSTORE_PROTOS / PROTO_FIELDS / renderFields / collectNodes / addNodeRow
 */

var SUBSTORE_PROTOS = ["vmess","vless","trojan","shadowsocks","ssr","hysteria2","tuic","wireguard"];

var PROTO_FIELDS = {
	ssr: ["server","port","password","cipher","protocol","obfs","obfs-param","protocol-param","udp"],
	vmess: ["server","port","uuid","alterId","cipher","net","headerType","path","host","sni","tls","udp","skip-cert-verify"],
	vless: ["server","port","uuid","security","flow","net","headerType","path","host","sni","udp","skip-cert-verify"],
	trojan: ["server","port","password","sni","net","headerType","path","host","udp","skip-cert-verify"],
	shadowsocks: ["server","port","password","method","headerType","udp"],
	hysteria2: ["server","port","password","sni","obfs","obfs-password","skip-cert-verify"],
	tuic: ["server","port","uuid","password","sni","udp","skip-cert-verify"],
	wireguard: ["server","port","private-key","public-key","pre-shared-key","ip","ipv6","allowed-ips","reserved","persistent-keepalive","listen-port","mtu","amnezia-wg-option"]
};

// 枚举字段用下拉框；键为 "协议.字段" 优先，退化为通用 "字段"
// 选项集合以模型/输出模块实际支持的值为准（见 output_singbox.build_transport / output_uri）
var SELECT_FIELDS = {
	"net": ["tcp","ws","h2","grpc"],
	"headerType": ["none","http"],
	"cipher": ["auto","aes-128-gcm","chacha20-poly1305","none","zero"],
	"method": ["aes-128-gcm","aes-256-gcm","chacha20-ietf-poly1305","xchacha20-ietf-poly1305","aes-128-cfb","aes-256-cfb","rc4-md5","chacha20-ietf","2022-blake3-aes-128-gcm","2022-blake3-aes-256-gcm","2022-blake3-chacha20-poly1305"],
	"security": ["none","tls","reality"],
	"flow": ["","xtls-rprx-vision"],
	"tls": ["","tls"],
	"hysteria2.obfs": ["","salamander"]
};

// 布尔字段用下拉框：默认（不提交）/ true / false
var BOOL_FIELDS = { "udp": true, "skip-cert-verify": true };

function nodeformLabel(k) {
	return (typeof FIELD_LABELS === "object" && FIELD_LABELS && FIELD_LABELS[k]) || k;
}

function nodeformT(k) {
	return (typeof NODEFORM_I18N === "object" && NODEFORM_I18N && NODEFORM_I18N[k]) || k;
}

function fieldRow(k, proto) {
	var label = nodeformLabel(k);
	var input;
	var opts = SELECT_FIELDS[proto + "." + k] || SELECT_FIELDS[k];
	if (opts) {
		input = '<select data-k="' + k + '">';
		for (var i = 0; i < opts.length; i++) {
			var v = opts[i];
			input += '<option value="' + v + '">' + (v === "" ? nodeformT("defaultOpt") : v) + '</option>';
		}
		input += '</select>';
	} else if (BOOL_FIELDS[k]) {
		input = '<select data-k="' + k + '">' +
			'<option value="">' + nodeformT("defaultOpt") + '</option>' +
			'<option value="true">true</option>' +
			'<option value="false">false</option>' +
			'</select>';
	} else {
		input = '<input type="text" data-k="' + k + '" style="width:50%"/>';
	}
	return '<label style="display:inline-block;min-width:10em">' + label + '</label>' + input + '<br/>';
}

function nodeTemplate(idx) {
	var opts = "";
	for (var i = 0; i < SUBSTORE_PROTOS.length; i++) {
		opts += '<option value="' + SUBSTORE_PROTOS[i] + '">' + SUBSTORE_PROTOS[i] + '</option>';
	}
	return '<div class="node_row" style="border:1px solid #ddd;padding:0.5em;margin:0.5em 0">' +
		'<div style="margin-bottom:0.25em"><strong>' + nodeformT("node") + ' ' + (idx + 1) + '</strong> ' +
		'<button type="button" class="cbi-button cbi-button-reset node_remove" onclick="this.parentNode.parentNode.remove()">×</button></div>' +
		'<label style="display:inline-block;min-width:10em">' + nodeformLabel("name") + '</label>' +
		'<input type="text" data-k="name" style="width:50%"/><br/>' +
		'<label style="display:inline-block;min-width:10em">' + nodeformLabel("group") + '</label>' +
		'<input type="text" data-k="group" style="width:50%"/><br/>' +
		'<label style="display:inline-block;min-width:10em">' + nodeformLabel("type") + '</label>' +
		'<select data-k="type" onchange="renderFields(this)">' + opts + '</select><br/>' +
		'<div class="fields"></div>' +
		'</div>';
}

function renderFields(sel, data) {
	var row = sel.parentNode;
	while (row && row.className.indexOf("node_row") < 0) row = row.parentNode;
	if (!row) return;
	var fieldsDiv = row.querySelector(".fields");
	var proto = sel.value;
	var keys = PROTO_FIELDS[proto] || [];
	var html = "";
	for (var i = 0; i < keys.length; i++) html += fieldRow(keys[i], proto);
	fieldsDiv.innerHTML = html;
	if (data) {
		for (var j = 0; j < keys.length; j++) {
			var el = fieldsDiv.querySelector('[data-k="' + keys[j] + '"]');
			if (el && data[keys[j]] !== undefined && data[keys[j]] !== null) el.value = String(data[keys[j]]);
		}
	}
}

function collectNodes() {
	var rows = document.querySelectorAll(".node_row");
	var out = [];
	for (var i = 0; i < rows.length; i++) {
		var obj = {};
		var els = rows[i].querySelectorAll("[data-k]");
		for (var j = 0; j < els.length; j++) {
			var k = els[j].getAttribute("data-k");
			var v = (els[j].value || "").replace(/^\s+|\s+$/g, "");
			if (v !== "") obj[k] = v;
		}
		if (obj.name || obj.server) out.push(obj);
	}
	return out;
}

function addNodeRow(data) {
	var list = document.getElementById("nodes_list");
	var div = document.createElement("div");
	div.innerHTML = nodeTemplate(list.children.length);
	var row = div.firstChild;
	list.appendChild(row);
	var sel = row.querySelector('select[data-k="type"]');
	if (data && (data.type || data.proto)) sel.value = data.type || data.proto;
	if (data && data.name) {
		var nameEl = row.querySelector('[data-k="name"]');
		if (nameEl) nameEl.value = data.name;
	}
	if (data && data.group) {
		var groupEl = row.querySelector('[data-k="group"]');
		if (groupEl) groupEl.value = data.group;
	}
	renderFields(sel, data);
	return row;
}
