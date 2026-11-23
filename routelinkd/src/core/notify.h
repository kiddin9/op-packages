/*
 * Push notices (design §11, P4): what the router says (Chinese or English), merging what happens within a
 * minute into one message, and the HTTP request each channel expects (URL, JSON body, DingTalk and Feishu
 * signatures). Pure: sys/notify sends the request with uclient-fetch.
 */
#ifndef RL_NOTIFY_H
#define RL_NOTIFY_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum {
	RL_NE_DEVICE_NEW,
	RL_NE_DEVICE_ONLINE,  /* watched device */
	RL_NE_DEVICE_OFFLINE, /* watched device */
	RL_NE_QUOTA_WARN,
	RL_NE_QUOTA_EXCEEDED,
	RL_NE_OUTAGE, /* sent after the internet is back, with its duration */
} rl_notify_kind;

typedef struct {
	rl_notify_kind kind;
	int64_t ts;
	char name[64];
	char ip[46];
	char mac[18];
	uint64_t used, limit; /* quota, bytes */
	bool slow_down;       /* quota action: slowed down instead of cut off */
	int64_t duration;     /* outage, seconds */
	const char *cause;    /* outage: "wan_down" | "redial" | "upstream" */
} rl_notify_event;

/* Channel subscriptions (UCI `list events`). */
enum { RL_NS_DEVICE_NEW = 1, RL_NS_DEVICE_WATCH = 2, RL_NS_QUOTA = 4, RL_NS_OUTAGE = 8 };
unsigned rl_notify_sub_parse(const char *s);
/* The subscription an event belongs to. */
unsigned rl_notify_sub_of(rl_notify_kind k);

/*
 * Title and body for n events (n ≥ 1, oldest first): one event gets its own headline, several a summary
 * title and one line each. Output is truncated to the buffers.
 */
void rl_notify_format(const rl_notify_event *ev, int n, const char *router, bool zh, char *title, size_t title_size,
		      char *body, size_t body_size);

/* Events within RL_NOTIFY_MERGE_SEC of the first are sent together. */
#define RL_NOTIFY_MERGE_SEC 60
#define RL_NOTIFY_BATCH_MAX 16
typedef struct {
	rl_notify_event ev[RL_NOTIFY_BATCH_MAX];
	int n;
	int dropped;
} rl_notify_batch;

void rl_notify_batch_add(rl_notify_batch *b, const rl_notify_event *ev);
/* The batch is due once its first event is a minute old. */
bool rl_notify_batch_due(const rl_notify_batch *b, int64_t now);
void rl_notify_batch_clear(rl_notify_batch *b);

typedef enum {
	RL_NT_WEBHOOK,
	RL_NT_BARK,
	RL_NT_SERVERCHAN,
	RL_NT_PUSHPLUS,
	RL_NT_TELEGRAM,
	RL_NT_WECOM,
	RL_NT_DINGTALK,
	RL_NT_FEISHU,
} rl_notify_type;

int rl_notify_type_parse(const char *s);

typedef struct {
	const char *url;
	const char *template; /* webhook */
	const char *token;
	const char *chat_id;
	const char *secret;
} rl_notify_conf;

#define RL_NOTIFY_URL_MAX 1024
#define RL_NOTIFY_BODY_MAX 4096

/* How the body goes out. */
typedef enum {
	RL_NB_JSON, /* POST, Content-Type: application/json */
	RL_NB_FORM, /* POST, application/x-www-form-urlencoded */
	RL_NB_GET,  /* GET, everything in the URL (body empty) */
} rl_notify_body_kind;

typedef struct {
	char url[RL_NOTIFY_URL_MAX];
	char body[RL_NOTIFY_BODY_MAX];
	rl_notify_body_kind kind;
} rl_notify_request;

/* 0, or -1 when the channel is missing what it needs or the result does not fit. now_ms signs requests. */
int rl_notify_build(rl_notify_type t, const rl_notify_conf *c, const char *title, const char *body, int64_t now_ms,
		    rl_notify_request *out);
/*
 * The same for an uclient-fetch without --header (OpenWrt 23.05), which always posts as a form: channels
 * that take a form or a GET get one (Bark, ServerChan, PushPlus, Telegram); the others keep their JSON
 * body and depend on the service not checking the content type.
 */
int rl_notify_build_legacy(rl_notify_type t, const rl_notify_conf *c, const char *title, const char *body,
			   int64_t now_ms, rl_notify_request *out);

/*
 * Checks a 2xx response body for an error the service reports in JSON (errcode, code, ok:false); webhooks
 * are not checked. 0 when fine, else -1 with the service's message in err.
 */
int rl_notify_check_response(rl_notify_type t, const char *response, char *err, size_t err_size);

/* The test message of notify_test. */
void rl_notify_test_text(bool zh, const char *router, char *title, size_t title_size, char *body, size_t body_size);

/* JSON string contents (no quotes). Returns the length, or (size_t)-1 when it does not fit. */
size_t rl_json_escape(const char *in, char *out, size_t size);
/* application/x-www-form-urlencoded style percent-encoding. Returns the length or (size_t)-1. */
size_t rl_url_encode(const char *in, char *out, size_t size);

#endif
