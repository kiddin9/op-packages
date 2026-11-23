#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <syslog.h>
#include <time.h>
#include <unistd.h>

#include <libubox/uloop.h>

#include "sys/daemon.h"
#include "sys/notify.h"
#include "sys/proc.h"

#define FETCH "uclient-fetch"
#define MAX_JOBS 32
#define MAX_RUNNING 4
#define FETCH_TIMEOUT 10 /* uclient-fetch --timeout */
#define GUARD_MS ((RL_NOTIFY_TEST_TIMEOUT - 1) * 1000)
#define TICK_MS 5000

static const int BACKOFF[RL_NOTIFY_RETRIES] = { 10, 60, 300 };

typedef struct {
	char section[64];
	int64_t last_ok, last_error_ts;
	char last_error[160];
} chan_status;

typedef struct job {
	struct rl_notifier *owner;
	char section[64];
	rl_notify_type type;
	rl_notify_request req;
	int attempts;
	int64_t next_try;
	bool running, timed_out;
	rl_notify_done_cb cb; /* notify_test */
	void *ctx;
	struct uloop_process proc;
	struct uloop_timeout guard;
	char out[64];
} job_t;

struct rl_notifier {
	rl_channel *ch;
	chan_status *st;
	size_t n;
	bool zh, hold;
	char router[64];
	rl_notify_batch batch;
	job_t *jobs[MAX_JOBS];
	int n_jobs;
	struct uloop_timeout tick;
	int header; /* uclient-fetch knows --header: -1 not checked yet, 0, 1 */
	unsigned seq;
	rl_notify_refresh_cb refresh;
	void *refresh_ctx;
};

static int64_t now_s(void)
{
	return (int64_t)time(NULL);
}

static int64_t now_ms(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_REALTIME, &ts);
	return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static chan_status *status_of(rl_notifier *n, const char *section)
{
	for (size_t i = 0; i < n->n; i++)
		if (!strcmp(n->st[i].section, section))
			return &n->st[i];
	return NULL;
}

static const rl_channel *channel_of(const rl_notifier *n, const char *section)
{
	for (size_t i = 0; i < n->n; i++)
		if (!strcmp(n->ch[i].section, section))
			return &n->ch[i];
	return NULL;
}

/* OpenWrt 23.05's uclient-fetch has no --header: it always posts as a form. */
static bool has_header_option(rl_notifier *n)
{
	if (n->header < 0) {
		char out[2048];
		const char *argv[] = { FETCH, "--help", NULL };
		rl_proc_run(argv, NULL, 0, out, sizeof(out), 3000);
		n->header = strstr(out, "--header") != NULL;
		if (!n->header)
			syslog(LOG_INFO, "uclient-fetch has no --header: push requests go out as forms where possible");
	}
	return n->header == 1;
}

static void schedule(rl_notifier *n)
{
	if (!n->tick.pending)
		uloop_timeout_set(&n->tick, TICK_MS);
}

/* ---- jobs ---- */

static void read_file(const char *path, char *buf, size_t size)
{
	buf[0] = '\0';
	int fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return;
	ssize_t r = read(fd, buf, size - 1);
	buf[r > 0 ? r : 0] = '\0';
	close(fd);
}

/* The last line of uclient-fetch's messages that says what went wrong. */
static void error_line(const char *msgs, int status, char *err, size_t size)
{
	static const char *const progress[] = { "Downloading", "Connecting", "Writing to", "Download completed",
						"Redirected", NULL };
	err[0] = '\0';
	for (const char *p = msgs; *p;) {
		size_t len = strcspn(p, "\r\n");
		bool skip = len == 0;
		for (int i = 0; progress[i] && !skip; i++)
			skip = !strncmp(p, progress[i], strlen(progress[i]));
		if (!skip)
			snprintf(err, size, "%.*s", (int)len, p);
		p += len;
		p += strspn(p, "\r\n");
	}
	if (!err[0])
		snprintf(err, size, status == 127 ? "uclient-fetch is not installed" : "uclient-fetch exit code %d", status);
}

static void free_job(rl_notifier *n, job_t *j)
{
	for (int i = 0; i < n->n_jobs; i++)
		if (n->jobs[i] == j) {
			memmove(&n->jobs[i], &n->jobs[i + 1], (size_t)(n->n_jobs - i - 1) * sizeof(job_t *));
			n->n_jobs--;
			break;
		}
	free(j);
}

static bool start_job(rl_notifier *n, job_t *j);

static void run_waiting(rl_notifier *n)
{
	int running = 0;
	int64_t now = now_s();
	for (int i = 0; i < n->n_jobs; i++)
		running += n->jobs[i]->running;
	for (int i = 0; i < n->n_jobs && running < MAX_RUNNING; i++) {
		job_t *j = n->jobs[i];
		if (!j->running && j->next_try <= now) {
			if (start_job(n, j))
				running++;
			else
				j->next_try = now + BACKOFF[0]; /* no process now: later */
		}
	}
}

static void finish(rl_notifier *n, job_t *j, bool ok, const char *error)
{
	chan_status *st = status_of(n, j->section);
	int64_t now = now_s();
	if (st) {
		if (ok) {
			st->last_ok = now;
		} else {
			snprintf(st->last_error, sizeof(st->last_error), "%s", error);
			st->last_error_ts = now;
		}
	}
	if (j->cb) {
		j->cb(j->ctx, ok, error);
		free_job(n, j);
		return;
	}
	if (!ok && st && ++j->attempts <= RL_NOTIFY_RETRIES) {
		j->next_try = now + BACKOFF[j->attempts - 1];
		syslog(LOG_NOTICE, "push to %s failed (%s), trying again in %d s", j->section, error,
		       BACKOFF[j->attempts - 1]);
		schedule(n);
		return;
	}
	if (!ok)
		syslog(LOG_WARNING, "push to %s failed: %s", j->section, error);
	free_job(n, j);
}

static void proc_cb(struct uloop_process *p, int ret)
{
	job_t *j = container_of(p, job_t, proc);
	rl_notifier *n = j->owner;
	char body[1024], msgs[1024], err[160], path[80];
	uloop_timeout_cancel(&j->guard);
	j->running = false;
	snprintf(path, sizeof(path), "%s.err", j->out);
	read_file(j->out, body, sizeof(body));
	read_file(path, msgs, sizeof(msgs));
	unlink(j->out);
	unlink(path);
	bool ok = !j->timed_out && WIFEXITED(ret) && WEXITSTATUS(ret) == 0;
	if (j->timed_out)
		snprintf(err, sizeof(err), "no answer within %d s", RL_NOTIFY_TEST_TIMEOUT - 1);
	else if (!ok)
		error_line(msgs, WIFEXITED(ret) ? WEXITSTATUS(ret) : 128 + WTERMSIG(ret), err, sizeof(err));
	else if (rl_notify_check_response(j->type, body, err, sizeof(err)) != 0)
		ok = false;
	finish(n, j, ok, ok ? NULL : err);
	run_waiting(n);
}

static void guard_cb(struct uloop_timeout *t)
{
	job_t *j = container_of(t, job_t, guard);
	j->timed_out = true;
	kill(j->proc.pid, SIGKILL); /* proc_cb follows */
}

static bool start_job(rl_notifier *n, job_t *j)
{
	char timeout[24], post[RL_NOTIFY_BODY_MAX + 16], errpath[80];
	const char *argv[10];
	int k = 0;
	/* in the daemon's own directory: only root writes there, so nobody can plant a symlink */
	mkdir(RL_RUN_DIR, 0755);
	snprintf(j->out, sizeof(j->out), RL_RUN_DIR "/push-%u", ++n->seq);
	snprintf(errpath, sizeof(errpath), "%s.err", j->out);
	snprintf(timeout, sizeof(timeout), "--timeout=%d", FETCH_TIMEOUT);
	argv[k++] = FETCH;
	argv[k++] = timeout;
	argv[k++] = "-O";
	argv[k++] = j->out;
	if (j->req.kind == RL_NB_JSON && n->header == 1)
		argv[k++] = "--header=Content-Type: application/json";
	if (j->req.kind != RL_NB_GET) {
		snprintf(post, sizeof(post), "--post-data=%s", j->req.body);
		argv[k++] = post;
	}
	argv[k++] = j->req.url;
	argv[k] = NULL;

	pid_t pid = fork();
	if (pid < 0) {
		syslog(LOG_WARNING, "cannot start uclient-fetch: %s", strerror(errno));
		return false;
	}
	if (pid == 0) {
		int null = open("/dev/null", O_RDWR);
		int err = open(errpath, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0600);
		if (null >= 0) {
			dup2(null, 0);
			dup2(null, 1);
		}
		if (err >= 0)
			dup2(err, 2);
		long max = sysconf(_SC_OPEN_MAX);
		for (int fd = 3; fd < (max > 0 && max < 4096 ? max : 4096); fd++)
			close(fd);
		signal(SIGPIPE, SIG_DFL);
		execvp(FETCH, (char *const *)argv);
		_exit(127);
	}
	j->running = true;
	j->timed_out = false;
	j->proc.pid = pid;
	j->proc.cb = proc_cb;
	uloop_process_add(&j->proc);
	j->guard.cb = guard_cb;
	uloop_timeout_set(&j->guard, GUARD_MS);
	return true;
}

/* A message for one channel; the oldest waiting retry makes room when the queue is full. */
static job_t *enqueue(rl_notifier *n, const rl_channel *c, const char *title, const char *body)
{
	job_t *j = calloc(1, sizeof(*j));
	if (!j)
		abort();
	rl_notify_conf conf = { .url = c->url, .template = c->tpl, .token = c->token, .chat_id = c->chat_id,
				.secret = c->secret };
	int rc = has_header_option(n) ? rl_notify_build(c->type, &conf, title, body, now_ms(), &j->req)
				      : rl_notify_build_legacy(c->type, &conf, title, body, now_ms(), &j->req);
	j->owner = n;
	j->type = c->type;
	snprintf(j->section, sizeof(j->section), "%s", c->section);
	if (rc != 0) {
		chan_status *st = status_of(n, c->section);
		if (st) {
			snprintf(st->last_error, sizeof(st->last_error), "incomplete settings or message too long");
			st->last_error_ts = now_s();
		}
		free(j);
		return NULL;
	}
	if (n->n_jobs == MAX_JOBS) {
		job_t *drop = NULL;
		for (int i = 0; i < n->n_jobs && !drop; i++)
			if (!n->jobs[i]->running && !n->jobs[i]->cb)
				drop = n->jobs[i];
		if (!drop) {
			free(j);
			return NULL;
		}
		syslog(LOG_WARNING, "push queue full: a message to %s was dropped", drop->section);
		free_job(n, drop);
	}
	n->jobs[n->n_jobs++] = j;
	return j;
}

/* Every enabled channel gets the batch's events it subscribed to, in one message. */
static void flush_batch(rl_notifier *n)
{
	rl_notify_event ev[RL_NOTIFY_BATCH_MAX];
	char title[256], body[2048];
	for (int e = 0; n->refresh && e < n->batch.n; e++)
		n->refresh(n->refresh_ctx, &n->batch.ev[e]);
	for (size_t i = 0; i < n->n; i++) {
		const rl_channel *c = &n->ch[i];
		int k = 0;
		if (!c->enabled)
			continue;
		for (int e = 0; e < n->batch.n; e++)
			if (rl_notify_sub_of(n->batch.ev[e].kind) & c->events)
				ev[k++] = n->batch.ev[e];
		if (!k)
			continue;
		rl_notify_format(ev, k, n->router, n->zh, title, sizeof(title), body, sizeof(body));
		enqueue(n, c, title, body);
	}
	if (n->batch.dropped)
		syslog(LOG_NOTICE, "%d push events did not fit one message", n->batch.dropped);
	rl_notify_batch_clear(&n->batch);
}

static void tick_cb(struct uloop_timeout *t)
{
	rl_notifier *n = container_of(t, rl_notifier, tick);
	int64_t now = now_s();
	/* during an outage the batch waits, but not forever: probes may fail where ICMP is filtered */
	if (rl_notify_batch_due(&n->batch, now) && (!n->hold || now - n->batch.ev[0].ts >= RL_NOTIFY_HOLD_MAX))
		flush_batch(n);
	run_waiting(n);
	if (n->batch.n || n->n_jobs)
		uloop_timeout_set(t, TICK_MS);
}

/* ---- public ---- */

rl_notifier *rl_notifier_new(void)
{
	rl_notifier *n = calloc(1, sizeof(*n));
	if (!n)
		abort();
	n->header = -1;
	n->tick.cb = tick_cb;
	return n;
}

void rl_notifier_free(rl_notifier *n)
{
	if (!n)
		return;
	uloop_timeout_cancel(&n->tick);
	while (n->n_jobs) {
		job_t *j = n->jobs[0];
		if (j->running) {
			uloop_process_delete(&j->proc);
			uloop_timeout_cancel(&j->guard);
			kill(j->proc.pid, SIGKILL);
			waitpid(j->proc.pid, NULL, 0);
			unlink(j->out);
			char path[80];
			snprintf(path, sizeof(path), "%s.err", j->out);
			unlink(path);
		}
		if (j->cb)
			j->cb(j->ctx, false, "the daemon stopped");
		free_job(n, j);
	}
	free(n->ch);
	free(n->st);
	free(n);
}

void rl_notifier_configure(rl_notifier *n, const rl_channel *ch, size_t count, bool zh, const char *router)
{
	chan_status *st = calloc(count ? count : 1, sizeof(*st));
	rl_channel *copy = malloc((count ? count : 1) * sizeof(*copy));
	if (!st || !copy)
		abort();
	memcpy(copy, ch, count * sizeof(*copy));
	for (size_t i = 0; i < count; i++) {
		const chan_status *old = status_of(n, ch[i].section);
		if (old)
			st[i] = *old;
		snprintf(st[i].section, sizeof(st[i].section), "%s", ch[i].section);
	}
	free(n->ch);
	free(n->st);
	n->ch = copy;
	n->st = st;
	n->n = count;
	n->zh = zh;
	snprintf(n->router, sizeof(n->router), "%s", router ? router : "");
}

void rl_notifier_set_refresh(rl_notifier *n, rl_notify_refresh_cb cb, void *ctx)
{
	n->refresh = cb;
	n->refresh_ctx = ctx;
}

bool rl_notifier_wants(const rl_notifier *n, unsigned sub)
{
	for (size_t i = 0; i < n->n; i++)
		if (n->ch[i].enabled && (n->ch[i].events & sub))
			return true;
	return false;
}

void rl_notifier_event(rl_notifier *n, const rl_notify_event *ev)
{
	if (!rl_notifier_wants(n, rl_notify_sub_of(ev->kind)))
		return;
	rl_notify_batch_add(&n->batch, ev);
	schedule(n);
}

void rl_notifier_hold(rl_notifier *n, bool hold)
{
	n->hold = hold;
}

int rl_notifier_test(rl_notifier *n, const char *section, rl_notify_done_cb cb, void *ctx)
{
	const rl_channel *c = channel_of(n, section);
	char title[128], body[256];
	if (!c)
		return -1;
	rl_notify_test_text(n->zh, n->router, title, sizeof(title), body, sizeof(body));
	job_t *j = enqueue(n, c, title, body);
	if (!j) {
		const chan_status *st = status_of(n, section);
		cb(ctx, false, st && st->last_error[0] ? st->last_error : "cannot send now");
		return 0;
	}
	j->cb = cb;
	j->ctx = ctx;
	if (!start_job(n, j)) { /* right away, whatever else runs */
		free_job(n, j);
		cb(ctx, false, "cannot start uclient-fetch");
	}
	return 0;
}

size_t rl_notifier_status(const rl_notifier *n, rl_channel_status *out, size_t max)
{
	size_t k = 0;
	for (size_t i = 0; i < n->n && k < max; i++, k++)
		out[k] = (rl_channel_status){ .section = n->st[i].section,
					      .last_ok = n->st[i].last_ok,
					      .last_error_ts = n->st[i].last_error_ts,
					      .last_error = n->st[i].last_error };
	return k;
}

int rl_notifier_pending(const rl_notifier *n)
{
	int k = n->batch.n;
	for (int i = 0; i < n->n_jobs; i++)
		k += !n->jobs[i]->cb;
	return k;
}
