/*
 * Speed limits (design §9.1, plan P4 §0.2) as `tc -force -batch -` scripts.
 *
 * Download: each LAN bridge port's egress gets an HTB root (handle 1:, unlimited default class 1:1), one
 * class per rule and a flower filter on the destination MAC.
 *
 * Upload: policing drops too much for TCP to keep its rate (CI measured 50–85 % of the limit), so uploads
 * are shaped as well: each port's clsact ingress redirects the limited devices' packets (flower on the
 * source MAC, mirred) to one shared ifb device, whose egress has the same kind of HTB with a class per
 * device (flower on the source MAC). A device's upload limit thus holds across all ports.
 *
 * Pure text generation; sys/shaper creates the ifb, runs tc and checks the result.
 */
#ifndef RL_TCGEN_H
#define RL_TCGEN_H

#include <stddef.h>
#include <stdint.h>

#define RL_TC_HANDLE "1:"
/* Classes 1:10 … */
#define RL_TC_FIRST_CLASS 10
/* The ifb device the uploads of limited devices go through. */
#define RL_TC_IFB "rl-ifb0"

typedef struct {
	uint8_t mac[6];
	uint32_t down_kbps; /* 0 = not limited */
	uint32_t up_kbps;
} rl_tc_rule;

/*
 * Removes what RouteLink set up on dev (a port or the ifb). Run it with `tc -force -batch -` and ignore the
 * exit status: on a device that has nothing yet the deletes fail, which is fine.
 */
size_t rl_tc_clear_script(char *out, size_t size, const char *dev);
/*
 * Sets up these rules on a cleared port: download classes, and the redirection of limited uploads to ifb
 * (NULL: no upload limits, e.g. when the ifb could not be created). Empty when nothing is limited. Every
 * command must succeed (a failure means missing kernel modules or a bad rule). Returns the length, or
 * (size_t)-1 when it does not fit.
 */
size_t rl_tc_script(char *out, size_t size, const char *dev, const char *ifb, const rl_tc_rule *rules, size_t n);
/* The upload classes on the cleared ifb; empty when no rule limits uploads. Like rl_tc_script. */
size_t rl_tc_ifb_script(char *out, size_t size, const char *ifb, const rl_tc_rule *rules, size_t n);

#endif
