/*
 * SHA-256, HMAC-SHA256 and Base64 for push channels that sign their requests (DingTalk, Feishu). Small
 * enough not to pull a crypto library into the package.
 */
#ifndef RL_SHA256_H
#define RL_SHA256_H

#include <stddef.h>
#include <stdint.h>

#define RL_SHA256_LEN 32

typedef struct {
	uint32_t h[8];
	uint64_t len;
	uint8_t buf[64];
	size_t fill;
} rl_sha256_ctx;

void rl_sha256_init(rl_sha256_ctx *c);
void rl_sha256_update(rl_sha256_ctx *c, const void *data, size_t len);
void rl_sha256_final(rl_sha256_ctx *c, uint8_t out[RL_SHA256_LEN]);
void rl_sha256(const void *data, size_t len, uint8_t out[RL_SHA256_LEN]);
void rl_hmac_sha256(const void *key, size_t key_len, const void *msg, size_t msg_len, uint8_t out[RL_SHA256_LEN]);

/* Standard Base64 with padding; returns the length written (without the NUL), or 0 if out is too small. */
size_t rl_base64(const uint8_t *in, size_t len, char *out, size_t out_size);

#endif
