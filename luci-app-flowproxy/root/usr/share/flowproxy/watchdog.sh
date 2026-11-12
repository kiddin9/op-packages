#!/bin/sh
# FlowProxy sidecar watchdog daemon (ARP + Ping health probe)

. /usr/share/flowproxy/common.sh

MY_GEN="$1"
[ -z "$MY_GEN" ] && exit 0

STOP_REQUESTED=0
SLEEP_PID=""

handle_signal() {
	STOP_REQUESTED=1
	[ -n "$SLEEP_PID" ] && kill "$SLEEP_PID" 2>/dev/null
}

trap 'handle_signal' TERM INT

interruptible_sleep() {
	local secs="$1"
	[ "$STOP_REQUESTED" -eq 1 ] && return 1
	sleep "$secs" &
	SLEEP_PID=$!
	wait "$SLEEP_PID" 2>/dev/null
	SLEEP_PID=""
	[ "$STOP_REQUESTED" -eq 1 ] && return 1
	return 0
}

get_uint_or_default() {
	local val="$1"
	local def="$2"
	local min="$3"
	case "$val" in
		''|*[!0-9]*) echo "$def"; return ;;
	esac
	[ "$val" -lt "$min" ] && echo "$min" || echo "$val"
}

is_context_valid() {
	[ "$STOP_REQUESTED" -eq 0 ] || return 1
	[ -f "$STATE_FILE" ] || return 1
	[ "$(cat "$GEN_FILE" 2>/dev/null)" = "$MY_GEN" ] || return 1
	[ "$(uci -q get "$UCI_CONFIG.global.enabled" || echo 0)" = "1" ] || return 1
	[ "$(uci -q get "$UCI_CONFIG.global.monitor_enabled" || echo 0)" = "1" ] || return 1
	return 0
}

is_nft_active() {
	nft list tables inet 2>/dev/null | grep -q "^table inet ${UCI_CONFIG}$"
}

proxy_ip=$(uci -q get "$UCI_CONFIG.global.proxy_server_ip_addr")
probe_iface=$(resolve_proxy_iface "" "$proxy_ip")

interval=$(get_uint_or_default "$(uci -q get "$UCI_CONFIG.global.monitor_interval")" 5 2)
fail_threshold=$(get_uint_or_default "$(uci -q get "$UCI_CONFIG.global.monitor_fail_threshold")" 3 1)
recover_threshold=$(get_uint_or_default "$(uci -q get "$UCI_CONFIG.global.monitor_recover_threshold")" 2 1)

[ -z "$proxy_ip" ] && exit 0

echo "$$" > "$WD_PID_FILE"
log_msg info "Watchdog started (target=$proxy_ip, iface=$probe_iface, interval=${interval}s, fail=$fail_threshold, recover=$recover_threshold)"

# 启动阶段已由 init 完成首次状态建立，进入常规周期轮询
interruptible_sleep "$interval" || exit 0

[ -f "$DEGRADED_FILE" ] && state="degraded" || state="online"
fail_count=0
ok_count=0

while is_context_valid; do
	[ -f "$DEGRADED_FILE" ] && state="degraded" || state="online"
	probe_start=$(date +%s)
	if check_proxy_alive "$proxy_ip" "$probe_iface"; then
		fail_count=0
		if [ "$state" = "degraded" ]; then
			ok_count=$((ok_count + 1))
			log_msg debug "Watchdog: probe succeeded ($ok_count/$recover_threshold)"
			if [ "$ok_count" -ge "$recover_threshold" ]; then
				if acquire_lock 0; then
					if ! is_context_valid; then
						release_lock
						break
					fi
					if [ -f "$DEGRADED_FILE" ]; then
						if do_recover; then
							state="online"
							ok_count=0
							fail_count=0
						else
							log_msg error "Watchdog: recovery failed, staying in degraded mode"
						fi
					else
						state="online"
						ok_count=0
					fi
					release_lock
				else
					log_msg warn "Watchdog: failed to acquire lock for recovery, retrying next cycle"
				fi
			fi
		else
			ok_count=0
			# 在线状态下若内核 nft 表被外部清空，自动自愈恢复
			if ! is_nft_active; then
				if acquire_lock 0; then
					if is_context_valid && [ ! -f "$DEGRADED_FILE" ] && ! is_nft_active; then
						log_msg warn "Watchdog: nftables table missing while online, restoring rules..."
						restore_nft_rules && add_route
					fi
					release_lock
				fi
			fi
		fi
	else
		[ "$STOP_REQUESTED" -eq 1 ] && break
		ok_count=0
		if [ "$state" = "online" ]; then
			fail_count=$((fail_count + 1))
			log_msg warn "Watchdog: probe failed ($fail_count/$fail_threshold) for $proxy_ip via $probe_iface"
			if [ "$fail_count" -ge "$fail_threshold" ]; then
				if acquire_lock 0; then
					if ! is_context_valid; then
						release_lock
						break
					fi
					if [ ! -f "$DEGRADED_FILE" ]; then
						do_degrade
						state="degraded"
						fail_count=0
						ok_count=0
					else
						state="degraded"
						fail_count=0
					fi
					release_lock
				else
					log_msg warn "Watchdog: failed to acquire lock for degrade, retrying next cycle"
				fi
			fi
		else
			fail_count=0
		fi
	fi

	probe_end=$(date +%s)
	elapsed=$((probe_end - probe_start))
	[ "$elapsed" -lt 0 ] && elapsed=0
	sleep_secs=$((interval - elapsed))
	[ "$sleep_secs" -lt 1 ] && sleep_secs=1
	interruptible_sleep "$sleep_secs" || break
done

[ "$(cat "$WD_PID_FILE" 2>/dev/null)" = "$$" ] && rm -f "$WD_PID_FILE"
log_msg info "Watchdog stopped"
exit 0
