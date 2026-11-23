/* The traffic record shared by aggregation, storage and queries. */
#ifndef RL_REC_H
#define RL_REC_H

#include <stdbool.h>
#include <stdint.h>

/* Device indexes 0..RL_DEV_MAX are real devices (see devtab); the top values are pseudo devices. */
#define RL_DEV_MAX 0xFFFC
#define RL_DEV_UNKNOWN 0xFFFD /* LAN address whose MAC could not be resolved */
#define RL_DEV_ROUTER 0xFFFE  /* traffic of the router itself */
#define RL_DEV_WAN 0xFFFF     /* WAN interface counters: one record per bucket with a sample in it */

typedef struct {
	int64_t ts;     /* bucket start */
	uint16_t dev;
	uint8_t cls;    /* rl_class */
	uint8_t flags;  /* reserved */
	uint32_t conns; /* peak concurrent connections seen in the bucket (internet class only) */
	uint64_t rx, tx;
} rl_rec;

/* Return false to stop iterating. */
typedef bool (*rl_rec_cb)(const rl_rec *r, void *ctx);

#endif
