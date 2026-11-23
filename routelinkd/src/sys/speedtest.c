#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <netdb.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <syslog.h>
#include <time.h>
#include <unistd.h>

#include <libubox/uloop.h>

#include "sys/daemon.h"
#include "sys/speedtest.h"

#define FETCH "/bin/uclient-fetch"
#define UPLOAD_FILE RL_RUN_DIR "/speedtest.bin" /* RAM; only root writes there */
#define UPLOAD_MAX (8 << 20)
#define UPLOAD_MIN (256 << 10)
#define UPLOAD_TLS (48 << 10)
#define SAMPLE_MS 200
#define CONNECT_TIMEOUT_MS 2000
#define MAX_STREAMS 8

struct rl_speedtest {
	char path[256];
	rl_speed_log log;
	bool running;
	rl_speed_run run;
	rl_speed_result result; /* of the running test, filled from its lines */
	struct uloop_process proc;
	struct uloop_fd fd;
	struct uloop_timeout guard;
	char buf[512];
	size_t len;
};

/* ---- the test process ---- */

static int64_t mono_us(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (int64_t)ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
}

/* One line to the daemon. */
static void say(int out, const char *fmt, ...)
{
	char line[256];
	va_list ap;
	va_start(ap, fmt);
	int n = vsnprintf(line, sizeof(line) - 1, fmt, ap);
	va_end(ap);
	if (n < 0)
		return;
	if (n > (int)sizeof(line) - 2)
		n = (int)sizeof(line) - 2;
	line[n++] = '\n';
	if (write(out, line, (size_t)n) < 0) {
		/* the daemon is gone: the test is killed with it anyway */
	}
}

static bool read_u64(const char *path, uint64_t *v)
{
	FILE *f = fopen(path, "r");
	if (!f)
		return false;
	bool ok = fscanf(f, "%" SCNu64, v) == 1;
	fclose(f);
	return ok;
}

/* Sum of the WAN devices' rx (or tx) byte counters. */
static bool wan_bytes(const rl_speed_params *p, bool tx, uint64_t *out)
{
	char path[128];
	bool any = false;
	*out = 0;
	for (int i = 0; i < p->n_wan; i++) {
		uint64_t v;
		snprintf(path, sizeof(path), "/sys/class/net/%s/statistics/%s", p->wan_devs[i], tx ? "tx_bytes" : "rx_bytes");
		if (read_u64(path, &v)) {
			*out += v;
			any = true;
		}
	}
	return any;
}

/* Milliseconds of one TCP handshake, -1 when it failed. */
static double connect_ms(const struct addrinfo *ai)
{
	int fd = socket(ai->ai_family, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
	if (fd < 0)
		return -1;
	int64_t t0 = mono_us();
	int rc = connect(fd, ai->ai_addr, ai->ai_addrlen);
	if (rc != 0 && errno == EINPROGRESS) {
		struct pollfd pfd = { .fd = fd, .events = POLLOUT };
		int err = 0;
		socklen_t len = sizeof(err);
		rc = poll(&pfd, 1, CONNECT_TIMEOUT_MS) == 1 && getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len) == 0 &&
				     err == 0
			     ? 0
			     : -1;
	}
	double ms = (double)(mono_us() - t0) / 1000.0;
	close(fd);
	return rc == 0 ? ms : -1;
}

/* uclient-fetch downloading url to /dev/null, or posting post_file to it. */
static pid_t spawn_fetch(const char *url, const char *post_file)
{
	pid_t pid = fork();
	if (pid != 0)
		return pid;
	int null = open("/dev/null", O_RDWR);
	if (null >= 0) {
		dup2(null, 0);
		dup2(null, 1);
		dup2(null, 2);
	}
	long max = sysconf(_SC_OPEN_MAX);
	for (int fd = 3; fd < (max > 0 && max < 4096 ? max : 4096); fd++)
		close(fd); /* the daemon's sockets */
	char post[RL_SPEED_URL_LEN + 16];
	char *argv[8];
	int n = 0;
	argv[n++] = (char *)"uclient-fetch";
	argv[n++] = (char *)"-q";
	argv[n++] = (char *)"--no-check-certificate"; /* only throughput is measured; no CA bundle needed */
	argv[n++] = (char *)"-O";
	argv[n++] = (char *)"/dev/null";
	if (post_file) {
		snprintf(post, sizeof(post), "--post-file=%s", post_file);
		argv[n++] = post;
	}
	argv[n++] = (char *)url;
	argv[n] = NULL;
	execv(FETCH, argv);
	execvp("uclient-fetch", argv);
	_exit(127);
}

/*
 * streams parallel transfers for duration seconds, restarting the ones that finish; the rate comes from the
 * WAN counter (rx for downloads, tx for uploads). -1 with err set when it failed.
 */
static int64_t transfer(const rl_speed_params *p, const char *url, const char *post_file, int out,
			rl_speed_phase phase, double p0, double p1, char *err, size_t errlen)
{
	int streams = p->streams < 1 ? 1 : p->streams > MAX_STREAMS ? MAX_STREAMS : p->streams;
	pid_t pids[MAX_STREAMS];
	int ok = 0, failed = 0, status = 0, cap = p->duration * 1000 / SAMPLE_MS + 4, ns = 0;
	int64_t *t = calloc((size_t)cap, sizeof(int64_t));
	uint64_t *bytes = calloc((size_t)cap, sizeof(uint64_t));
	if (!t || !bytes)
		abort();
	for (int i = 0; i < streams; i++)
		pids[i] = spawn_fetch(url, post_file);
	int64_t t0 = mono_us(), end = t0 + (int64_t)p->duration * 1000000;
	for (int64_t tick = t0;; tick += SAMPLE_MS * 1000) {
		int64_t now = mono_us();
		uint64_t c;
		if (ns < cap && wan_bytes(p, post_file != NULL, &c)) {
			t[ns] = (now - t0) / 1000;
			bytes[ns++] = c;
		}
		if (now >= end)
			break;
		for (int i = 0; i < streams; i++) {
			int st;
			if (pids[i] <= 0 || waitpid(pids[i], &st, WNOHANG) != pids[i])
				continue;
			if (WIFEXITED(st) && WEXITSTATUS(st) == 0) {
				ok++;
			} else {
				failed++;
				status = WIFEXITED(st) ? WEXITSTATUS(st) : 128 + WTERMSIG(st);
			}
			pids[i] = -1;
		}
		if (!ok && failed >= 3 * streams) {
			snprintf(err, errlen, "%s failed (uclient-fetch exit code %d)", rl_speed_phase_name(phase), status);
			break;
		}
		for (int i = 0; i < streams; i++)
			if (pids[i] <= 0)
				pids[i] = spawn_fetch(url, post_file);
		say(out, "P %s %.3f", rl_speed_phase_name(phase), p0 + (p1 - p0) * (double)(now - t0) / (double)(end - t0));
		int64_t sleep_us = tick + SAMPLE_MS * 1000 - mono_us();
		if (sleep_us > 0)
			usleep((useconds_t)sleep_us);
	}
	for (int i = 0; i < streams; i++)
		if (pids[i] > 0)
			kill(pids[i], SIGKILL);
	for (int i = 0; i < streams; i++)
		if (pids[i] > 0)
			waitpid(pids[i], NULL, 0);
	int64_t rate = err[0] ? -1 : rl_speed_rate(t, bytes, ns, RL_SPEED_WARMUP_MS);
	if (!err[0] && rate < 0)
		snprintf(err, errlen, "no WAN byte counters");
	free(t);
	free(bytes);
	return rate;
}

/* MemAvailable in bytes, 0 when unknown. */
static uint64_t mem_available(void)
{
	char line[128];
	uint64_t kb = 0;
	FILE *f = fopen("/proc/meminfo", "r");
	if (!f)
		return 0;
	while (fgets(line, sizeof(line), f))
		if (sscanf(line, "MemAvailable: %" SCNu64 " kB", &kb) == 1)
			break;
	fclose(f);
	return kb * 1024;
}

/*
 * Incompressible upload data in /tmp (RAM): 8 MB or a 64th of the available memory, whichever is less.
 * uclient-fetch sends a file as a chunked body and queues all of it in memory, so each stream holds a copy.
 * Over TLS it loses what does not fit its stream buffers (the upload stalls), so HTTPS posts stay small.
 */
static bool make_upload_file(bool tls)
{
	uint64_t size = mem_available() / 64;
	if (size > UPLOAD_MAX || size == 0)
		size = size ? UPLOAD_MAX : UPLOAD_MIN;
	if (size < UPLOAD_MIN)
		size = UPLOAD_MIN;
	if (tls)
		size = UPLOAD_TLS;
	mkdir(RL_RUN_DIR, 0755);
	int fd = open(UPLOAD_FILE, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW, 0600);
	if (fd < 0)
		return false;
	uint64_t x = (uint64_t)mono_us() | 1, buf[8192];
	bool ok = true;
	for (uint64_t done = 0; ok && done < size; done += sizeof(buf)) {
		for (size_t i = 0; i < 8192; i++) {
			x ^= x << 13; /* xorshift64 */
			x ^= x >> 7;
			x ^= x << 17;
			buf[i] = x;
		}
		size_t k = size - done < sizeof(buf) ? (size_t)(size - done) : sizeof(buf);
		ok = write(fd, buf, k) == (ssize_t)k;
	}
	close(fd);
	return ok;
}

static bool have_tls(void)
{
	return access("/lib/libustream-ssl.so", F_OK) == 0 || access("/usr/lib/libustream-ssl.so", F_OK) == 0;
}

static void child_main(const rl_speed_params *p, int out)
{
	static const int sigs[] = { SIGCHLD, SIGTERM, SIGINT, SIGHUP };
	for (size_t i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++)
		signal(sigs[i], SIG_DFL); /* uloop's handlers would wake the daemon */
	setpgid(0, 0);

	rl_speed_target tg;
	if (!rl_speed_target_of(p->server, &tg)) {
		say(out, "E invalid server URL");
		_exit(1);
	}
	say(out, "P latency 0");
	struct addrinfo hints = { .ai_socktype = SOCK_STREAM }, *res = NULL;
	char port[8];
	snprintf(port, sizeof(port), "%d", tg.port);
	if (getaddrinfo(tg.host, port, &hints, &res) != 0 || !res) {
		say(out, "E cannot resolve %s", tg.host);
		_exit(1);
	}
	/* the first address that answers, then always that one */
	const struct addrinfo *ai = NULL;
	double ms[RL_SPEED_PINGS];
	int n = 0;
	for (int i = 0; i < RL_SPEED_PINGS; i++) {
		double v = -1;
		for (const struct addrinfo *a = ai ? ai : res; a && v < 0; a = ai ? NULL : a->ai_next)
			if ((v = connect_ms(a)) >= 0)
				ai = a;
		if (v >= 0)
			ms[n++] = v;
		say(out, "P latency %.3f", 0.1 * (i + 1) / RL_SPEED_PINGS);
	}
	freeaddrinfo(res);
	if (!n) {
		say(out, "E cannot connect to %s port %d", tg.host, tg.port);
		_exit(1);
	}
	double median, jitter;
	rl_speed_stats(ms, n, &median, &jitter);
	say(out, "L %.3f %.3f", median, jitter);

	char err[128] = "";
	if (!p->n_wan) {
		say(out, "E no WAN interface is up");
		_exit(1);
	}
	if (!strncasecmp(tg.down, "https:", 6) && !have_tls()) {
		say(out, "E HTTPS needs a libustream-ssl package (libustream-mbedtls, -openssl or -wolfssl)");
		_exit(1);
	}
	int64_t down = transfer(p, tg.down, NULL, out, RL_SPEED_DOWNLOAD, 0.1, 0.55, err, sizeof(err));
	if (down < 0) {
		say(out, "E %s", err);
		_exit(1);
	}
	say(out, "D %" PRId64, down);
	say(out, "P upload 0.55");
	if (!make_upload_file(!strncasecmp(tg.up, "https:", 6))) {
		unlink(UPLOAD_FILE);
		say(out, "E cannot write %s", UPLOAD_FILE);
		_exit(1);
	}
	int64_t up = transfer(p, tg.up, UPLOAD_FILE, out, RL_SPEED_UPLOAD, 0.55, 1.0, err, sizeof(err));
	unlink(UPLOAD_FILE);
	if (up < 0) {
		say(out, "E %s", err);
		_exit(1);
	}
	say(out, "U %" PRId64, up);
	_exit(0);
}

/* ---- the daemon's side ---- */

static void read_lines(rl_speedtest *s)
{
	for (;;) {
		ssize_t n = read(s->fd.fd, s->buf + s->len, sizeof(s->buf) - 1 - s->len);
		if (n <= 0)
			return;
		s->len += (size_t)n;
		s->buf[s->len] = '\0';
		char *line = s->buf, *nl;
		while ((nl = strchr(line, '\n'))) {
			*nl = '\0';
			if (!rl_speed_line(line, &s->result, &s->run.phase, &s->run.progress))
				syslog(LOG_DEBUG, "speed test: unexpected line '%s'", line);
			line = nl + 1;
		}
		s->len = strlen(line);
		memmove(s->buf, line, s->len);
		if (s->len == sizeof(s->buf) - 1)
			s->len = 0; /* a line that long is garbage */
	}
}

static void close_pipe(rl_speedtest *s)
{
	if (s->fd.fd < 0)
		return;
	uloop_fd_delete(&s->fd);
	close(s->fd.fd);
	s->fd.fd = -1;
}

static void fd_cb(struct uloop_fd *fd, unsigned int events)
{
	rl_speedtest *s = container_of(fd, rl_speedtest, fd);
	read_lines(s);
	if (fd->eof || fd->error)
		close_pipe(s); /* the process callback records the result */
}

static void proc_cb(struct uloop_process *p, int ret)
{
	rl_speedtest *s = container_of(p, rl_speedtest, proc);
	rl_speed_result *r = &s->result;
	if (s->fd.fd >= 0)
		read_lines(s);
	close_pipe(s);
	uloop_timeout_cancel(&s->guard);
	unlink(UPLOAD_FILE);
	if (!r->error[0] && (r->down_bps < 0 || r->up_bps < 0))
		snprintf(r->error, sizeof(r->error), "the test process ended unexpectedly");
	s->run.phase = r->error[0] ? RL_SPEED_FAILED : RL_SPEED_DONE;
	s->run.progress = 1;
	s->running = false;
	rl_speed_log_add(&s->log, r);
	if (rl_speed_log_save(&s->log, s->path) != 0)
		syslog(LOG_WARNING, "cannot write %s: %s", s->path, strerror(errno));
	if (r->error[0])
		syslog(LOG_NOTICE, "speed test %d failed: %s", r->id, r->error);
	else
		syslog(LOG_INFO, "speed test %d: %.1f ms, down %" PRId64 " bit/s, up %" PRId64 " bit/s", r->id,
		       r->latency_ms, r->down_bps, r->up_bps);
}

static void guard_cb(struct uloop_timeout *t)
{
	rl_speedtest *s = container_of(t, rl_speedtest, guard);
	snprintf(s->result.error, sizeof(s->result.error), "the test did not finish in time");
	kill(-s->proc.pid, SIGKILL); /* the process callback follows */
}

rl_speedtest *rl_speedtest_open(const char *path)
{
	rl_speedtest *s = calloc(1, sizeof(*s));
	if (!s)
		abort();
	snprintf(s->path, sizeof(s->path), "%s", path);
	if (rl_speed_log_load(&s->log, path) != 0)
		syslog(LOG_WARNING, "damaged %s was replaced", path);
	s->fd.fd = -1;
	s->fd.cb = fd_cb;
	s->proc.cb = proc_cb;
	s->guard.cb = guard_cb;
	return s;
}

void rl_speedtest_close(rl_speedtest *s)
{
	if (!s)
		return;
	if (s->running) {
		uloop_process_delete(&s->proc);
		uloop_timeout_cancel(&s->guard);
		kill(-s->proc.pid, SIGKILL);
		waitpid(s->proc.pid, NULL, 0);
		close_pipe(s);
		unlink(UPLOAD_FILE);
	}
	rl_speed_log_free(&s->log);
	free(s);
}

int rl_speedtest_start(rl_speedtest *s, const rl_speed_params *p, int64_t now, bool *already)
{
	int fds[2];
	*already = s->running;
	if (s->running)
		return s->run.id;
	if (pipe2(fds, O_CLOEXEC) != 0)
		return -1;
	pid_t pid = fork();
	if (pid < 0) {
		close(fds[0]);
		close(fds[1]);
		return -1;
	}
	if (pid == 0) {
		close(fds[0]);
		child_main(p, fds[1]);
		_exit(1);
	}
	setpgid(pid, pid); /* also in the child: whichever runs first; the group is killed as a whole */
	close(fds[1]);
	int id = s->log.last_id + 1;
	s->log.last_id = id;
	rl_speed_result_init(&s->result, id, now, p->server);
	s->run = (rl_speed_run){ .id = id, .phase = RL_SPEED_LATENCY, .progress = 0 };
	s->running = true;
	s->len = 0;
	fcntl(fds[0], F_SETFL, fcntl(fds[0], F_GETFL) | O_NONBLOCK);
	s->fd.fd = fds[0];
	uloop_fd_add(&s->fd, ULOOP_READ);
	s->proc.pid = pid;
	uloop_process_add(&s->proc);
	uloop_timeout_set(&s->guard, (60 + 3 * p->duration) * 1000);
	syslog(LOG_INFO, "speed test %d started (%s, %d streams, %d s)", id, p->server[0] ? p->server : "Cloudflare",
	       p->streams, p->duration);
	return id;
}

const rl_speed_run *rl_speedtest_current(const rl_speedtest *s)
{
	return s->running ? &s->run : NULL;
}

const rl_speed_log *rl_speedtest_log(const rl_speedtest *s)
{
	return &s->log;
}
