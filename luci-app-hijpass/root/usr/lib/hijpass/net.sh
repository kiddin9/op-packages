#!/bin/sh

is_port_value() {
	echo "$1" | grep -Eq "^([0-9]{1,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$" >/dev/null 2>&1
}

is_safe_target() {
	echo "$1" | grep -Eq "^[A-Za-z0-9.-]+$" >/dev/null 2>&1
}

is_ipv4_value() {
	echo "$1" | grep -Eq "^([0-9]{1,3}\.){3}[0-9]{1,3}$" >/dev/null 2>&1
}

is_ipv6_value() {
	echo "$1" | grep -Eq "^[0-9A-Fa-f:]+$" >/dev/null 2>&1 && echo "$1" | grep -q ":" >/dev/null 2>&1
}

json_escape() {
	echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

check_port() {
	if is_port_value "$1"; then
		if netstat -tlnp | grep -q ":$1 " >>/dev/null 2>&1; then
			return 0
		fi
	fi
	return 1
}

# 主函数
main() {
	local action="$1"
	shift
	case "$action" in
	"port")
		local result="{}"
		for p in "$@"; do
			if check_port "$p"; then
				result="$(echo "$result" | jq --arg k "$p" '.[$k] = true')"
			else
				result="$(echo "$result" | jq --arg k "$p" '.[$k] = false')"
			fi
		done
		echo "$result"
		;;
	"ping")
		# $1=socks_port, $2=target (optional, default www.google.com)
		local socks_port="$1"
		local target="${2:-www.google.com}"
		local output
		if ! is_port_value "$socks_port" || ! is_safe_target "$target"; then
			echo "{\"error\":\"invalid argument\"}"
			exit 1
		fi
		output=$(curl -I -o /dev/null -sSk \
			-w '{"t_namelookup":%{time_namelookup},"t_starttransfer":%{time_starttransfer},"t_total":%{time_total}}' \
			--max-time 5 \
			--socks5 "127.0.0.1:${socks_port}" \
			"https://${target}" 2>/dev/null)
		local exit_code=$?
		if [ $exit_code -eq 0 ] || [ $exit_code -eq 56 ]; then
			echo "$output" | jq '{
				ms: ((.t_starttransfer - .t_namelookup) * 1000 | floor),
				total_ms: (.t_total * 1000 | floor)
			}'
		else
			echo "{\"error\":\"timeout\"}"
		fi
		;;
	"resolve")
		local target="$1"
		local address
		if ! is_safe_target "$target" && ! is_ipv6_value "$target"; then
			echo "{\"error\":\"invalid argument\"}"
			exit 1
		fi
		if is_ipv4_value "$target" || is_ipv6_value "$target"; then
			echo "{\"address\":\"$(json_escape "$target")\"}"
			exit 0
		fi
		address=$(nslookup "$target" 2>/dev/null | awk '
			/^Address[[:space:]][0-9]+:[[:space:]]/ { print $3; exit }
			/^Address:[[:space:]]/ && $2 !~ /#/ { print $2; exit }
		')
		if [ -n "$address" ]; then
			echo "{\"address\":\"$(json_escape "$address")\"}"
		else
			echo "{\"error\":\"resolve failed\"}"
			exit 1
		fi
		;;
	*)
		echo -e "Usage: \n    $0 [port|ping|resolve] args"
		exit 1
		;;
	esac
}

main "$@"
