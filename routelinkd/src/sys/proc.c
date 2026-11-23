#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "sys/proc.h"

static long long mono_ms(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

int rl_proc_run(const char *const argv[], const char *input, size_t input_len, char *out, size_t out_size,
		int timeout_ms)
{
	int in[2], res[2];
	size_t got = 0;
	if (out_size)
		out[0] = '\0';
	if (pipe2(in, O_CLOEXEC) != 0)
		return -1;
	if (pipe2(res, O_CLOEXEC) != 0) {
		close(in[0]);
		close(in[1]);
		return -1;
	}
	pid_t pid = fork();
	if (pid < 0) {
		close(in[0]);
		close(in[1]);
		close(res[0]);
		close(res[1]);
		return -1;
	}
	if (pid == 0) {
		signal(SIGPIPE, SIG_DFL); /* the daemon ignores it; exec would keep that */
		dup2(in[0], 0);
		dup2(res[1], 1);
		dup2(res[1], 2);
		long max = sysconf(_SC_OPEN_MAX);
		for (int fd = 3; fd < (max > 0 && max < 4096 ? max : 4096); fd++)
			close(fd);
		execvp(argv[0], (char *const *)argv);
		_exit(127);
	}
	close(in[0]);
	close(res[1]);
	fcntl(in[1], F_SETFL, O_NONBLOCK);
	fcntl(res[0], F_SETFL, O_NONBLOCK);
	if (!input_len) {
		close(in[1]);
		in[1] = -1;
	}

	long long deadline = mono_ms() + timeout_ms;
	size_t sent = 0;
	bool timed_out = false;
	for (;;) {
		struct pollfd p[2] = { { .fd = res[0], .events = POLLIN }, { .fd = in[1], .events = POLLOUT } };
		long long left = deadline - mono_ms();
		if (left <= 0) {
			timed_out = true;
			break;
		}
		int n = poll(p, in[1] >= 0 ? 2 : 1, (int)left);
		if (n < 0 && errno != EINTR)
			break;
		if (in[1] >= 0 && (p[1].revents & (POLLOUT | POLLERR | POLLHUP))) {
			ssize_t w = write(in[1], input + sent, input_len - sent);
			if (w > 0)
				sent += (size_t)w;
			if ((w < 0 && errno != EAGAIN && errno != EINTR) || sent == input_len) {
				close(in[1]); /* end of the script */
				in[1] = -1;
			}
		}
		if (p[0].revents & (POLLIN | POLLHUP | POLLERR)) {
			char buf[512];
			ssize_t r = read(res[0], buf, sizeof(buf));
			if (r == 0 || (r < 0 && errno != EAGAIN && errno != EINTR))
				break; /* the program closed its output: it is done */
			if (r > 0 && out_size && got < out_size - 1) {
				size_t k = (size_t)r < out_size - 1 - got ? (size_t)r : out_size - 1 - got;
				memcpy(out + got, buf, k);
				got += k;
				out[got] = '\0';
			}
		}
	}
	if (in[1] >= 0)
		close(in[1]);
	close(res[0]);
	int status;
	if (timed_out)
		kill(pid, SIGKILL);
	else {
		/* output closed; give it the rest of the time to exit */
		while (waitpid(pid, &status, WNOHANG) == 0) {
			if (mono_ms() >= deadline) {
				kill(pid, SIGKILL);
				timed_out = true;
				break;
			}
			usleep(2000);
		}
		if (!timed_out)
			return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
	}
	while (waitpid(pid, &status, 0) < 0 && errno == EINTR)
		;
	return -1;
}

void rl_proc_first_line(const char *s, char *line, size_t size)
{
	if (!size)
		return;
	line[0] = '\0';
	while (*s) {
		size_t n = strcspn(s, "\n");
		if (n) {
			snprintf(line, size, "%.*s", (int)n, s);
			return;
		}
		s++;
	}
}
