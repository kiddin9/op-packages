/*
 * Cutting devices off the internet (quota action "block", plan P4 §0.3) with RouteLink's own nftables
 * table, so fw4 reloads never touch it: devices whose MAC is in @block may still reach local networks but
 * nothing else. Pure text for `nft -f -`; sys/block runs it and drops the devices' conntrack entries.
 */
#ifndef RL_NFTGEN_H
#define RL_NFTGEN_H

#include <stddef.h>
#include <stdint.h>

#define RL_NFT_TABLE "routelink"

typedef struct {
	uint8_t family; /* 4 or 6 */
	uint8_t addr[16];
	uint8_t prefix;
} rl_nft_net;

/*
 * The whole table, recreated atomically (delete + add in one transaction). With no blocked device only
 * the delete is written, so nothing stays behind. Returns the length or (size_t)-1 when it does not fit.
 */
size_t rl_nft_script(char *out, size_t size, const uint8_t (*block)[6], size_t n_block, const rl_nft_net *local,
		     size_t n_local);

#endif
