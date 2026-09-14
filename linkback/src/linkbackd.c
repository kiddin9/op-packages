#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <syslog.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/select.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <errno.h>
#include <uci.h>
#include "linkbackd.h"

// DNS Header struct for raw check
struct dns_header {
	unsigned short id;
	unsigned short flags;
	unsigned short qdcount;
	unsigned short ancount;
	unsigned short nscount;
	unsigned short arcount;
};

// Global daemon state
static global_config_t global_cfg;
static link_t links[MAX_LINKS];
static int link_count = 0;
static volatile bool keep_running = true;

// Prototypes
static void restore_all_metrics(void);
static bool validate_loaded_config(void);
static void handle_signal(int sig) {
	syslog(LOG_INFO, "Received signal %d, exiting...", sig);
	keep_running = false;
}

// Ubus popen JSON parser
static bool get_interface_ubus_status(const char *ifname, char *device, int dev_len, char *gateway, int gw_len, bool *is_up) {
	char cmd[256];
	snprintf(cmd, sizeof(cmd), "ubus call network.interface.%s status 2>/dev/null", ifname);
	FILE *fp = popen(cmd, "r");
	if (!fp) return false;

	char buf[4096] = {0};
	int bytes_read = fread(buf, 1, sizeof(buf) - 1, fp);
	pclose(fp);

	if (bytes_read <= 0) return false;

	// Check if interface is up
	*is_up = false;
	char *p_up = strstr(buf, "\"up\":");
	if (p_up) {
		char *p_true = strstr(p_up, "true");
		// Ensure 'true' belongs to this property and isn't far away
		if (p_true && p_true - p_up < 10) {
			*is_up = true;
		}
	}

	// Extract physical device
	device[0] = '\0';
	char *p_dev = strstr(buf, "\"l3_device\":");
	int dev_key_len = 12;
	if (!p_dev) {
		p_dev = strstr(buf, "\"device\":");
		dev_key_len = 9;
	}
	if (p_dev) {
		char *p_start = strchr(p_dev + dev_key_len, '"');
		if (p_start) {
			char *p_end = strchr(p_start + 1, '"');
			if (p_end) {
				int len = p_end - p_start - 1;
				if (len >= dev_len) len = dev_len - 1;
				strncpy(device, p_start + 1, len);
				device[len] = '\0';
			}
		}
	}

	// Extract gateway/nexthop from route list
	gateway[0] = '\0';
	char *p_route = strstr(buf, "\"route\":");
	if (p_route) {
		char *p_nexthop = strstr(p_route, "\"nexthop\":");
		if (p_nexthop) {
			char *p_start = strchr(p_nexthop + 10, '"');
			if (p_start) {
				char *p_end = strchr(p_start + 1, '"');
				if (p_end) {
					int len = p_end - p_start - 1;
					if (len >= gw_len) len = gw_len - 1;
					strncpy(gateway, p_start + 1, len);
					gateway[len] = '\0';
				}
			}
		}
	}

	return true;
}

// Ping check
static bool run_ping_check(const char *device, const char *target, int timeout, int *rtt_ms) {
	if (device[0] == '\0' || target[0] == '\0') return false;

	char cmd[256];
	snprintf(cmd, sizeof(cmd), "ping -I %s -c 1 -W %d %s 2>/dev/null", device, timeout, target);
	FILE *fp = popen(cmd, "r");
	if (!fp) return false;

	char line[128];
	bool ok = false;
	*rtt_ms = -1;
	while (fgets(line, sizeof(line), fp)) {
		char *p = strstr(line, "time=");
		if (p) {
			ok = true;
			double rtt = atof(p + 5);
			*rtt_ms = (int)rtt;
		}
	}
	int status = pclose(fp);
	return ok && (WIFEXITED(status) && WEXITSTATUS(status) == 0);
}

// DNS check
static bool run_dns_check(const char *device, const char *dns_server, const char *domain, int timeout, int *rtt_ms) {
	if (device[0] == '\0' || dns_server[0] == '\0' || domain[0] == '\0') return false;

	struct timeval start, end;
	gettimeofday(&start, NULL);

	int sockfd = socket(AF_INET, SOCK_DGRAM, 0);
	if (sockfd < 0) return false;

	// Set non-blocking
	int flags = fcntl(sockfd, F_GETFL, 0);
	fcntl(sockfd, F_SETFL, flags | O_NONBLOCK);

	// Bind to device
	if (setsockopt(sockfd, SOL_SOCKET, SO_BINDTODEVICE, device, strlen(device)) < 0) {
		close(sockfd);
		return false;
	}

	struct sockaddr_in servaddr;
	memset(&servaddr, 0, sizeof(servaddr));
	servaddr.sin_family = AF_INET;
	servaddr.sin_port = htons(53);
	if (inet_pton(AF_INET, dns_server, &servaddr.sin_addr) <= 0) {
		close(sockfd);
		return false;
	}

	// Format DNS packet
	unsigned char packet[512];
	memset(packet, 0, sizeof(packet));

	struct dns_header *dns = (struct dns_header *)packet;
	dns->id = (unsigned short)htons(getpid());
	dns->flags = htons(0x0100);
	dns->qdcount = htons(1);

	unsigned char *qname = packet + sizeof(struct dns_header);
	const char *src = domain;
	unsigned char *dst = qname;
	while (*src) {
		const char *next = strchr(src, '.');
		int len = next ? (next - src) : strlen(src);
		*dst++ = len;
		memcpy(dst, src, len);
		dst += len;
		src = next ? (next + 1) : (src + len);
	}
	*dst++ = 0;

	unsigned short *qtype = (unsigned short *)dst;
	*qtype = htons(1); // A Record
	dst += 2;
	unsigned short *qclass = (unsigned short *)dst;
	*qclass = htons(1); // IN
	dst += 2;

	int packet_len = dst - packet;

	if (sendto(sockfd, packet, packet_len, 0, (struct sockaddr *)&servaddr, sizeof(servaddr)) < 0) {
		if (errno != EAGAIN && errno != EWOULDBLOCK) {
			close(sockfd);
			return false;
		}
	}

	fd_set readfds;
	FD_ZERO(&readfds);
	FD_SET(sockfd, &readfds);
	struct timeval tv;
	tv.tv_sec = timeout;
	tv.tv_usec = 0;

	int sel = select(sockfd + 1, &readfds, NULL, NULL, &tv);
	if (sel <= 0) {
		close(sockfd);
		return false;
	}

	unsigned char response[512];
	struct sockaddr_in from;
	socklen_t from_len = sizeof(from);
	int resp_len = recvfrom(sockfd, response, sizeof(response), 0, (struct sockaddr *)&from, &from_len);
	close(sockfd);

	if (resp_len < 12) return false;

	struct dns_header *resp_dns = (struct dns_header *)response;
	if (ntohs(resp_dns->id) != getpid()) return false;

	gettimeofday(&end, NULL);
	*rtt_ms = (int)((end.tv_sec - start.tv_sec) * 1000 + (end.tv_usec - start.tv_usec) / 1000);
	return true;
}

// TCP check
static bool run_tcp_check(const char *device, const char *tcp_target, int port, int timeout, int *rtt_ms) {
	if (device[0] == '\0' || tcp_target[0] == '\0' || port <= 0) return false;

	struct timeval start, end;
	gettimeofday(&start, NULL);

	int sockfd = socket(AF_INET, SOCK_STREAM, 0);
	if (sockfd < 0) return false;

	// Set non-blocking
	int flags = fcntl(sockfd, F_GETFL, 0);
	fcntl(sockfd, F_SETFL, flags | O_NONBLOCK);

	// Bind to device
	if (setsockopt(sockfd, SOL_SOCKET, SO_BINDTODEVICE, device, strlen(device)) < 0) {
		close(sockfd);
		return false;
	}

	struct sockaddr_in addr;
	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_port = htons(port);
	if (inet_pton(AF_INET, tcp_target, &addr.sin_addr) <= 0) {
		close(sockfd);
		return false;
	}

	int rc = connect(sockfd, (struct sockaddr *)&addr, sizeof(addr));
	if (rc < 0) {
		if (errno != EINPROGRESS) {
			close(sockfd);
			return false;
		}
	} else {
		gettimeofday(&end, NULL);
		*rtt_ms = (int)((end.tv_sec - start.tv_sec) * 1000 + (end.tv_usec - start.tv_usec) / 1000);
		close(sockfd);
		return true;
	}

	fd_set writefds;
	FD_ZERO(&writefds);
	FD_SET(sockfd, &writefds);
	struct timeval tv;
	tv.tv_sec = timeout;
	tv.tv_usec = 0;

	int sel = select(sockfd + 1, NULL, &writefds, NULL, &tv);
	if (sel <= 0) {
		close(sockfd);
		return false;
	}

	int optval;
	socklen_t optlen = sizeof(optval);
	if (getsockopt(sockfd, SOL_SOCKET, SO_ERROR, &optval, &optlen) < 0 || optval != 0) {
		close(sockfd);
		return false;
	}

	gettimeofday(&end, NULL);
	*rtt_ms = (int)((end.tv_sec - start.tv_sec) * 1000 + (end.tv_usec - start.tv_usec) / 1000);
	close(sockfd);
	return true;
}

// UCI parser helper
static bool load_config(void) {
	struct uci_context *ctx = uci_alloc_context();
	if (!ctx) return false;

	struct uci_package *pkg = NULL;
	if (uci_load(ctx, "linkback", &pkg) != UCI_OK) {
		uci_free_context(ctx);
		return false;
	}

	// Parse global config
	global_cfg.enabled = false;

	struct uci_section *global_sec = uci_lookup_section(ctx, pkg, "global");
	if (!global_sec) {
		struct uci_element *ge;
		uci_foreach_element(&pkg->sections, ge) {
			struct uci_section *s = uci_to_section(ge);
			if (strcmp(s->type, "global") == 0) {
				global_sec = s;
				break;
			}
		}
	}

	if (global_sec) {
		const char *enabled = uci_lookup_option_string(ctx, global_sec, "enabled");
		global_cfg.enabled = (enabled && strcmp(enabled, "1") == 0);
	}

	// Parse links
	link_count = 0;
	struct uci_element *e;
	uci_foreach_element(&pkg->sections, e) {
		struct uci_section *s = uci_to_section(e);
		if (strcmp(s->type, "link") != 0) continue;

		const char *enabled = uci_lookup_option_string(ctx, s, "enabled");
		if (enabled && strcmp(enabled, "0") == 0) continue;

		link_t *link = &links[link_count];
		memset(link, 0, sizeof(link_t));

		const char *name = uci_lookup_option_string(ctx, s, "name");
		if (!name) continue;
		strncpy(link->name, name, MAX_NAME_LEN - 1);

		link->enabled = true;

		const char *priority = uci_lookup_option_string(ctx, s, "priority");
		int prio_val = priority ? atoi(priority) : 1;
		link->priority = (prio_val > 0) ? prio_val : 1;

		link->metric = link->priority * 10;
		link->current_metric = link->metric;

		// Parse ping targets (split by comma or space)
		const char *pings = uci_lookup_option_string(ctx, s, "ping_targets");
		if (pings) {
			char tmp[256];
			strncpy(tmp, pings, sizeof(tmp) - 1);
			tmp[sizeof(tmp) - 1] = '\0';
			char *token = strtok(tmp, ", \t");
			while (token && link->ping_target_count < MAX_TARGETS) {
				// Trim leading whitespace
				while (*token == ' ' || *token == '\t' || *token == '\r' || *token == '\n') {
					token++;
				}
				// Trim trailing whitespace
				char *end = token + strlen(token) - 1;
				while (end > token && (*end == ' ' || *end == '\t' || *end == '\r' || *end == '\n')) {
					*end = '\0';
					end--;
				}
				if (*token != '\0') {
					strncpy(link->ping_targets[link->ping_target_count], token, MAX_IP_LEN - 1);
					link->ping_target_count++;
				}
				token = strtok(NULL, ",");
			}
		}

		// Parse DNS targets
		const char *dns_srv = uci_lookup_option_string(ctx, s, "dns_server");
		if (dns_srv) strncpy(link->dns_server, dns_srv, MAX_IP_LEN - 1);

		const char *dns_dom = uci_lookup_option_string(ctx, s, "dns_domain");
		if (dns_dom) strncpy(link->dns_domain, dns_dom, MAX_DOMAIN_LEN - 1);

		// Parse TCP targets
		const char *tcp_tgt = uci_lookup_option_string(ctx, s, "tcp_target");
		if (tcp_tgt) strncpy(link->tcp_target, tcp_tgt, MAX_IP_LEN - 1);

		const char *tcp_p = uci_lookup_option_string(ctx, s, "tcp_port");
		if (tcp_p) link->tcp_port = atoi(tcp_p);

		const char *interval = uci_lookup_option_string(ctx, s, "check_interval");
		link->check_interval = interval ? atoi(interval) : 5;

		const char *timeout = uci_lookup_option_string(ctx, s, "check_timeout");
		link->check_timeout = timeout ? atoi(timeout) : 3;

		const char *recovery = uci_lookup_option_string(ctx, s, "recovery_delay");
		link->recovery_delay = recovery ? atoi(recovery) : 3;

		const char *failover = uci_lookup_option_string(ctx, s, "failover_delay");
		link->failover_delay = failover ? atoi(failover) : 2;

		// Default runtime states
		link->healthy = true;
		link->is_up = false;
		link->last_checked = 0; // Force immediate check on startup

		link_count++;
		if (link_count >= MAX_LINKS) break;
	}

	uci_unload(ctx, pkg);
	uci_free_context(ctx);

	if (!validate_loaded_config()) {
		return false;
	}

	return true;
}

// Startup-time defensive validation. LuCI-side checks can be bypassed by
// direct UCI edits, so daemon must refuse unsafe/incomplete configs.
static bool validate_loaded_config(void) {
	if (!global_cfg.enabled) {
		return true;
	}

	if (link_count < 2) {
		syslog(LOG_ERR, "Invalid config: at least 2 enabled monitored links are required, got %d.", link_count);
		return false;
	}

	for (int i = 0; i < link_count; i++) {
		link_t *a = &links[i];

		if (a->name[0] == '\0') {
			syslog(LOG_ERR, "Invalid config: link[%d] has empty interface name.", i);
			return false;
		}

		if (a->priority <= 0) {
			syslog(LOG_ERR, "Invalid config: link %s has invalid priority %d (must be > 0).", a->name, a->priority);
			return false;
		}

		if (a->metric <= 0) {
			syslog(LOG_ERR, "Invalid config: link %s has invalid metric %d (must be > 0).", a->name, a->metric);
			return false;
		}

		// No duplicate priorities
		for (int j = i + 1; j < link_count; j++) {
			link_t *b = &links[j];
			if (a->priority == b->priority) {
				syslog(LOG_ERR, "Invalid config: duplicate priority %d on links %s and %s.", a->priority, a->name, b->name);
				return false;
			}
		}

		bool has_ping = (a->ping_target_count > 0);
		bool has_dns = (a->dns_server[0] != '\0' && a->dns_domain[0] != '\0');
		bool has_tcp = (a->tcp_target[0] != '\0' && a->tcp_port > 0);

		int check_count = 0;
		if (has_ping) check_count++;
		if (has_dns) check_count++;
		if (has_tcp) check_count++;

		if (check_count == 0) {
			syslog(LOG_ERR, "Invalid config: link %s has no complete health-check probe configured.", a->name);
			return false;
		}
		if (check_count > 1) {
			syslog(LOG_ERR, "Invalid config: link %s has multiple health-check probes configured. Only one check type is allowed.", a->name);
			return false;
		}

		if ((a->dns_server[0] != '\0') != (a->dns_domain[0] != '\0')) {
			syslog(LOG_ERR, "Invalid config: link %s DNS probe is incomplete (dns_server + dns_domain required).", a->name);
			return false;
		}

		if ((a->tcp_target[0] != '\0') != (a->tcp_port > 0)) {
			syslog(LOG_ERR, "Invalid config: link %s TCP probe is incomplete (tcp_target + tcp_port required).", a->name);
			return false;
		}

		if (a->check_interval <= 0 || a->check_timeout <= 0 ||
		    a->recovery_delay <= 0 || a->failover_delay <= 0) {
			syslog(LOG_ERR, "Invalid config: link %s timing values must be > 0.", a->name);
			return false;
		}
	}

	return true;
}

// Retrieve the real default route metric for a device from /proc/net/route
static int get_system_route_metric(const char *device, int expected_metric) {
	if (device[0] == '\0') return -1;
	FILE *fp = fopen("/proc/net/route", "r");
	if (!fp) return -1;

	char line[256];
	char iface[32];
	unsigned long dest;
	int metric = -1;
	int first_found_metric = -1;
	bool found_expected = false;

	// Skip header line
	if (fgets(line, sizeof(line), fp)) {
		while (fgets(line, sizeof(line), fp)) {
			// Destination is 2nd column, Metric is 7th column, dest is in hex.
			// Use %*s for Gateway and Flags to safely skip non-numeric characters.
			if (sscanf(line, "%31s %lx %*s %*s %*d %*d %d", iface, &dest, &metric) == 3) {
				if (strcmp(iface, device) == 0 && dest == 0) {
					if (first_found_metric == -1) {
						first_found_metric = metric;
					}
					if (metric == expected_metric) {
						found_expected = true;
						break;
					}
				}
			}
		}
	}
	fclose(fp);

	if (found_expected) {
		return expected_metric;
	}
	return first_found_metric;
}

// Compare priority for sorting (lowest priority number is highest precedence)
static int compare_links(const void *a, const void *b) {
	link_t *la = (link_t *)a;
	link_t *lb = (link_t *)b;
	return la->priority - lb->priority;
}

// Dynamic route update using ip route command
static void update_route_metric(link_t *link, int new_metric, int old_metric_to_delete) {
	if (link->device[0] == '\0') return;

	char cmd[512];

	// 1. Delete the specified old metric to prevent duplicate routes
	if (old_metric_to_delete != -1 && old_metric_to_delete != new_metric) {
		if (link->gateway[0] != '\0') {
			snprintf(cmd, sizeof(cmd), "ip route del default via %s dev %s metric %d 2>/dev/null", 
			         link->gateway, link->device, old_metric_to_delete);
		} else {
			snprintf(cmd, sizeof(cmd), "ip route del default dev %s metric %d 2>/dev/null", 
			         link->device, old_metric_to_delete);
		}
		system(cmd);
	}

	// 2. Delete the current_metric if it is different from new_metric and old_metric_to_delete
	if (link->current_metric != new_metric && link->current_metric != old_metric_to_delete) {
		if (link->gateway[0] != '\0') {
			snprintf(cmd, sizeof(cmd), "ip route del default via %s dev %s metric %d 2>/dev/null", 
			         link->gateway, link->device, link->current_metric);
		} else {
			snprintf(cmd, sizeof(cmd), "ip route del default dev %s metric %d 2>/dev/null", 
			         link->device, link->current_metric);
		}
		system(cmd);
	}

	// 3. Add/replace with new_metric
	if (link->gateway[0] != '\0') {
		snprintf(cmd, sizeof(cmd), "ip route replace default via %s dev %s metric %d 2>/dev/null", 
		         link->gateway, link->device, new_metric);
	} else {
		snprintf(cmd, sizeof(cmd), "ip route replace default dev %s metric %d 2>/dev/null", 
		         link->device, new_metric);
	}

	syslog(LOG_INFO, "Applying route metric update on link %s (%s, priority %d): %d -> %d", 
	       link->name, link->device, link->priority, link->current_metric, new_metric);
	
	int rc = system(cmd);
	if (rc == 0) {
		link->current_metric = new_metric;
	} else {
		syslog(LOG_ERR, "Failed to apply route update for %s (priority %d) using cmd: %s", link->name, link->priority, cmd);
	}
}

// Restore default metrics on exit
static void restore_all_metrics(void) {
	syslog(LOG_INFO, "Restoring all interface metrics on exit...");
	for (int i = 0; i < link_count; i++) {
		link_t *link = &links[i];
		if (link->enabled && link->is_up && link->device[0] != '\0') {
			char cmd[512];
			// Delete floated metric if it was in fault state
			if (link->current_metric != link->metric) {
				if (link->gateway[0] != '\0') {
					snprintf(cmd, sizeof(cmd), "ip route del default via %s dev %s metric %d 2>/dev/null", 
					         link->gateway, link->device, link->current_metric);
				} else {
					snprintf(cmd, sizeof(cmd), "ip route del default dev %s metric %d 2>/dev/null", 
					         link->device, link->current_metric);
				}
				system(cmd);
			}
			if (link->gateway[0] != '\0') {
				snprintf(cmd, sizeof(cmd), "ip route replace default via %s dev %s metric %d 2>/dev/null", 
				         link->gateway, link->device, link->metric);
			} else {
				snprintf(cmd, sizeof(cmd), "ip route replace default dev %s metric %d 2>/dev/null", 
				         link->device, link->metric);
			}
			int rc = system(cmd);
			if (rc == 0) {
				syslog(LOG_INFO, "Successfully restored default metric %d for interface %s (priority %d)", link->metric, link->name, link->priority);
			}
		}
	}
}

// Write status file to /var/run/linkback.json
static void write_status_json(void) {
	FILE *fp = fopen(STATUS_FILE, "w");
	if (!fp) return;

	fprintf(fp, "{\n");
	fprintf(fp, "  \"enabled\": %s,\n", global_cfg.enabled ? "true" : "false");
	fprintf(fp, "  \"check_interval\": 5,\n");

	// Find current active gateway link (first healthy link ordered by priority)
	char active_link[MAX_NAME_LEN] = "none";
	for (int i = 0; i < link_count; i++) {
		if (links[i].is_up && links[i].healthy) {
			strncpy(active_link, links[i].name, MAX_NAME_LEN - 1);
			break;
		}
	}
	fprintf(fp, "  \"active_link\": \"%s\",\n", active_link);
	fprintf(fp, "  \"links\": [\n");

	for (int i = 0; i < link_count; i++) {
		link_t *link = &links[i];
		fprintf(fp, "    {\n");
		fprintf(fp, "      \"name\": \"%s\",\n", link->name);
		fprintf(fp, "      \"priority\": %d,\n", link->priority);
		fprintf(fp, "      \"metric\": %d,\n", link->metric);
		fprintf(fp, "      \"current_metric\": %d,\n", link->current_metric);
		fprintf(fp, "      \"healthy\": %s,\n", link->healthy ? "true" : "false");
		fprintf(fp, "      \"is_up\": %s,\n", link->is_up ? "true" : "false");
		fprintf(fp, "      \"device\": \"%s\",\n", link->device);
		fprintf(fp, "      \"gateway\": \"%s\",\n", link->gateway);
		fprintf(fp, "      \"score\": %d,\n", link->current_score);
		fprintf(fp, "      \"threshold\": %d,\n", link->weight_threshold);
		fprintf(fp, "      \"check_interval\": %d,\n", link->check_interval);
		fprintf(fp, "      \"check_timeout\": %d,\n", link->check_timeout);
		fprintf(fp, "      \"recovery_delay\": %d,\n", link->recovery_delay);
		fprintf(fp, "      \"failover_delay\": %d,\n", link->failover_delay);
		const char *type = "none";
		if (link->ping_target_count > 0) type = "ping";
		else if (link->dns_server[0] != '\0') type = "dns";
		else if (link->tcp_target[0] != '\0') type = "tcp";

		fprintf(fp, "      \"check_type\": \"%s\",\n", type);
		fprintf(fp, "      \"ping\": {\"ok\": %s, \"rtt\": %d},\n", link->ping_ok ? "true" : "false", link->ping_rtt_ms);
		fprintf(fp, "      \"dns\": {\"ok\": %s, \"rtt\": %d},\n", link->dns_ok ? "true" : "false", link->dns_rtt_ms);
		fprintf(fp, "      \"tcp\": {\"ok\": %s, \"rtt\": %d}\n", link->tcp_ok ? "true" : "false", link->tcp_rtt_ms);
		fprintf(fp, "    }%s\n", (i == link_count - 1) ? "" : ",");
	}
	fprintf(fp, "  ]\n");
	fprintf(fp, "}\n");
	fclose(fp);
}

int main(int argc, char **argv) {
	// Setup syslog
	openlog("linkbackd", LOG_PID | LOG_NDELAY, LOG_DAEMON);
	syslog(LOG_INFO, "Starting LinkBack daemon...");

	// Register signal handlers for clean exits and metric restoration
	signal(SIGTERM, handle_signal);
	signal(SIGINT, handle_signal);

	// Load configuration
	if (!load_config()) {
		syslog(LOG_ERR, "Failed to load linkback config. Exiting.");
		closelog();
		return 1;
	}

	if (!global_cfg.enabled) {
		syslog(LOG_WARNING, "LinkBack is disabled globally in configuration. Exiting.");
		closelog();
		return 0;
	}

	// Sort links by priority (lowest priority number first)
	qsort(links, link_count, sizeof(link_t), compare_links);

	syslog(LOG_INFO, "Loaded %d monitored interfaces. Starting health check scheduler.", link_count);

	// Core check loop
	while (keep_running) {
		time_t now = time(NULL);
		bool any_checked = false;

		for (int i = 0; i < link_count; i++) {
			link_t *link = &links[i];

			// Check if this interface is due for checking
			if (now - link->last_checked < link->check_interval) {
				continue;
			}
			link->last_checked = now;
			any_checked = true;

			// 1. Fetch real-time netifd status
			char dev[MAX_NAME_LEN] = {0};
			char gw[MAX_IP_LEN] = {0};
			bool is_up = false;

			get_interface_ubus_status(link->name, dev, sizeof(dev), gw, sizeof(gw), &is_up);
			link->is_up = is_up;
			strncpy(link->device, dev, MAX_NAME_LEN - 1);
			strncpy(link->gateway, gw, MAX_IP_LEN - 1);

			if (!is_up || dev[0] == '\0') {
				// Interface is down in netifd, mark unhealthy immediately
				link->healthy = false;
				link->current_score = 0;
				link->ping_ok = false;
				link->dns_ok = false;
				link->tcp_ok = false;
				link->consecutive_success = 0;
				link->consecutive_failure = 0;

				// If it still has low metric, float it
				if (link->current_metric == link->metric) {
					update_route_metric(link, 1000 + link->metric, -1);
				}
				continue;
			}

			// 2. Perform health checks
			bool check_success = false;

			if (link->ping_target_count > 0) {
				link->ping_ok = false;
				link->ping_rtt_ms = -1;
				for (int p = 0; p < link->ping_target_count; p++) {
					int rtt = -1;
					if (run_ping_check(link->device, link->ping_targets[p], link->check_timeout, &rtt)) {
						link->ping_ok = true;
						link->ping_rtt_ms = rtt;
						break;
					}
				}
				check_success = link->ping_ok;
			}
			else if (link->dns_server[0] != '\0' && link->dns_domain[0] != '\0') {
				link->dns_ok = false;
				link->dns_rtt_ms = -1;
				int rtt = -1;
				if (run_dns_check(link->device, link->dns_server, link->dns_domain, link->check_timeout, &rtt)) {
					link->dns_ok = true;
					link->dns_rtt_ms = rtt;
				}
				check_success = link->dns_ok;
			}
			else if (link->tcp_target[0] != '\0' && link->tcp_port > 0) {
				link->tcp_ok = false;
				link->tcp_rtt_ms = -1;
				int rtt = -1;
				if (run_tcp_check(link->device, link->tcp_target, link->tcp_port, link->check_timeout, &rtt)) {
					link->tcp_ok = true;
					link->tcp_rtt_ms = rtt;
				}
				check_success = link->tcp_ok;
			}

			link->current_score = check_success ? 1 : 0;

			// 3. Evaluate health state changes (filtering and delay)

			if (check_success) {
				link->consecutive_success++;
				link->consecutive_failure = 0;

				if (!link->healthy && link->consecutive_success >= link->recovery_delay) {
					// Recovered! Failback!
					link->healthy = true;
					syslog(LOG_NOTICE, "Link %s (%s, priority %d) recovered to healthy after %d successes.", 
					       link->name, link->device, link->priority, link->consecutive_success);
					
					// Restore original metric
					update_route_metric(link, link->metric, -1);
				}
			} else {
				link->consecutive_failure++;
				link->consecutive_success = 0;

				if (link->healthy && link->consecutive_failure >= link->failover_delay) {
					// Failed! Failover!
					link->healthy = false;
					syslog(LOG_WARNING, "Link %s (%s, priority %d) went down after %d failures.", 
					       link->name, link->device, link->priority, link->consecutive_failure);
					
					// Push metric out of choice range
					update_route_metric(link, 1000 + link->metric, -1);
				}
			}

			// 4. Active routing metric self-healing to prevent external/netifd interference
			if (link->device[0] != '\0') {
				int expected_metric = (link->is_up && link->healthy) ? link->metric : (1000 + link->metric);
				int real_metric = get_system_route_metric(link->device, expected_metric);
				if (real_metric != -1 && real_metric != expected_metric) {
					syslog(LOG_WARNING, "Route metric mismatch detected on %s (%s, priority %d): expected %d, got %d. Correcting...", 
					       link->name, link->device, link->priority, expected_metric, real_metric);
					update_route_metric(link, expected_metric, real_metric);
				}
			}
		}

		if (any_checked) {
			// Write states to shared JSON file
			write_status_json();
		}

		// High-responsiveness scheduler ticks every second
		sleep(1);
	}

	// Terminating: clean up routes before exit
	restore_all_metrics();
	unlink(STATUS_FILE);
	syslog(LOG_INFO, "LinkBack daemon terminated successfully.");
	closelog();
	return 0;
}
