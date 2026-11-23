/* Minimal unit-test helpers: no dependencies, one executable per test file. */
#ifndef RL_T_H
#define RL_T_H

#include <inttypes.h>
#include <stdio.h>
#include <string.h>

static int t_failures;

#define T_FAIL(fmt, ...)                                                              \
	do {                                                                          \
		fprintf(stderr, "%s:%d: " fmt "\n", __FILE__, __LINE__, __VA_ARGS__); \
		t_failures++;                                                         \
	} while (0)

#define T_ASSERT(c)                                    \
	do {                                           \
		if (!(c))                              \
			T_FAIL("assertion failed: %s", #c); \
	} while (0)

#define T_EQ_I64(a, b)                                                                             \
	do {                                                                                       \
		int64_t _a = (int64_t)(a), _b = (int64_t)(b);                                      \
		if (_a != _b)                                                                      \
			T_FAIL("%s == %s: %" PRId64 " != %" PRId64, #a, #b, _a, _b);              \
	} while (0)

#define T_EQ_U64(a, b)                                                                             \
	do {                                                                                       \
		uint64_t _a = (uint64_t)(a), _b = (uint64_t)(b);                                   \
		if (_a != _b)                                                                      \
			T_FAIL("%s == %s: %" PRIu64 " != %" PRIu64, #a, #b, _a, _b);              \
	} while (0)

#define T_EQ_STR(a, b)                                                             \
	do {                                                                       \
		const char *_a = (a), *_b = (b);                                   \
		if (strcmp(_a, _b) != 0)                                           \
			T_FAIL("%s == %s: \"%s\" != \"%s\"", #a, #b, _a, _b);      \
	} while (0)

#define T_RUN(fn)                                       \
	do {                                            \
		int _before = t_failures;               \
		fn();                                   \
		printf("%s %s\n", t_failures == _before ? "ok  " : "FAIL", #fn); \
	} while (0)

#define T_DONE() return t_failures ? 1 : 0

#endif
