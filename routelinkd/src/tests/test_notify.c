#include "t.h"

#include "core/notify.h"

static rl_notify_event ev(rl_notify_kind k, int64_t ts, const char *name)
{
	rl_notify_event e = { .kind = k, .ts = ts };
	snprintf(e.name, sizeof(e.name), "%s", name);
	snprintf(e.ip, sizeof(e.ip), "192.168.1.23");
	snprintf(e.mac, sizeof(e.mac), "AA:BB:CC:DD:EE:01");
	return e;
}

static void test_subscriptions(void)
{
	T_EQ_U64(rl_notify_sub_parse("quota"), RL_NS_QUOTA);
	T_EQ_U64(rl_notify_sub_parse("nope"), 0);
	T_EQ_U64(rl_notify_sub_of(RL_NE_DEVICE_OFFLINE), RL_NS_DEVICE_WATCH);
	T_EQ_U64(rl_notify_sub_of(RL_NE_OUTAGE), RL_NS_OUTAGE);
	T_EQ_I64(rl_notify_type_parse("feishu"), RL_NT_FEISHU);
	T_EQ_I64(rl_notify_type_parse("x"), -1);
}

static void test_format_single(void)
{
	char title[128], body[512];
	rl_notify_event e = ev(RL_NE_DEVICE_NEW, 0, "iPhone");
	rl_notify_format(&e, 1, "家里", true, title, sizeof(title), body, sizeof(body));
	T_EQ_STR(title, "新设备接入：iPhone");
	T_EQ_STR(body, "192.168.1.23 · AA:BB:CC:DD:EE:01\n家里");

	e = ev(RL_NE_QUOTA_WARN, 0, "TV");
	e.used = 85ull << 30;
	e.limit = 100ull << 30;
	rl_notify_format(&e, 1, "Home", false, title, sizeof(title), body, sizeof(body));
	T_EQ_STR(title, "TV has used 85% of its data");
	T_EQ_STR(body, "85.0 GB of 100.0 GB this period\nHome");

	e = ev(RL_NE_OUTAGE, 0, "");
	e.duration = 200;
	e.cause = "redial";
	rl_notify_format(&e, 1, "", true, title, sizeof(title), body, sizeof(body));
	T_EQ_STR(title, "网络已恢复");
	T_EQ_STR(body, "断网 3 分 20 秒，原因：重新拨号");

	e = ev(RL_NE_QUOTA_EXCEEDED, 0, "Switch");
	e.slow_down = true;
	rl_notify_format(&e, 1, "", false, title, sizeof(title), body, sizeof(body));
	T_EQ_STR(body, "Slowed down; let it through in the app");
}

static void test_format_merged_and_truncated(void)
{
	char title[64], body[512], tiny[24];
	rl_notify_event e[2] = { ev(RL_NE_DEVICE_ONLINE, 0, "NAS"), ev(RL_NE_DEVICE_OFFLINE, 5, "iPad") };
	rl_notify_format(e, 2, "Home", false, title, sizeof(title), body, sizeof(body));
	T_EQ_STR(title, "Home: 2 notices");
	T_EQ_STR(body, "NAS is online (192.168.1.23)\niPad went offline (192.168.1.23)");
	rl_notify_format(e, 2, "Home", false, title, sizeof(title), tiny, sizeof(tiny));
	T_EQ_U64(strlen(tiny), sizeof(tiny) - 1);
}

static void test_batch(void)
{
	rl_notify_batch b = { 0 };
	T_ASSERT(!rl_notify_batch_due(&b, 1000));
	rl_notify_event e = ev(RL_NE_DEVICE_NEW, 1000, "a");
	rl_notify_batch_add(&b, &e);
	T_ASSERT(!rl_notify_batch_due(&b, 1059));
	T_ASSERT(rl_notify_batch_due(&b, 1060));
	for (int i = 0; i < 20; i++)
		rl_notify_batch_add(&b, &e);
	T_EQ_I64(b.n, RL_NOTIFY_BATCH_MAX);
	T_EQ_I64(b.dropped, 5);
	rl_notify_batch_clear(&b);
	T_EQ_I64(b.n, 0);
}

static void test_escape(void)
{
	char out[64];
	T_EQ_U64(rl_json_escape("a\"b\\c\nd\x01", out, sizeof(out)), strlen("a\\\"b\\\\c\\nd\\u0001"));
	T_EQ_STR(out, "a\\\"b\\\\c\\nd\\u0001");
	T_EQ_U64(rl_json_escape("abcdef", out, 4), (size_t)-1);
	T_EQ_STR((rl_url_encode("a+b/c= ~", out, sizeof(out)), out), "a%2Bb%2Fc%3D%20~");
}

static void test_requests(void)
{
	rl_notify_request r;
	rl_notify_conf c = { 0 };

	c.url = "https://hooks.example/x";
	T_EQ_I64(rl_notify_build(RL_NT_WEBHOOK, &c, "T\"", "B", 0, &r), 0);
	T_EQ_STR(r.body, "{\"title\":\"T\\\"\",\"body\":\"B\"}");
	c.template = "{\"text\":\"{title}: {body}\",\"x\":1}";
	T_EQ_I64(rl_notify_build(RL_NT_WEBHOOK, &c, "T", "line1\nline2", 0, &r), 0);
	T_EQ_STR(r.body, "{\"text\":\"T: line1\\nline2\",\"x\":1}");

	memset(&c, 0, sizeof(c));
	T_EQ_I64(rl_notify_build(RL_NT_BARK, &c, "T", "B", 0, &r), -1);
	c.token = "key123";
	c.url = "https://bark.example/";
	T_EQ_I64(rl_notify_build(RL_NT_BARK, &c, "T", "B", 0, &r), 0);
	T_EQ_STR(r.url, "https://bark.example/push");
	T_EQ_STR(r.body, "{\"device_key\":\"key123\",\"title\":\"T\",\"body\":\"B\",\"group\":\"RouteLink\"}");

	memset(&c, 0, sizeof(c));
	c.token = "SCT12345abc";
	rl_notify_build(RL_NT_SERVERCHAN, &c, "T", "B", 0, &r);
	T_EQ_STR(r.url, "https://sctapi.ftqq.com/SCT12345abc.send");
	c.token = "sctp4321tABCD";
	rl_notify_build(RL_NT_SERVERCHAN, &c, "T", "B", 0, &r);
	T_EQ_STR(r.url, "https://4321.push.ft07.com/send/sctp4321tABCD.send");

	memset(&c, 0, sizeof(c));
	c.token = "123:abc";
	T_EQ_I64(rl_notify_build(RL_NT_TELEGRAM, &c, "T", "B", 0, &r), -1); /* no chat id */
	c.chat_id = "-100200";
	T_EQ_I64(rl_notify_build(RL_NT_TELEGRAM, &c, "T", "B", 0, &r), 0);
	T_EQ_STR(r.url, "https://api.telegram.org/bot123:abc/sendMessage");
	T_EQ_STR(r.body, "{\"chat_id\":\"-100200\",\"text\":\"T\\nB\"}");

	memset(&c, 0, sizeof(c));
	c.url = "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=k";
	rl_notify_build(RL_NT_WECOM, &c, "T", "B", 0, &r);
	T_EQ_STR(r.body, "{\"msgtype\":\"text\",\"text\":{\"content\":\"T\\nB\"}}");
	T_EQ_I64(r.kind, RL_NB_JSON);
}

/* Signatures checked against Python's hmac/base64 for the same inputs. */
static void test_signed_requests(void)
{
	rl_notify_request r;
	rl_notify_conf c = { .url = "https://oapi.dingtalk.com/robot/send?access_token=t", .secret = "SECabc123" };
	T_EQ_I64(rl_notify_build(RL_NT_DINGTALK, &c, "T", "B", 1790000000123, &r), 0);
	T_EQ_STR(r.url, "https://oapi.dingtalk.com/robot/send?access_token=t&timestamp=1790000000123"
			"&sign=01gS3Mla3BkNVPYosr3l%2FbSyAGG7pJzGf0byvjVcsbM%3D");

	c.url = "https://open.feishu.cn/open-apis/bot/v2/hook/x";
	T_EQ_I64(rl_notify_build(RL_NT_FEISHU, &c, "T", "B", 1790000000123, &r), 0);
	T_EQ_STR(r.body, "{\"timestamp\":\"1790000000\",\"sign\":\"Ks57E9grcZK803pkhDIHdFQnUd9ov8D6HyF7poblyYc=\","
			 "\"msg_type\":\"text\",\"content\":{\"text\":\"T\\nB\"}}");
	c.secret = NULL;
	rl_notify_build(RL_NT_FEISHU, &c, "T", "B", 0, &r);
	T_EQ_STR(r.body, "{\"msg_type\":\"text\",\"content\":{\"text\":\"T\\nB\"}}");
}

/* uclient-fetch without --header (23.05): forms and GETs where the service takes them. */
static void test_legacy_requests(void)
{
	rl_notify_request r;
	rl_notify_conf c = { .token = "k/1", .url = "https://bark.example/" };
	T_EQ_I64(rl_notify_build_legacy(RL_NT_BARK, &c, "T", "a b&c", 0, &r), 0);
	T_EQ_I64(r.kind, RL_NB_FORM);
	T_EQ_STR(r.url, "https://bark.example/k%2F1");
	T_EQ_STR(r.body, "title=T&body=a%20b%26c&group=RouteLink");

	memset(&c, 0, sizeof(c));
	c.token = "SCT1";
	T_EQ_I64(rl_notify_build_legacy(RL_NT_SERVERCHAN, &c, "T", "B\n2", 0, &r), 0);
	T_EQ_I64(r.kind, RL_NB_FORM);
	T_EQ_STR(r.url, "https://sctapi.ftqq.com/SCT1.send");
	T_EQ_STR(r.body, "title=T&desp=B%0A2");

	memset(&c, 0, sizeof(c));
	c.token = "1:a";
	c.chat_id = "-5";
	T_EQ_I64(rl_notify_build_legacy(RL_NT_TELEGRAM, &c, "T", "B", 0, &r), 0);
	T_EQ_STR(r.body, "chat_id=-5&text=T%0AB");

	memset(&c, 0, sizeof(c));
	c.token = "tok";
	T_EQ_I64(rl_notify_build_legacy(RL_NT_PUSHPLUS, &c, "标题", "B", 0, &r), 0);
	T_EQ_I64(r.kind, RL_NB_GET);
	T_EQ_STR(r.body, "");
	T_EQ_STR(r.url, "https://www.pushplus.plus/send?token=tok&title=%E6%A0%87%E9%A2%98&content=B&template=txt");
	/* too long for a URL: shortened on a character boundary */
	char body[2000] = "";
	for (int i = 0; i < 300; i++)
		strcat(body, "流");
	T_EQ_I64(rl_notify_build_legacy(RL_NT_PUSHPLUS, &c, "T", body, 0, &r), 0);
	T_ASSERT(strlen(r.url) < RL_NOTIFY_URL_MAX);
	T_ASSERT(strstr(r.url, "%E6%B5%81&template=txt") != NULL);

	/* the rest keep JSON */
	memset(&c, 0, sizeof(c));
	c.url = "https://qyapi.weixin.qq.com/x";
	T_EQ_I64(rl_notify_build_legacy(RL_NT_WECOM, &c, "T", "B", 0, &r), 0);
	T_EQ_I64(r.kind, RL_NB_JSON);
	T_EQ_STR(r.body, "{\"msgtype\":\"text\",\"text\":{\"content\":\"T\\nB\"}}");
}

static void test_responses(void)
{
	char err[128];
	T_EQ_I64(rl_notify_check_response(RL_NT_DINGTALK, "{\"errcode\":0,\"errmsg\":\"ok\"}", err, sizeof(err)), 0);
	T_EQ_I64(rl_notify_check_response(RL_NT_DINGTALK, "{\"errcode\":310000,\"errmsg\":\"sign not match\"}", err,
					  sizeof(err)),
		 -1);
	T_EQ_STR(err, "sign not match");
	T_EQ_I64(rl_notify_check_response(RL_NT_BARK, "{\"code\":200,\"message\":\"success\"}", err, sizeof(err)), 0);
	T_EQ_I64(rl_notify_check_response(RL_NT_SERVERCHAN, "{\"code\":0,\"message\":\"\",\"data\":{}}", err, sizeof(err)),
		 0);
	T_EQ_I64(rl_notify_check_response(RL_NT_PUSHPLUS, "{\"code\":903,\"msg\":\"无效的用户token\"}", err, sizeof(err)), -1);
	T_EQ_STR(err, "无效的用户token");
	T_EQ_I64(rl_notify_check_response(RL_NT_FEISHU, "{\"code\":19021}", err, sizeof(err)), -1);
	T_EQ_STR(err, "code 19021");
	T_EQ_I64(rl_notify_check_response(RL_NT_TELEGRAM, "{\"ok\":false,\"description\":\"chat not found\"}", err,
					  sizeof(err)),
		 -1);
	T_EQ_STR(err, "chat not found");
	T_EQ_I64(rl_notify_check_response(RL_NT_TELEGRAM, "{\"ok\":true,\"result\":{}}", err, sizeof(err)), 0);
	/* webhooks, and bodies that are not JSON, only count the HTTP status */
	T_EQ_I64(rl_notify_check_response(RL_NT_WEBHOOK, "{\"code\":1}", err, sizeof(err)), 0);
	T_EQ_I64(rl_notify_check_response(RL_NT_WECOM, "OK", err, sizeof(err)), 0);
	T_EQ_I64(rl_notify_check_response(RL_NT_WECOM, "", err, sizeof(err)), 0);

	char title[64], body[128];
	rl_notify_test_text(true, "Home", title, sizeof(title), body, sizeof(body));
	T_EQ_STR(title, "RouteLink 测试消息");
	T_EQ_STR(body, "推送设置正确。\nHome");
	rl_notify_test_text(false, "", title, sizeof(title), body, sizeof(body));
	T_EQ_STR(body, "Push notifications are set up correctly.");
}

int main(void)
{
	T_RUN(test_subscriptions);
	T_RUN(test_format_single);
	T_RUN(test_format_merged_and_truncated);
	T_RUN(test_batch);
	T_RUN(test_escape);
	T_RUN(test_requests);
	T_RUN(test_signed_requests);
	T_RUN(test_legacy_requests);
	T_RUN(test_responses);
	T_DONE();
}
