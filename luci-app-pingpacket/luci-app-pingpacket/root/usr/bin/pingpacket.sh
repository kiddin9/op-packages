#!/bin/sh

STATUS_FILE="/tmp/pingpacket_status.json"
STATUS_TMP="${STATUS_FILE}.tmp"
LOG_FILE="/tmp/pingpacket.log"
LOG_MAX_LINES=500
RUN_DIR="/var/run/pingpacket"
START_TIME_FILE="$RUN_DIR/start_time"
child_pids=""
domestic_fail_count=0
foreign_fail_count=0
domestic_fault_open=0
foreign_fault_open=0
domestic_total_samples=0
foreign_total_samples=0
domestic_success_count=0
foreign_success_count=0
domestic_loss_count=0
foreign_loss_count=0
domestic_rtt_sum="0"
foreign_rtt_sum="0"
domestic_min_rtt=""
foreign_min_rtt=""
domestic_max_rtt=""
foreign_max_rtt=""
domestic_last_probe_at=0
foreign_last_probe_at=0
domestic_last_fault_probe_at=0
foreign_last_fault_probe_at=0
domestic_last_stats_probe_at=0
foreign_last_stats_probe_at=0

log_rotate() {
	[ -f "$LOG_FILE" ] || return 0
	tail -n "$LOG_MAX_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp" 2>/dev/null && \
		mv -f "${LOG_FILE}.tmp" "$LOG_FILE"
}

log_event() {
	local event_type="$1"
	local scope="$2"
	local message="$3"
	local timestamp

	timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
	if [ -n "$scope" ]; then
		printf '[%s] [%s] [%s] %s\n' "$timestamp" "$event_type" "$scope" "$message" >> "$LOG_FILE"
	else
		printf '[%s] [%s] %s\n' "$timestamp" "$event_type" "$message" >> "$LOG_FILE"
	fi
	log_rotate
}

kill_children() {
	[ -n "$child_pids" ] || return 0
	kill $child_pids 2>/dev/null
	wait $child_pids 2>/dev/null
	child_pids=""
}

cleanup() {
	kill_children
	exit 0
}

trap cleanup INT TERM

mkdir -p "$RUN_DIR"
date '+%Y-%m-%d %H:%M:%S' > "$START_TIME_FILE"

write_result_file() {
	local path="$1"
	local success="$2"
	local rtt="$3"
	local detail="$4"
	local probe_at="$5"

	[ -n "$probe_at" ] || probe_at="$(date '+%s' 2>/dev/null || echo 0)"

	mkdir -p "$(dirname "$path")"
	printf '%s\n%s\n%s\n%s\n' "$success" "$rtt" "$detail" "$probe_at" > "$path"
}

normalize_foreign_url() {
	case "$1" in
		http://*|https://*)
			printf '%s\n' "$1"
			;;
		*)
			printf 'https://%s\n' "$1"
			;;
	esac
}

ensure_runtime_state() {
	local domestic
	local foreign
	local proxy_type
	local proxy_host
	local proxy_port
	local domestic_interval
	local foreign_interval

	mkdir -p "$RUN_DIR"

	if [ ! -s "$START_TIME_FILE" ]; then
		date '+%Y-%m-%d %H:%M:%S' > "$START_TIME_FILE"
	fi

	if [ -f "$RUN_DIR/config" ]; then
		return 0
	fi

	if ! command -v uci >/dev/null 2>&1; then
		return 0
	fi

	domestic="$(uci -q get pingpacket.config.domestic_target)"
	foreign="$(uci -q get pingpacket.config.foreign_target)"
	proxy_type="$(uci -q get pingpacket.config.foreign_proxy_type)"
	proxy_host="$(uci -q get pingpacket.config.foreign_proxy_host)"
	proxy_port="$(uci -q get pingpacket.config.foreign_proxy_port)"
	domestic_interval="$(uci -q get pingpacket.config.domestic_interval)"
	foreign_interval="$(uci -q get pingpacket.config.foreign_interval)"

	proxy_type="socks5h"
	[ -n "$proxy_host" ] || proxy_host="127.0.0.1"
	[ -n "$proxy_port" ] || proxy_port="7891"
	[ -n "$domestic_interval" ] || domestic_interval="1"
	[ -n "$foreign_interval" ] || foreign_interval="5"

	printf '%s\n' "$domestic" > "$RUN_DIR/config"
	printf '%s\n' "$foreign" >> "$RUN_DIR/config"
	printf '%s\n' "$proxy_type" >> "$RUN_DIR/config"
	printf '%s\n' "$proxy_host" >> "$RUN_DIR/config"
	printf '%s\n' "$proxy_port" >> "$RUN_DIR/config"
	printf '%s\n' "$domestic_interval" >> "$RUN_DIR/config"
	printf '%s\n' "$foreign_interval" >> "$RUN_DIR/config"
}

normalize_interval() {
	local value="$1"

	case "$value" in
		""|*[!0-9]*)
			printf '1\n'
			return 0
			;;
	esac

	if [ "$value" -ge 1 ] 2>/dev/null; then
		printf '%s\n' "$value"
	else
		printf '1\n'
	fi
}

should_probe_now() {
	local last_probe_at="${1:-0}"
	local interval="${2:-1}"
	local now_ts="${3:-0}"

	if [ "$last_probe_at" -le 0 ] 2>/dev/null; then
		return 0
	fi

	if [ $((now_ts - last_probe_at)) -ge "$interval" ] 2>/dev/null; then
		return 0
	fi

	return 1
}

is_ip_literal() {
	case "$1" in
		*:*|*.*)
			printf '%s\n' "$1" | awk '
				/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { found=1 }
				/^[0-9A-Fa-f:]+$/ { found=1 }
				END { exit(found ? 0 : 1) }
			'
			;;
		*)
			return 1
			;;
	esac
}

resolve_target_ip() {
	local target="$1"
	local name="$2"
	local cache_target_file="$RUN_DIR/${name}_resolved_target"
	local cache_ip_file="$RUN_DIR/${name}_resolved_ip"
	local cache_time_file="$RUN_DIR/${name}_resolved_at"
	local cached_target
	local cached_ip
	local cached_time
	local now
	local resolved_ip=""

	if is_ip_literal "$target"; then
		printf '%s\n' "$target"
		return 0
	fi

	cached_target="$(cat "$cache_target_file" 2>/dev/null || echo "")"
	cached_ip="$(cat "$cache_ip_file" 2>/dev/null || echo "")"
	cached_time="$(cat "$cache_time_file" 2>/dev/null || echo "")"
	now="$(date '+%s' 2>/dev/null || echo 0)"

	if [ "$cached_target" = "$target" ] && [ -n "$cached_ip" ] && [ -n "$cached_time" ]; then
		if [ $((now - cached_time)) -lt 300 ] 2>/dev/null; then
			printf '%s\n' "$cached_ip"
			return 0
		fi
	fi

	if command -v resolveip >/dev/null 2>&1; then
		resolved_ip="$(
			resolveip -4 -t 3 "$target" 2>/dev/null | awk '
				{
					for (i = 1; i <= NF; i++) {
						if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
							print $i
							exit
						}
					}
				}
			'
		)"
	fi

	if [ -z "$resolved_ip" ] && command -v nslookup >/dev/null 2>&1; then
		resolved_ip="$(
			nslookup "$target" 2>/dev/null | awk '
				{
					for (i = 1; i <= NF; i++) {
						if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
							print $i
							exit
						}
					}
				}
			'
		)"
	fi

	if [ -n "$resolved_ip" ]; then
		printf '%s\n' "$target" > "$cache_target_file"
		printf '%s\n' "$resolved_ip" > "$cache_ip_file"
		printf '%s\n' "$now" > "$cache_time_file"
		printf '%s\n' "$resolved_ip"
		return 0
	fi

	if [ "$cached_target" = "$target" ] && [ -n "$cached_ip" ]; then
		printf '%s\n' "$cached_ip"
		return 0
	fi

	printf '%s\n' "$target"
}

do_ping() {
	local target="$1"
	local name="$2"
	local result_file="$RUN_DIR/${name}_last_result"
	local ping_target
	local result
	local rtt

	ping_target="$(resolve_target_ip "$target" "$name")"
	result="$(ping -n -c 1 -W 2 "$ping_target" 2>/dev/null)"
	if echo "$result" | grep -q "bytes from"; then
		rtt="$(echo "$result" | sed -n 's/.*time=\([0-9.]*\).*/\1/p')"
		write_result_file "$result_file" "1" "${rtt:-0}" ""
	else
		write_result_file "$result_file" "0" "" "ping 无响应"
	fi
}

do_proxy_curl() {
	local target="$1"
	local proxy_type="$2"
	local proxy_host="${3:-127.0.0.1}"
	local proxy_port="$4"
	local name="$5"
	local result_file="$RUN_DIR/${name}_last_result"
	local error_file="$RUN_DIR/${name}_curl_error"
	local url
	local proxy_addr
	local curl_result
	local http_code
	local time_pretransfer
	local rtt_ms
	local detail
	local rc

	if ! command -v curl >/dev/null 2>&1; then
		write_result_file "$result_file" "0" "" "系统未安装 curl"
		return 0
	fi

	if [ -z "$proxy_port" ]; then
		write_result_file "$result_file" "0" "" "代理端口未配置"
		return 0
	fi

	url="$(normalize_foreign_url "$target")"
	proxy_addr="${proxy_host}:${proxy_port}"

	curl_result="$(
		curl -k -I -L -sS --noproxy "" \
			--connect-timeout 5 --max-time 10 \
			--socks5-hostname "$proxy_addr" \
			-o /dev/null -w '%{http_code}:%{time_pretransfer}' \
			"$url" 2>"$error_file"
	)"
	rc=$?

	http_code="$(printf '%s' "$curl_result" | awk -F ':' 'NR==1 { print $1 }')"
	time_pretransfer="$(printf '%s' "$curl_result" | awk -F ':' 'NR==1 { print $2 }')"

	if [ "$rc" -eq 0 ] && [ -n "$http_code" ] && [ -n "$time_pretransfer" ] && { [ "$http_code" = "200" ] || [ "$http_code" = "204" ]; }; then
		rtt_ms="$(awk -v sec="$time_pretransfer" 'BEGIN { printf "%.1f", (sec + 0) * 1000 }')"
		write_result_file "$result_file" "1" "$rtt_ms" "curl 连接探测成功，HTTP ${http_code}"
	else
		detail="$(sed -n '1p' "$error_file" 2>/dev/null)"
		[ -n "$detail" ] || detail="curl 退出码 ${rc}，HTTP ${http_code:-000}"
		write_result_file "$result_file" "0" "" "$detail"
	fi

	rm -f "$error_file"
}

get_target_state() {
	local name="$1"

	case "$name" in
		domestic)
			fail_count="$domestic_fail_count"
			fault_open="$domestic_fault_open"
			;;
		foreign)
			fail_count="$foreign_fail_count"
			fault_open="$foreign_fault_open"
			;;
		*)
			fail_count=0
			fault_open=0
			;;
	esac
}

set_target_state() {
	local name="$1"
	local next_fail_count="$2"
	local next_fault_open="$3"

	case "$name" in
		domestic)
			domestic_fail_count="$next_fail_count"
			domestic_fault_open="$next_fault_open"
			;;
		foreign)
			foreign_fail_count="$next_fail_count"
			foreign_fault_open="$next_fault_open"
			;;
	esac
}

get_processed_probe_at() {
	local name="$1"
	local kind="$2"

	case "${name}:${kind}" in
		domestic:fault)
			processed_probe_at="$domestic_last_fault_probe_at"
			;;
		foreign:fault)
			processed_probe_at="$foreign_last_fault_probe_at"
			;;
		domestic:stats)
			processed_probe_at="$domestic_last_stats_probe_at"
			;;
		foreign:stats)
			processed_probe_at="$foreign_last_stats_probe_at"
			;;
		*)
			processed_probe_at=0
			;;
	esac
}

set_processed_probe_at() {
	local name="$1"
	local kind="$2"
	local value="${3:-0}"

	case "${name}:${kind}" in
		domestic:fault)
			domestic_last_fault_probe_at="$value"
			;;
		foreign:fault)
			foreign_last_fault_probe_at="$value"
			;;
		domestic:stats)
			domestic_last_stats_probe_at="$value"
			;;
		foreign:stats)
			foreign_last_stats_probe_at="$value"
			;;
	esac
}

reset_target_state() {
	local name="$1"

	rm -f "$RUN_DIR/${name}_last_result"
	set_target_state "$name" 0 0
	set_processed_probe_at "$name" "fault" 0
	set_processed_probe_at "$name" "stats" 0
}

update_target_faults() {
	local name="$1"
	local label="$2"
	local target="$3"
	local result_file="$RUN_DIR/${name}_last_result"
	local success="0"
	local rtt=""
	local detail=""
	local probe_at=""

	[ -n "$target" ] || {
		reset_target_state "$name"
		return 0
	}

	get_target_state "$name"

	if [ -f "$result_file" ]; then
		success="$(sed -n '1p' "$result_file" 2>/dev/null)"
		rtt="$(sed -n '2p' "$result_file" 2>/dev/null)"
		detail="$(sed -n '3p' "$result_file" 2>/dev/null)"
		probe_at="$(sed -n '4p' "$result_file" 2>/dev/null)"
	fi

	get_processed_probe_at "$name" "fault"
	if [ -n "$probe_at" ] && [ "$probe_at" = "$processed_probe_at" ]; then
		return 0
	fi

	if [ "$success" = "1" ]; then
		if [ "$fault_open" = "1" ]; then
			log_event "恢复" "$label" "目标 ${target} 已恢复响应，当前延迟 ${rtt:-0} ms"
		fi

		set_target_state "$name" 0 0
		set_processed_probe_at "$name" "fault" "${probe_at:-0}"
		return 0
	fi

	fail_count=$((fail_count + 1))
	if [ -n "$detail" ]; then
		log_event "丢包" "$label" "目标 ${target} 本次探测失败（连续第 ${fail_count} 次）：${detail}"
	else
		log_event "丢包" "$label" "目标 ${target} 本次探测失败（连续第 ${fail_count} 次）"
	fi
	fault_open=1

	set_target_state "$name" "$fail_count" "$fault_open"
	set_processed_probe_at "$name" "fault" "${probe_at:-0}"
}

calc_stats() {
	local name="$1"
	local total_samples=0
	local success_count=0
	local loss_count=0
	local rtt_sum="0"
	local min_rtt=""
	local max_rtt=""
	local avg="0.0"
	local min="0.0"
	local max="0.0"
	local loss_rate="0.0"

	case "$name" in
		domestic)
			total_samples="$domestic_total_samples"
			success_count="$domestic_success_count"
			loss_count="$domestic_loss_count"
			rtt_sum="$domestic_rtt_sum"
			min_rtt="$domestic_min_rtt"
			max_rtt="$domestic_max_rtt"
			;;
		foreign)
			total_samples="$foreign_total_samples"
			success_count="$foreign_success_count"
			loss_count="$foreign_loss_count"
			rtt_sum="$foreign_rtt_sum"
			min_rtt="$foreign_min_rtt"
			max_rtt="$foreign_max_rtt"
			;;
	esac

	if [ "$success_count" -gt 0 ]; then
		avg="$(awk -v sum="$rtt_sum" -v count="$success_count" 'BEGIN { printf "%.1f", (sum + 0) / count }')"
		min="$(awk -v value="${min_rtt:-0}" 'BEGIN { printf "%.1f", value + 0 }')"
		max="$(awk -v value="${max_rtt:-0}" 'BEGIN { printf "%.1f", value + 0 }')"
	fi

	if [ "$total_samples" -gt 0 ]; then
		loss_rate="$(awk -v loss="$loss_count" -v total="$total_samples" 'BEGIN { printf "%.1f", loss * 100.0 / total }')"
	fi

	printf '{"avg":"%s","min":"%s","max":"%s","loss_rate":"%s","loss_count":%d,"count":%d,"samples":%d}' \
		"$avg" "$min" "$max" "$loss_rate" "$loss_count" "$success_count" "$total_samples"
}

update_cumulative_stats() {
	local name="$1"
	local target="$2"
	local result_file="$RUN_DIR/${name}_last_result"
	local success="0"
	local rtt=""
	local probe_at=""
	local total_samples=0
	local success_count=0
	local loss_count=0
	local rtt_sum="0"
	local min_rtt=""
	local max_rtt=""

	[ -n "$target" ] || return 0

	case "$name" in
		domestic)
			total_samples="$domestic_total_samples"
			success_count="$domestic_success_count"
			loss_count="$domestic_loss_count"
			rtt_sum="$domestic_rtt_sum"
			min_rtt="$domestic_min_rtt"
			max_rtt="$domestic_max_rtt"
			;;
		foreign)
			total_samples="$foreign_total_samples"
			success_count="$foreign_success_count"
			loss_count="$foreign_loss_count"
			rtt_sum="$foreign_rtt_sum"
			min_rtt="$foreign_min_rtt"
			max_rtt="$foreign_max_rtt"
			;;
	esac

	total_samples=$((total_samples + 1))

	if [ -f "$result_file" ]; then
		success="$(sed -n '1p' "$result_file" 2>/dev/null)"
		rtt="$(sed -n '2p' "$result_file" 2>/dev/null)"
		probe_at="$(sed -n '4p' "$result_file" 2>/dev/null)"
	fi

	get_processed_probe_at "$name" "stats"
	if [ -n "$probe_at" ] && [ "$probe_at" = "$processed_probe_at" ]; then
		return 0
	fi

	if [ "$success" = "1" ]; then
		rtt="${rtt:-0}"
		success_count=$((success_count + 1))
		rtt_sum="$(awk -v sum="$rtt_sum" -v value="$rtt" 'BEGIN { printf "%.3f", (sum + 0) + (value + 0) }')"

		if [ -z "$min_rtt" ]; then
			min_rtt="$rtt"
		else
			min_rtt="$(awk -v current="$min_rtt" -v value="$rtt" 'BEGIN { printf "%.3f", ((value + 0) < (current + 0)) ? (value + 0) : (current + 0) }')"
		fi

		if [ -z "$max_rtt" ]; then
			max_rtt="$rtt"
		else
			max_rtt="$(awk -v current="$max_rtt" -v value="$rtt" 'BEGIN { printf "%.3f", ((value + 0) > (current + 0)) ? (value + 0) : (current + 0) }')"
		fi
	else
		loss_count=$((loss_count + 1))
	fi

	case "$name" in
		domestic)
			domestic_total_samples="$total_samples"
			domestic_success_count="$success_count"
			domestic_loss_count="$loss_count"
			domestic_rtt_sum="$rtt_sum"
			domestic_min_rtt="$min_rtt"
			domestic_max_rtt="$max_rtt"
			;;
		foreign)
			foreign_total_samples="$total_samples"
			foreign_success_count="$success_count"
			foreign_loss_count="$loss_count"
			foreign_rtt_sum="$rtt_sum"
			foreign_min_rtt="$min_rtt"
			foreign_max_rtt="$max_rtt"
			;;
	esac

	set_processed_probe_at "$name" "stats" "${probe_at:-0}"
}

while true; do
	ensure_runtime_state
	START_TIME="$(cat "$START_TIME_FILE" 2>/dev/null || echo "")"
	UPDATED_AT="$(date '+%Y-%m-%d %H:%M:%S')"
	NOW_TS="$(date '+%s' 2>/dev/null || echo 0)"
	DOMESTIC_TARGET=""
	FOREIGN_TARGET=""
	FOREIGN_PROXY_TYPE="socks5h"
	FOREIGN_PROXY_HOST="127.0.0.1"
	FOREIGN_PROXY_PORT="7891"
	DOMESTIC_INTERVAL="1"
	FOREIGN_INTERVAL="5"

	if [ -f "$RUN_DIR/config" ]; then
		DOMESTIC_TARGET="$(sed -n '1p' "$RUN_DIR/config")"
		FOREIGN_TARGET="$(sed -n '2p' "$RUN_DIR/config")"
		FOREIGN_PROXY_TYPE="$(sed -n '3p' "$RUN_DIR/config")"
		FOREIGN_PROXY_HOST="$(sed -n '4p' "$RUN_DIR/config")"
		FOREIGN_PROXY_PORT="$(sed -n '5p' "$RUN_DIR/config")"
		DOMESTIC_INTERVAL="$(sed -n '6p' "$RUN_DIR/config")"
		FOREIGN_INTERVAL="$(sed -n '7p' "$RUN_DIR/config")"
	fi

	FOREIGN_PROXY_TYPE="socks5h"
	[ -n "$FOREIGN_PROXY_HOST" ] || FOREIGN_PROXY_HOST="127.0.0.1"
	[ -n "$FOREIGN_PROXY_PORT" ] || FOREIGN_PROXY_PORT="7891"
	[ -n "$FOREIGN_INTERVAL" ] || FOREIGN_INTERVAL="5"
	DOMESTIC_INTERVAL="$(normalize_interval "$DOMESTIC_INTERVAL")"
	FOREIGN_INTERVAL="$(normalize_interval "$FOREIGN_INTERVAL")"

	child_pids=""
	if [ -n "$DOMESTIC_TARGET" ]; then
		if should_probe_now "$domestic_last_probe_at" "$DOMESTIC_INTERVAL" "$NOW_TS"; then
			do_ping "$DOMESTIC_TARGET" "domestic" &
			child_pids="$!"
			domestic_last_probe_at="$NOW_TS"
		fi
	else
		domestic_last_probe_at=0
		reset_target_state "domestic"
	fi

	if [ -n "$FOREIGN_TARGET" ]; then
		if should_probe_now "$foreign_last_probe_at" "$FOREIGN_INTERVAL" "$NOW_TS"; then
			do_proxy_curl "$FOREIGN_TARGET" "$FOREIGN_PROXY_TYPE" "$FOREIGN_PROXY_HOST" "$FOREIGN_PROXY_PORT" "foreign" &
			child_pids="${child_pids:+$child_pids }$!"
			foreign_last_probe_at="$NOW_TS"
		fi
	else
		foreign_last_probe_at=0
		reset_target_state "foreign"
	fi

	[ -n "$child_pids" ] && wait $child_pids 2>/dev/null
	child_pids=""

	update_target_faults "domestic" "国内" "$DOMESTIC_TARGET"
	update_target_faults "foreign" "国外" "$FOREIGN_TARGET"
	update_cumulative_stats "domestic" "$DOMESTIC_TARGET"
	update_cumulative_stats "foreign" "$FOREIGN_TARGET"

	DOMESTIC_STATS="$(calc_stats "domestic")"
	FOREIGN_STATS="$(calc_stats "foreign")"

	printf '{"start_time":"%s","updated_at":"%s","domestic":%s,"foreign":%s}\n' \
		"$START_TIME" "$UPDATED_AT" "$DOMESTIC_STATS" "$FOREIGN_STATS" > "$STATUS_TMP" && \
		mv -f "$STATUS_TMP" "$STATUS_FILE"

	sleep 1
done

