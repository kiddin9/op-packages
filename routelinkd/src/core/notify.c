#include "core/notify.h"

#include <ctype.h>
#include <inttypes.h>
#include <json-c/json.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "core/sha256.h"

unsigned rl_notify_sub_parse(const char *s)
{
	if (!s)
		return 0;
	if (strcmp(s, "device_new") == 0)
		return RL_NS_DEVICE_NEW;
	if (strcmp(s, "device_watch") == 0)
		return RL_NS_DEVICE_WATCH;
	if (strcmp(s, "quota") == 0)
		return RL_NS_QUOTA;
	if (strcmp(s, "outage") == 0)
		return RL_NS_OUTAGE;
	return 0;
}

unsigned rl_notify_sub_of(rl_notify_kind k)
{
	switch (k) {
	case RL_NE_DEVICE_NEW:
		return RL_NS_DEVICE_NEW;
	case RL_NE_DEVICE_ONLINE:
	case RL_NE_DEVICE_OFFLINE:
		return RL_NS_DEVICE_WATCH;
	case RL_NE_QUOTA_WARN:
	case RL_NE_QUOTA_EXCEEDED:
		return RL_NS_QUOTA;
	default:
		return RL_NS_OUTAGE;
	}
}

/* snprintf that appends at *len and never overflows; the result stays NUL-terminated. */
static void add(char *buf, size_t size, size_t *len, const char *fmt, ...)
{
	if (*len >= size)
		return;
	va_list ap;
	va_start(ap, fmt);
	int n = vsnprintf(buf + *len, size - *len, fmt, ap);
	va_end(ap);
	if (n > 0)
		*len = *len + (size_t)n < size ? *len + (size_t)n : size - 1;
}

static void human_bytes(uint64_t b, char *out, size_t size)
{
	static const char *units[] = { "B", "KB", "MB", "GB", "TB" };
	double v = (double)b;
	int u = 0;
	while (v >= 1024 && u < 4) {
		v /= 1024;
		u++;
	}
	snprintf(out, size, u ? "%.1f %s" : "%.0f %s", v, units[u]);
}

static void human_duration(int64_t s, bool zh, char *out, size_t size)
{
	if (s < 0)
		s = 0;
	int64_t h = s / 3600, m = s % 3600 / 60, sec = s % 60;
	if (h)
		snprintf(out, size, zh ? "%" PRId64 " 小时 %" PRId64 " 分" : "%" PRId64 " h %" PRId64 " min", h, m);
	else if (m)
		snprintf(out, size, zh ? "%" PRId64 " 分 %" PRId64 " 秒" : "%" PRId64 " min %" PRId64 " s", m, sec);
	else
		snprintf(out, size, zh ? "%" PRId64 " 秒" : "%" PRId64 " s", sec);
}

static const char *cause_text(const char *cause, bool zh)
{
	if (cause && strcmp(cause, "wan_down") == 0)
		return zh ? "WAN 断开" : "the WAN connection dropped";
	if (cause && strcmp(cause, "redial") == 0)
		return zh ? "重新拨号" : "the line reconnected";
	return zh ? "上游不通" : "the provider's network was down";
}

/* Headline and detail line of one event. */
static void describe(const rl_notify_event *e, bool zh, char *head, size_t hs, char *detail, size_t ds)
{
	const char *who = e->name[0] ? e->name : e->mac;
	char used[24], limit[24], dur[32];
	switch (e->kind) {
	case RL_NE_DEVICE_NEW:
		snprintf(head, hs, zh ? "新设备接入：%s" : "New device: %s", who);
		snprintf(detail, ds, "%s%s%s", e->ip, e->ip[0] && e->mac[0] ? " · " : "", e->mac);
		break;
	case RL_NE_DEVICE_ONLINE:
	case RL_NE_DEVICE_OFFLINE: {
		bool on = e->kind == RL_NE_DEVICE_ONLINE;
		snprintf(head, hs, zh ? (on ? "%s 上线了" : "%s 离线了") : (on ? "%s is online" : "%s went offline"), who);
		snprintf(detail, ds, "%s", e->ip[0] ? e->ip : e->mac);
		break;
	}
	case RL_NE_QUOTA_WARN:
		human_bytes(e->used, used, sizeof(used));
		human_bytes(e->limit, limit, sizeof(limit));
		snprintf(head, hs, zh ? "%s 的流量已用 %d%%" : "%s has used %d%% of its data", who,
			 e->limit ? (int)(e->used * 100 / e->limit) : 0);
		snprintf(detail, ds, zh ? "本周期 %s / %s" : "%s of %s this period", used, limit);
		break;
	case RL_NE_QUOTA_EXCEEDED:
		snprintf(head, hs, zh ? "%s 的流量用完了" : "%s used up its data", who);
		snprintf(detail, ds, "%s",
			 zh ? (e->slow_down ? "已限速，可以在 App 里临时放行" : "已断开外网，可以在 App 里临时放行")
			    : (e->slow_down ? "Slowed down; let it through in the app" : "Cut off the internet; let it through in the app"));
		break;
	case RL_NE_OUTAGE:
		human_duration(e->duration, zh, dur, sizeof(dur));
		snprintf(head, hs, "%s", zh ? "网络已恢复" : "The internet is back");
		snprintf(detail, ds, zh ? "断网 %s，原因：%s" : "Down for %s: %s", dur, cause_text(e->cause, zh));
		break;
	}
}

void rl_notify_format(const rl_notify_event *ev, int n, const char *router, bool zh, char *title, size_t title_size,
		      char *body, size_t body_size)
{
	char head[160], detail[160];
	size_t len = 0;
	title[0] = body[0] = '\0';
	if (n <= 0)
		return;
	if (n == 1) {
		describe(&ev[0], zh, head, sizeof(head), detail, sizeof(detail));
		snprintf(title, title_size, "%s", head);
		add(body, body_size, &len, "%s", detail);
		if (router && router[0])
			add(body, body_size, &len, "%s%s", detail[0] ? "\n" : "", router);
		return;
	}
	snprintf(title, title_size, zh ? "%s：%d 条通知" : "%s: %d notices", router && router[0] ? router : "RouteLink", n);
	for (int i = 0; i < n; i++) {
		describe(&ev[i], zh, head, sizeof(head), detail, sizeof(detail));
		add(body, body_size, &len, "%s%s", i ? "\n" : "", head);
		if (detail[0])
			add(body, body_size, &len, zh ? "（%s）" : " (%s)", detail);
	}
}

void rl_notify_batch_add(rl_notify_batch *b, const rl_notify_event *ev)
{
	if (b->n < RL_NOTIFY_BATCH_MAX)
		b->ev[b->n++] = *ev;
	else
		b->dropped++;
}

bool rl_notify_batch_due(const rl_notify_batch *b, int64_t now)
{
	return b->n > 0 && now - b->ev[0].ts >= RL_NOTIFY_MERGE_SEC;
}

void rl_notify_batch_clear(rl_notify_batch *b)
{
	b->n = 0;
	b->dropped = 0;
}

int rl_notify_type_parse(const char *s)
{
	static const char *names[] = { "webhook", "bark", "serverchan", "pushplus",
				       "telegram", "wecom", "dingtalk", "feishu" };
	for (int i = 0; s && i < 8; i++)
		if (strcmp(s, names[i]) == 0)
			return i;
	return -1;
}

size_t rl_json_escape(const char *in, char *out, size_t size)
{
	size_t n = 0;
	for (const unsigned char *p = (const unsigned char *)in; *p; p++) {
		char tmp[8];
		const char *rep = NULL;
		switch (*p) {
		case '"':
			rep = "\\\"";
			break;
		case '\\':
			rep = "\\\\";
			break;
		case '\n':
			rep = "\\n";
			break;
		case '\r':
			rep = "\\r";
			break;
		case '\t':
			rep = "\\t";
			break;
		default:
			if (*p < 0x20) {
				snprintf(tmp, sizeof(tmp), "\\u%04x", *p);
				rep = tmp;
			}
		}
		size_t l = rep ? strlen(rep) : 1;
		if (n + l + 1 > size)
			return (size_t)-1;
		if (rep)
			memcpy(out + n, rep, l);
		else
			out[n] = (char)*p;
		n += l;
	}
	if (n + 1 > size)
		return (size_t)-1;
	out[n] = '\0';
	return n;
}

size_t rl_url_encode(const char *in, char *out, size_t size)
{
	static const char hex[] = "0123456789ABCDEF";
	size_t n = 0;
	for (const unsigned char *p = (const unsigned char *)in; *p; p++) {
		bool plain = isalnum(*p) || *p == '-' || *p == '_' || *p == '.' || *p == '~';
		if (n + (plain ? 1 : 3) + 1 > size)
			return (size_t)-1;
		if (plain) {
			out[n++] = (char)*p;
		} else {
			out[n++] = '%';
			out[n++] = hex[*p >> 4];
			out[n++] = hex[*p & 15];
		}
	}
	out[n] = '\0';
	return n;
}

static bool set(const char *s)
{
	return s && s[0];
}

/* A JSON string value (escaped) appended to the body; false when it does not fit. */
static bool jstr(char *body, size_t *len, const char *s)
{
	size_t l = rl_json_escape(s, body + *len, RL_NOTIFY_BODY_MAX - *len);
	if (l == (size_t)-1)
		return false;
	*len += l;
	return true;
}

/* Builds the body from a printf-like pattern where %s takes an escaped string. */
static int json(rl_notify_request *out, const char *pattern, ...)
{
	va_list ap;
	size_t len = 0;
	va_start(ap, pattern);
	for (const char *p = pattern; *p; p++) {
		if (p[0] == '%' && p[1] == 's') {
			if (!jstr(out->body, &len, va_arg(ap, const char *))) {
				va_end(ap);
				return -1;
			}
			p++;
			continue;
		}
		if (len + 2 > RL_NOTIFY_BODY_MAX) {
			va_end(ap);
			return -1;
		}
		out->body[len++] = *p;
	}
	va_end(ap);
	out->body[len] = '\0';
	return 0;
}

static int url(rl_notify_request *out, const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	int n = vsnprintf(out->url, sizeof(out->url), fmt, ap);
	va_end(ap);
	return n > 0 && (size_t)n < sizeof(out->url) ? 0 : -1;
}

/* Webhook template: {title} and {body} replaced by escaped strings. */
static int from_template(rl_notify_request *out, const char *tpl, const char *title, const char *body)
{
	size_t len = 0;
	for (const char *p = tpl; *p;) {
		const char *value = NULL;
		if (strncmp(p, "{title}", 7) == 0)
			value = title, p += 7;
		else if (strncmp(p, "{body}", 6) == 0)
			value = body, p += 6;
		if (value) {
			if (!jstr(out->body, &len, value))
				return -1;
			continue;
		}
		if (len + 2 > RL_NOTIFY_BODY_MAX)
			return -1;
		out->body[len++] = *p++;
	}
	out->body[len] = '\0';
	return 0;
}

int rl_notify_build(rl_notify_type t, const rl_notify_conf *c, const char *title, const char *body, int64_t now_ms,
		    rl_notify_request *out)
{
	char text[RL_NOTIFY_BODY_MAX / 2];
	snprintf(text, sizeof(text), "%s\n%s", title, body);
	memset(out, 0, sizeof(*out));
	out->kind = RL_NB_JSON;
	switch (t) {
	case RL_NT_WEBHOOK:
		if (!set(c->url) || url(out, "%s", c->url) < 0)
			return -1;
		if (set(c->template))
			return from_template(out, c->template, title, body);
		return json(out, "{\"title\":\"%s\",\"body\":\"%s\"}", title, body);
	case RL_NT_BARK: {
		if (!set(c->token))
			return -1;
		const char *base = set(c->url) ? c->url : "https://api.day.app";
		size_t l = strlen(base);
		if (url(out, "%.*s/push", (int)(l && base[l - 1] == '/' ? l - 1 : l), base) < 0)
			return -1;
		return json(out, "{\"device_key\":\"%s\",\"title\":\"%s\",\"body\":\"%s\",\"group\":\"RouteLink\"}", c->token,
			    title, body);
	}
	case RL_NT_SERVERCHAN: {
		if (!set(c->token))
			return -1;
		/* ServerChan³ keys look like sctp<uid>t…: they go to the user's own host. */
		unsigned uid = 0;
		if (strncmp(c->token, "sctp", 4) == 0 && sscanf(c->token + 4, "%ut", &uid) == 1 && uid) {
			if (url(out, "https://%u.push.ft07.com/send/%s.send", uid, c->token) < 0)
				return -1;
		} else if (url(out, "https://sctapi.ftqq.com/%s.send", c->token) < 0) {
			return -1;
		}
		return json(out, "{\"title\":\"%s\",\"desp\":\"%s\"}", title, body);
	}
	case RL_NT_PUSHPLUS:
		if (!set(c->token) || url(out, "https://www.pushplus.plus/send") < 0)
			return -1;
		return json(out, "{\"token\":\"%s\",\"title\":\"%s\",\"content\":\"%s\",\"template\":\"txt\"}", c->token, title,
			    body);
	case RL_NT_TELEGRAM:
		if (!set(c->token) || !set(c->chat_id) || url(out, "https://api.telegram.org/bot%s/sendMessage", c->token) < 0)
			return -1;
		return json(out, "{\"chat_id\":\"%s\",\"text\":\"%s\"}", c->chat_id, text);
	case RL_NT_WECOM:
		if (!set(c->url) || url(out, "%s", c->url) < 0)
			return -1;
		return json(out, "{\"msgtype\":\"text\",\"text\":{\"content\":\"%s\"}}", text);
	case RL_NT_DINGTALK: {
		if (!set(c->url))
			return -1;
		if (!set(c->secret)) {
			if (url(out, "%s", c->url) < 0)
				return -1;
		} else {
			/* sign = urlencode(base64(HMAC-SHA256(secret, "<ms>\n<secret>"))) */
			char to_sign[512], b64[64], enc[160];
			uint8_t mac[RL_SHA256_LEN];
			snprintf(to_sign, sizeof(to_sign), "%" PRId64 "\n%s", now_ms, c->secret);
			rl_hmac_sha256(c->secret, strlen(c->secret), to_sign, strlen(to_sign), mac);
			rl_base64(mac, sizeof(mac), b64, sizeof(b64));
			if (rl_url_encode(b64, enc, sizeof(enc)) == (size_t)-1)
				return -1;
			if (url(out, "%s%ctimestamp=%" PRId64 "&sign=%s", c->url, strchr(c->url, '?') ? '&' : '?', now_ms,
				enc) < 0)
				return -1;
		}
		return json(out, "{\"msgtype\":\"text\",\"text\":{\"content\":\"%s\"}}", text);
	}
	case RL_NT_FEISHU: {
		if (!set(c->url) || url(out, "%s", c->url) < 0)
			return -1;
		if (!set(c->secret))
			return json(out, "{\"msg_type\":\"text\",\"content\":{\"text\":\"%s\"}}", text);
		/* sign = base64(HMAC-SHA256(key = "<s>\n<secret>", message = "")) */
		char ts[24], to_sign[512], b64[64];
		uint8_t mac[RL_SHA256_LEN];
		snprintf(ts, sizeof(ts), "%" PRId64, now_ms / 1000);
		snprintf(to_sign, sizeof(to_sign), "%s\n%s", ts, c->secret);
		rl_hmac_sha256(to_sign, strlen(to_sign), "", 0, mac);
		rl_base64(mac, sizeof(mac), b64, sizeof(b64));
		return json(out, "{\"timestamp\":\"%s\",\"sign\":\"%s\",\"msg_type\":\"text\",\"content\":{\"text\":\"%s\"}}", ts,
			    b64, text);
	}
	}
	return -1;
}

/* Appends key=value (value percent-encoded) to a form body. */
static int form(rl_notify_request *out, size_t *len, const char *key, const char *value)
{
	size_t l = *len;
	int n = snprintf(out->body + l, RL_NOTIFY_BODY_MAX - l, "%s%s=", l ? "&" : "", key);
	if (n < 0 || (size_t)n >= RL_NOTIFY_BODY_MAX - l)
		return -1;
	l += (size_t)n;
	size_t e = rl_url_encode(value, out->body + l, RL_NOTIFY_BODY_MAX - l);
	if (e == (size_t)-1)
		return -1;
	*len = l + e;
	return 0;
}

/* Cuts s to at most max bytes without splitting a UTF-8 sequence. */
static void cut_utf8(char *s, size_t max)
{
	size_t n = strlen(s);
	if (n <= max)
		return;
	while (max > 0 && ((unsigned char)s[max] & 0xc0) == 0x80)
		max--;
	s[max] = '\0';
}

int rl_notify_build_legacy(rl_notify_type t, const rl_notify_conf *c, const char *title, const char *body,
			   int64_t now_ms, rl_notify_request *out)
{
	size_t len = 0;
	switch (t) {
	case RL_NT_BARK: {
		/* POST /<key> with form fields (the JSON endpoint /push needs the content type) */
		if (!set(c->token))
			return -1;
		memset(out, 0, sizeof(*out));
		out->kind = RL_NB_FORM;
		const char *base = set(c->url) ? c->url : "https://api.day.app";
		size_t l = strlen(base);
		char key[256];
		if (rl_url_encode(c->token, key, sizeof(key)) == (size_t)-1 ||
		    url(out, "%.*s/%s", (int)(l && base[l - 1] == '/' ? l - 1 : l), base, key) < 0)
			return -1;
		return form(out, &len, "title", title) || form(out, &len, "body", body) ||
				       form(out, &len, "group", "RouteLink")
			       ? -1
			       : 0;
	}
	case RL_NT_SERVERCHAN:
		if (rl_notify_build(t, c, title, body, now_ms, out) < 0)
			return -1;
		out->kind = RL_NB_FORM;
		return form(out, &len, "title", title) || form(out, &len, "desp", body) ? -1 : 0;
	case RL_NT_TELEGRAM: {
		if (rl_notify_build(t, c, title, body, now_ms, out) < 0)
			return -1;
		char text[RL_NOTIFY_BODY_MAX / 2];
		snprintf(text, sizeof(text), "%s\n%s", title, body);
		out->kind = RL_NB_FORM;
		return form(out, &len, "chat_id", c->chat_id) || form(out, &len, "text", text) ? -1 : 0;
	}
	case RL_NT_PUSHPLUS: {
		/* GET with query parameters; a long message is shortened to fit the URL */
		if (!set(c->token))
			return -1;
		char content[RL_NOTIFY_BODY_MAX / 2], tok[256], ttl[512], enc[RL_NOTIFY_URL_MAX];
		if (rl_url_encode(c->token, tok, sizeof(tok)) == (size_t)-1)
			return -1;
		snprintf(ttl, sizeof(ttl), "%s", title);
		cut_utf8(ttl, 100);
		char ettl[RL_NOTIFY_URL_MAX / 2];
		if (rl_url_encode(ttl, ettl, sizeof(ettl)) == (size_t)-1)
			return -1;
		snprintf(content, sizeof(content), "%s", body);
		memset(out, 0, sizeof(*out));
		out->kind = RL_NB_GET;
		for (;;) {
			if (rl_url_encode(content, enc, sizeof(enc)) != (size_t)-1 &&
			    url(out, "https://www.pushplus.plus/send?token=%s&title=%s&content=%s&template=txt", tok, ettl,
				enc) == 0)
				return 0;
			size_t n = strlen(content);
			if (!n)
				return -1;
			cut_utf8(content, n * 3 / 4);
		}
	}
	default:
		return rl_notify_build(t, c, title, body, now_ms, out);
	}
}

static const char *str_of(json_object *o, const char *const keys[])
{
	json_object *v;
	for (int i = 0; keys[i]; i++)
		if (json_object_object_get_ex(o, keys[i], &v) && json_object_is_type(v, json_type_string))
			return json_object_get_string(v);
	return NULL;
}

int rl_notify_check_response(rl_notify_type t, const char *response, char *err, size_t err_size)
{
	static const char *const desc[] = { "description", "error", NULL };
	static const char *const msg[] = { "errmsg", "msg", "message", "StatusMessage", NULL };
	err[0] = '\0';
	if (t == RL_NT_WEBHOOK || !response || !response[0])
		return 0;
	json_object *o = json_tokener_parse(response), *v;
	if (!o || !json_object_is_type(o, json_type_object)) {
		json_object_put(o);
		return 0; /* not JSON: the HTTP status said it worked */
	}
	int rc = 0;
	const char *text = NULL;
	if (json_object_object_get_ex(o, "ok", &v) && json_object_is_type(v, json_type_boolean) &&
	    !json_object_get_boolean(v)) {
		rc = -1;
		text = str_of(o, desc);
	} else if (json_object_object_get_ex(o, "errcode", &v) && json_object_get_int64(v) != 0) {
		rc = -1;
		text = str_of(o, msg);
		if (!text)
			snprintf(err, err_size, "errcode %" PRId64, json_object_get_int64(v));
	} else if (json_object_object_get_ex(o, "code", &v) &&
		   (json_object_is_type(v, json_type_int) || json_object_is_type(v, json_type_string))) {
		int64_t code = json_object_get_int64(v);
		if (code != 0 && code != 200) {
			rc = -1;
			text = str_of(o, msg);
			if (!text)
				snprintf(err, err_size, "code %" PRId64, code);
		}
	}
	if (rc && text)
		snprintf(err, err_size, "%s", text);
	else if (rc && !err[0])
		snprintf(err, err_size, "the service reported an error");
	json_object_put(o);
	return rc;
}

void rl_notify_test_text(bool zh, const char *router, char *title, size_t title_size, char *body, size_t body_size)
{
	snprintf(title, title_size, "%s", zh ? "RouteLink 测试消息" : "RouteLink test message");
	snprintf(body, body_size, "%s%s%s", zh ? "推送设置正确。" : "Push notifications are set up correctly.",
		 router && router[0] ? "\n" : "", router ? router : "");
}
