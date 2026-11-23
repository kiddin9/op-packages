/*
 * Push notices (design §11, P4 plan §0.7): events wait in core/notify's one-minute batch, then every enabled
 * channel gets the ones it subscribed to, in one message, sent by an uclient-fetch child (JSON with
 * --header, or core/notify's form fallback where uclient-fetch has no --header). A failed send is retried 3
 * times (after 10 s, 1 min, 5 min); the last success and failure of each channel are kept for notify_status.
 * While an outage lasts the batch waits (nothing would get out), at most RL_NOTIFY_HOLD_MAX.
 */
#ifndef RL_SYS_NOTIFY_H
#define RL_SYS_NOTIFY_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "core/notify.h"

#define RL_NOTIFY_RETRIES 3
#define RL_NOTIFY_TEST_TIMEOUT 15 /* seconds notify_test waits at most */
#define RL_NOTIFY_HOLD_MAX 600    /* seconds a batch waits for an outage to end */

typedef struct {
	char section[64];
	rl_notify_type type;
	bool enabled;
	char name[64];
	char url[512];
	char tpl[1024];
	char token[256];
	char chat_id[64];
	char secret[160];
	unsigned events; /* RL_NS_* */
} rl_channel;

typedef struct {
	const char *section;
	int64_t last_ok, last_error_ts;
	const char *last_error;
} rl_channel_status;

typedef void (*rl_notify_done_cb)(void *ctx, bool ok, const char *error);

typedef struct rl_notifier rl_notifier;

rl_notifier *rl_notifier_new(void);
/* Running sends are killed; a pending test is answered with an error. */
void rl_notifier_free(rl_notifier *n);
/* Channels (copied), Chinese or English, the router's name in the messages. */
void rl_notifier_configure(rl_notifier *n, const rl_channel *ch, size_t count, bool zh, const char *router);
/* Called for every event when its batch goes out, to fill in names and addresses learnt meanwhile. */
typedef void (*rl_notify_refresh_cb)(void *ctx, rl_notify_event *ev);
void rl_notifier_set_refresh(rl_notifier *n, rl_notify_refresh_cb cb, void *ctx);
/* An enabled channel subscribes to sub (RL_NS_*). */
bool rl_notifier_wants(const rl_notifier *n, unsigned sub);
void rl_notifier_event(rl_notifier *n, const rl_notify_event *ev);
/* An outage is going on: the batch waits. */
void rl_notifier_hold(rl_notifier *n, bool hold);
/* Sends a test message to a channel now; cb gets the outcome within RL_NOTIFY_TEST_TIMEOUT. -1: no such channel. */
int rl_notifier_test(rl_notifier *n, const char *section, rl_notify_done_cb cb, void *ctx);
size_t rl_notifier_status(const rl_notifier *n, rl_channel_status *out, size_t max);
/* Events waiting for their batch plus messages waiting to be sent. */
int rl_notifier_pending(const rl_notifier *n);

#endif
