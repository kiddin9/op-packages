#define _GNU_SOURCE
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <syslog.h>
#include <unistd.h>

#include <libubox/uloop.h>

#include "core/version.h"
#include "sys/daemon.h"

static rl_daemon daemon_state;
static int hup_pipe[2] = { -1, -1 };
static struct uloop_fd hup_fd;

static void on_sighup(int sig)
{
	(void)sig;
	char c = 1;
	if (write(hup_pipe[1], &c, 1) < 0) {
		/* pipe full: a reload is already pending */
	}
}

static void hup_cb(struct uloop_fd *fd, unsigned int events)
{
	char buf[16];
	while (read(fd->fd, buf, sizeof(buf)) > 0)
		;
	rl_daemon_reload(&daemon_state);
}

static void usage(void)
{
	fprintf(stderr, "routelinkd %s\nusage: routelinkd [-v] [-V]\n  -v  log debug messages\n  -V  print version\n",
		rl_version());
}

int main(int argc, char **argv)
{
	int opt, level = LOG_INFO;
	while ((opt = getopt(argc, argv, "vVh")) != -1) {
		switch (opt) {
		case 'v':
			level = LOG_DEBUG;
			break;
		case 'V':
			printf("%s\n", rl_version());
			return 0;
		default:
			usage();
			return opt == 'h' ? 0 : 2;
		}
	}
	openlog("routelinkd", LOG_PID, LOG_DAEMON);
	setlogmask(LOG_UPTO(level));

	uloop_init();
	if (pipe2(hup_pipe, O_NONBLOCK | O_CLOEXEC) == 0) {
		hup_fd.fd = hup_pipe[0];
		hup_fd.cb = hup_cb;
		uloop_fd_add(&hup_fd, ULOOP_READ);
		signal(SIGHUP, on_sighup);
	}
	signal(SIGPIPE, SIG_IGN);

	if (rl_daemon_init(&daemon_state) != 0) {
		syslog(LOG_ERR, "start-up failed");
		return 1;
	}
	uloop_run(); /* returns on SIGTERM / SIGINT */
	rl_daemon_shutdown(&daemon_state);
	uloop_done();
	return 0;
}
