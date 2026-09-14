#ifndef LINKBACKD_H
#define LINKBACKD_H

#include <stdbool.h>
#include <time.h>

#define MAX_LINKS 16
#define MAX_NAME_LEN 32
#define MAX_TARGETS 8
#define MAX_IP_LEN 64
#define MAX_DOMAIN_LEN 128
#define STATUS_FILE "/var/run/linkback.json"

typedef struct {
	char name[MAX_NAME_LEN];
	bool enabled;
	int priority;
	int metric;

	// Ping config
	char ping_targets[MAX_TARGETS][MAX_IP_LEN];
	int ping_target_count;
	int ping_weight;

	// DNS config
	char dns_server[MAX_IP_LEN];
	char dns_domain[MAX_DOMAIN_LEN];
	int dns_weight;

	// TCP config
	char tcp_target[MAX_IP_LEN];
	int tcp_port;
	int tcp_weight;

	// Thresholds
	int weight_threshold;
	int check_interval;
	int check_timeout;
	int recovery_delay;
	int failover_delay;

	// Runtime state
	char device[MAX_NAME_LEN];   // physical interface name e.g., pppoe-wan, eth1
	char gateway[MAX_IP_LEN];   // gateway IP address
	bool is_up;                 // whether interface is reported up by netifd
	bool healthy;               // daemon link health state
	int consecutive_success;
	int consecutive_failure;
	time_t last_checked;        // Last health check timestamp

	// Detailed health checks status
	bool ping_ok;
	int ping_rtt_ms;
	bool dns_ok;
	int dns_rtt_ms;
	bool tcp_ok;
	int tcp_rtt_ms;

	int current_score;
	int current_metric;         // actual system metric applied
} link_t;

typedef struct {
	bool enabled;
} global_config_t;

#endif // LINKBACKD_H
