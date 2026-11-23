/* Short helper programs (tc, nft) run synchronously: a script on stdin, stdout and stderr captured. */
#ifndef RL_PROC_H
#define RL_PROC_H

#include <stddef.h>

/*
 * Runs argv[0] (looked up in PATH) with input on its stdin; out receives stdout and stderr (NUL-terminated,
 * cut to out_size). Returns the exit status, 127 when the program is missing, or -1 when it could not be
 * started or was killed after timeout_ms.
 */
int rl_proc_run(const char *const argv[], const char *input, size_t input_len, char *out, size_t out_size,
		int timeout_ms);

/* The first non-empty line of s, at most size - 1 bytes, into line. */
void rl_proc_first_line(const char *s, char *line, size_t size);

#endif
