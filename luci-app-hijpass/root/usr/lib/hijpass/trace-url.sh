#!/bin/sh

SCRIPT_NAME="${0##*/}"

TIMEOUT=8
CLIENT_IP=
METHOD=HEAD
KEEP_TMP=0
VERBOSE=0
ENABLE_TCPDUMP=0
TCPDUMP_IFACE=any

usage() {
    cat <<EOF
Usage:
  $SCRIPT_NAME [-t seconds] [-X HEAD|GET] [-p] [-i iface] [-v] [-K] <url>
  $SCRIPT_NAME -c <client_ip> [-t seconds] [-p] [-i iface] [-v] [-K] <url>

Modes:
  default        Run curl on this router and trace hijpass out-route.
  -c client_ip  Trace hijpass pre-filter for a real request from the client.

Examples:
  $SCRIPT_NAME https://www.gstatic.com/generate_204
  $SCRIPT_NAME -p https://www.gstatic.com/generate_204
  $SCRIPT_NAME -p -i pppoe-wan https://www.gstatic.com/generate_204
  $SCRIPT_NAME -c 192.168.1.100 https://www.gstatic.com/generate_204

Notes:
  The default request is TCP HEAD. For transparent LAN traffic, use -c and
  run a matching curl request from the client during the trace window.
  Use -p to enable tcpdump packet capture. The default tcpdump interface is any.
  Use -v to print raw trace and log lines.
EOF
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

is_number() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

is_port() {
    is_number "$1" || return 1
    [ "$1" -ge 1 ] 2>/dev/null && [ "$1" -le 65535 ] 2>/dev/null
}

is_ipv4() {
    printf '%s\n' "$1" | awk -F. '
        NF != 4 { exit 1 }
        {
            for (i = 1; i <= 4; i++) {
                if ($i !~ /^[0-9]+$/ || $i < 0 || $i > 255) {
                    exit 1
                }
            }
        }
    '
}

is_ipv6() {
    case "$1" in
        *:*) return 0 ;;
        *) return 1 ;;
    esac
}

ip_family() {
    if is_ipv4 "$1"; then
        printf '4\n'
    elif is_ipv6 "$1"; then
        printf '6\n'
    else
        return 1
    fi
}

upper() {
    printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

while getopts 'c:t:X:i:Kpvh' opt; do
    case "$opt" in
        c) CLIENT_IP="$OPTARG" ;;
        t) TIMEOUT="$OPTARG" ;;
        X) METHOD="$(upper "$OPTARG")" ;;
        i) TCPDUMP_IFACE="$OPTARG" ;;
        K) KEEP_TMP=1 ;;
        p) ENABLE_TCPDUMP=1 ;;
        v) VERBOSE=1 ;;
        h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
done
shift $((OPTIND - 1))

[ "$#" -eq 1 ] || {
    usage >&2
    exit 2
}

URL="$1"
MODE=router
[ -n "$CLIENT_IP" ] && MODE=client

case "$METHOD" in
    HEAD|GET) ;;
    *) die "method must be HEAD or GET" ;;
esac

is_number "$TIMEOUT" || die "timeout must be an integer"
[ "$TIMEOUT" -ge 1 ] 2>/dev/null || die "timeout must be >= 1"

if [ -n "$CLIENT_IP" ]; then
    ip_family "$CLIENT_IP" >/dev/null || die "invalid client IP: $CLIENT_IP"
fi
case "$TCPDUMP_IFACE" in
    ''|*[!A-Za-z0-9_.:@-]*)
        die "invalid tcpdump interface: $TCPDUMP_IFACE"
        ;;
esac

has_cmd awk || die "awk is required"
has_cmd curl || die "curl is required"
has_cmd nft || die "nft is required"
if [ "$ENABLE_TCPDUMP" -eq 1 ]; then
    has_cmd tcpdump || die "tcpdump is required when -p is used"
fi

[ "$(id -u)" = "0" ] || die "must run as root"
nft list table inet hijpass >/dev/null 2>&1 || die "nft table inet hijpass not found"

parse_url() {
    case "$URL" in
        https://*)
            SCHEME=https
            PORT=443
            REST="${URL#https://}"
            ;;
        http://*)
            SCHEME=http
            PORT=80
            REST="${URL#http://}"
            ;;
        *)
            die "only http:// and https:// URLs are supported"
            ;;
    esac

    HOSTPORT="${REST%%/*}"
    [ -n "$HOSTPORT" ] || die "URL host is empty"

    case "$HOSTPORT" in
        \[*\]*)
            HOST="${HOSTPORT#\[}"
            HOST="${HOST%%\]*}"
            AFTER_BRACKET="${HOSTPORT#*\]}"
            case "$AFTER_BRACKET" in
                :*) PORT="${AFTER_BRACKET#:}" ;;
                '') ;;
                *) die "invalid IPv6 host/port: $HOSTPORT" ;;
            esac
            ;;
        *:*)
            LAST_PART="${HOSTPORT##*:}"
            PREFIX_PART="${HOSTPORT%:*}"
            if is_number "$LAST_PART"; then
                case "$PREFIX_PART" in
                    *:*) HOST="$HOSTPORT" ;;
                    *)
                        HOST="$PREFIX_PART"
                        PORT="$LAST_PART"
                        ;;
                esac
            else
                HOST="$HOSTPORT"
            fi
            ;;
        *)
            HOST="$HOSTPORT"
            ;;
    esac

    [ -n "$HOST" ] || die "URL host is empty"
    case "$HOST" in
        *[!A-Za-z0-9_.:-]*)
            die "unsupported URL host: $HOST"
            ;;
    esac
    is_port "$PORT" || die "invalid URL port: $PORT"
}

resolve_host() {
    if is_ipv4 "$HOST" || is_ipv6 "$HOST"; then
        printf '%s\n' "$HOST"
        return 0
    fi

    has_cmd nslookup || return 0

    nslookup "$HOST" 2>/dev/null | awk '
        /^Name:/ { answer = 1; next }
        answer && /^Address[[:space:]][0-9]+:/ { print $3; next }
        answer && /^Address:/ { print $2; next }
    ' | sed 's/%.*//' | awk '
        index($0, ".") || index($0, ":") {
            if (!seen[$0]++) print
        }
    '
}

parse_url

TARGET_IPS=

TMP_DIR="${TMPDIR:-/tmp}/hijpass-trace.$$"
NFT_LOG="$TMP_DIR/nft.trace"
NFT_SETUP_LOG="$TMP_DIR/nft.setup"
SYS_LOG="$TMP_DIR/system.log"
CURL_OUT="$TMP_DIR/curl.out"
CURL_ERR="$TMP_DIR/curl.err"
CURL_HDR="$TMP_DIR/curl.headers"
LOG_INDEX="$TMP_DIR/log-files.index"
SERVICE_LOG="$TMP_DIR/service.log"
TCPDUMP_LOG="$TMP_DIR/tcpdump.log"
TCPDUMP_ERR="$TMP_DIR/tcpdump.err"
TCPDUMP_FILTER=
TRACE_COMMENT="hijpass-trace-$$"
NFT_PID=
LOG_PID=
TCPDUMP_PID=
CLEANED=0

mkdir -p "$TMP_DIR" || die "failed to create $TMP_DIR"
: >"$NFT_LOG"
: >"$NFT_SETUP_LOG"
: >"$SYS_LOG"
: >"$CURL_OUT"
: >"$CURL_ERR"
: >"$CURL_HDR"
: >"$LOG_INDEX"
: >"$SERVICE_LOG"
: >"$TCPDUMP_LOG"
: >"$TCPDUMP_ERR"

delete_trace_rules() {
    for chain in pre-filter out-route; do
        nft -a list chain inet hijpass "$chain" 2>/dev/null |
            awk -v c="$TRACE_COMMENT" '
                index($0, "comment \"" c "\"") {
                    for (i = 1; i <= NF; i++) {
                        if ($i == "handle") print $(i + 1)
                    }
                }
            ' |
            while read -r handle; do
                [ -n "$handle" ] || continue
                nft delete rule inet hijpass "$chain" handle "$handle" >/dev/null 2>&1
            done
    done
}

cleanup() {
    [ "$CLEANED" -eq 1 ] && return
    CLEANED=1

    [ -n "$NFT_PID" ] && kill "$NFT_PID" >/dev/null 2>&1
    [ -n "$LOG_PID" ] && kill "$LOG_PID" >/dev/null 2>&1
    [ -n "$TCPDUMP_PID" ] && kill "$TCPDUMP_PID" >/dev/null 2>&1
    [ -n "$NFT_PID" ] && wait "$NFT_PID" >/dev/null 2>&1
    [ -n "$LOG_PID" ] && wait "$LOG_PID" >/dev/null 2>&1
    [ -n "$TCPDUMP_PID" ] && wait "$TCPDUMP_PID" >/dev/null 2>&1

    delete_trace_rules

    if [ "$KEEP_TMP" -eq 0 ]; then
        rm -rf "$TMP_DIR"
    else
        printf '\nTemporary files kept: %s\n' "$TMP_DIR"
    fi
}

trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

add_nft_rule() {
    chain="$1"
    shift
    nft insert rule inet hijpass "$chain" "$@" meta nftrace set 1 comment "$TRACE_COMMENT" \
        >>"$NFT_SETUP_LOG" 2>&1
}

target_expr_family() {
    family="$(ip_family "$1" 2>/dev/null || true)"
    case "$family" in
        4) printf 'ip daddr\n' ;;
        6) printf 'ip6 daddr\n' ;;
        *) return 1 ;;
    esac
}

client_expr_family() {
    family="$(ip_family "$1" 2>/dev/null || true)"
    case "$family" in
        4) printf 'ip saddr\n' ;;
        6) printf 'ip6 saddr\n' ;;
        *) return 1 ;;
    esac
}

add_router_trace_rules() {
    for target_ip in $TARGET_IPS; do
        expr="$(target_expr_family "$target_ip" || true)"
        [ -n "$expr" ] || continue
        set -- $expr "$target_ip" tcp dport "$PORT"
        add_nft_rule out-route "$@"
    done

    # Also trace the router-local destination port. Curl may use an address
    # family different from the router-side nslookup result.
    add_nft_rule out-route tcp dport "$PORT" || return 1
}

add_client_trace_rules() {
    client_expr="$(client_expr_family "$CLIENT_IP" || true)"
    [ -n "$client_expr" ] || return 1
    set -- $client_expr "$CLIENT_IP" tcp dport "$PORT"

    # Keep one broad client+port rule so the trace still works when the
    # client resolves the host to a different address than the router.
    add_nft_rule pre-filter "$@" || return 1
}

collect_log_paths() {
    has_cmd uci || return 0

    uci -q show hijpass 2>/dev/null |
        sed -n "s/^hijpass\\..*\\.log_path='\\([^']*\\)'$/\\1/p; s/^hijpass\\..*\\.log_path=\\([^']*\\)$/\\1/p" |
        awk 'NF && !seen[$0]++'
}

snapshot_log_positions() {
    collect_log_paths | while read -r log_path; do
        [ -f "$log_path" ] || continue
        line_count="$(wc -l <"$log_path" 2>/dev/null | tr -d ' ')"
        is_number "$line_count" || line_count=0
        printf '%s %s\n' "$line_count" "$log_path" >>"$LOG_INDEX"
    done
}

collect_new_service_logs() {
    : >"$SERVICE_LOG"
    while read -r line_count log_path; do
        [ -n "$line_count" ] || continue
        [ -f "$log_path" ] || continue
        start_line=$((line_count + 1))
        {
            printf -- '--- %s ---\n' "$log_path"
            tail -n +"$start_line" "$log_path" 2>/dev/null
        } >>"$SERVICE_LOG"
    done <"$LOG_INDEX"
}

start_monitors() {
    nft monitor trace >"$NFT_LOG" 2>&1 &
    NFT_PID="$!"

    if has_cmd logread; then
        logread -f >"$SYS_LOG" 2>&1 &
        LOG_PID="$!"
    fi
}

stop_monitors() {
    [ -n "$NFT_PID" ] && kill "$NFT_PID" >/dev/null 2>&1
    [ -n "$LOG_PID" ] && kill "$LOG_PID" >/dev/null 2>&1
    [ -n "$NFT_PID" ] && wait "$NFT_PID" >/dev/null 2>&1
    [ -n "$LOG_PID" ] && wait "$LOG_PID" >/dev/null 2>&1
    NFT_PID=
    LOG_PID=
}

tcpdump_filter() {
    # Keep capture broad enough to include proxy outbound traffic using the
    # same destination port. Output is filtered later to keep the report short.
    printf 'tcp and port %s\n' "$PORT"
}

start_tcpdump() {
    [ "$ENABLE_TCPDUMP" -eq 1 ] || return 0

    TCPDUMP_FILTER="$(tcpdump_filter)"
    tcpdump -p -i "$TCPDUMP_IFACE" -nn -tt -l -s 96 "$TCPDUMP_FILTER" \
        >"$TCPDUMP_LOG" 2>"$TCPDUMP_ERR" &
    TCPDUMP_PID="$!"

    sleep 1
    if ! kill -0 "$TCPDUMP_PID" >/dev/null 2>&1; then
        wait "$TCPDUMP_PID" >/dev/null 2>&1
        TCPDUMP_PID=
        return 1
    fi
}

stop_tcpdump() {
    [ -n "$TCPDUMP_PID" ] || return 0
    kill "$TCPDUMP_PID" >/dev/null 2>&1
    wait "$TCPDUMP_PID" >/dev/null 2>&1
    TCPDUMP_PID=
}

run_router_curl() {
    if [ "$METHOD" = "HEAD" ]; then
        curl -I -L -k -sS -o /dev/null -D "$CURL_HDR" \
            --connect-timeout "$TIMEOUT" \
            --max-time "$TIMEOUT" \
            -w 'url_effective=%{url_effective}
http_code=%{http_code}
remote_ip=%{remote_ip}
remote_port=%{remote_port}
time_namelookup=%{time_namelookup}
time_connect=%{time_connect}
time_appconnect=%{time_appconnect}
time_starttransfer=%{time_starttransfer}
time_total=%{time_total}
' "$URL" >"$CURL_OUT" 2>"$CURL_ERR"
    else
        curl -L -k -sS -o /dev/null -D "$CURL_HDR" \
            --connect-timeout "$TIMEOUT" \
            --max-time "$TIMEOUT" \
            -w 'url_effective=%{url_effective}
http_code=%{http_code}
remote_ip=%{remote_ip}
remote_port=%{remote_port}
time_namelookup=%{time_namelookup}
time_connect=%{time_connect}
time_appconnect=%{time_appconnect}
time_starttransfer=%{time_starttransfer}
time_total=%{time_total}
' "$URL" >"$CURL_OUT" 2>"$CURL_ERR"
    fi
    printf '%s\n' "$?" >"$TMP_DIR/curl.exit"
}

wait_for_client_request() {
    printf 'Trace is active for %s seconds.\n' "$TIMEOUT"
    printf 'Run this from client %s now:\n' "$CLIENT_IP"
    printf '  curl -I -k %s\n' "$URL"
    sleep "$TIMEOUT"
}

print_section() {
    printf '\n== %s ==\n' "$1"
}

get_curl_value() {
    awk -F= -v key="$1" '$1 == key { print substr($0, length(key) + 2) }' "$CURL_OUT" 2>/dev/null | tail -n 1
}

format_target_ips() {
    if [ -z "$TARGET_IPS" ]; then
        printf 'unavailable'
        return
    fi

    printf '%s\n' "$TARGET_IPS" | awk '
        NF {
            count++
            if (count <= 6) {
                out = out ? out ", " $0 : $0
            }
        }
        END {
            if (count > 6) {
                out = out ", +" (count - 6) " more"
            }
            print out
        }
    '
}

limit_unique_lines() {
    awk -v max="$1" 'NF && !seen[$0]++ { print; if (++count >= max) exit }'
}

print_request_summary() {
    print_section "Trace summary"
    if [ "$MODE" = "client" ]; then
        printf 'mode: client pre-filter, client=%s\n' "$CLIENT_IP"
    else
        printf 'mode: router out-route\n'
    fi
    printf 'request: %s %s\n' "$METHOD" "$URL"
    printf 'target: %s:%s (%s)\n' "$HOST" "$PORT" "$(format_target_ips)"

    if [ "$MODE" = "client" ]; then
        printf 'curl: not run by this script in client mode\n'
        return
    fi

    curl_exit="$(cat "$TMP_DIR/curl.exit" 2>/dev/null || printf '?')"
    http_code="$(get_curl_value http_code)"
    remote_ip="$(get_curl_value remote_ip)"
    remote_port="$(get_curl_value remote_port)"
    total_time="$(get_curl_value time_total)"

    [ -n "$http_code" ] || http_code="-"
    [ -n "$remote_ip" ] || remote_ip="-"
    [ -n "$remote_port" ] || remote_port="-"
    [ -n "$total_time" ] || total_time="-"

    printf 'curl: exit=%s http=%s remote=%s:%s total=%ss\n' \
        "$curl_exit" "$http_code" "$remote_ip" "$remote_port" "$total_time"

    if [ -s "$CURL_ERR" ]; then
        printf 'curl_error:\n'
        sed -n '1,4p' "$CURL_ERR" | sed 's/^/  /'
    fi
}

firewall_decision() {
    shunt_port="$(uci -q get hijpass.@firewall[0].shunt_port 2>/dev/null || true)"
    proxy_port="$(uci -q get hijpass.@firewall[0].proxy_port 2>/dev/null || true)"

    if grep -q ' reject' "$NFT_LOG"; then
        printf 'rejected by proxy-port-filter or another firewall rule\n'
    elif [ -n "$proxy_port" ] && grep -q "tproxy to :$proxy_port" "$NFT_LOG"; then
        printf 'tproxy to proxy port %s\n' "$proxy_port"
    elif [ -n "$shunt_port" ] && grep -q "tproxy to :$shunt_port" "$NFT_LOG"; then
        printf 'tproxy to shunt port %s\n' "$shunt_port"
    elif grep -q 'ct mark set 0' "$NFT_LOG"; then
        printf 'bypassed by proxy-port-filter or direct rule\n'
    elif grep -q 'comment "shunt mark"' "$NFT_LOG"; then
        printf 'marked for shunt, but final tproxy was not observed\n'
    else
        printf 'unknown from captured trace\n'
    fi
}

trace_path() {
    awk '
        /inet hijpass/ {
            for (i = 1; i <= NF - 2; i++) {
                if ($i == "inet" && $(i + 1) == "hijpass") {
                    chain = $(i + 2)
                    if (!seen[chain]++) {
                        path = path ? path " -> " chain : chain
                    }
                }
            }
        }
        END {
            print path ? path : "unavailable"
        }
    ' "$NFT_LOG"
}

print_trace_steps() {
    awk -v c="$TRACE_COMMENT" '
        index($0, c) { next }
        /inet hijpass/ && / rule / &&
        ($0 ~ /jump|return|tproxy|reject|accept|drop|ct mark set|meta mark set/) {
            line = $0
            sub(/^.*inet hijpass /, "", line)
            gsub(/ counter packets [0-9]+ bytes [0-9]+/, "", line)
            gsub(/ counter/, "", line)
            sub(/ \(verdict.*$/, "", line)
            gsub(/[[:space:]]+/, " ", line)
            if (!seen[line]++) {
                count++
                if (length(line) > 180) {
                    line = substr(line, 1, 177) "..."
                }
                printf "  %d. %s\n", count, line
                if (count >= 14) exit
            }
        }
        END {
            if (count == 0) print "  none"
        }
    ' "$NFT_LOG"
}

print_nft_summary() {
    print_section "Firewall"

    if [ -s "$NFT_SETUP_LOG" ]; then
        printf 'setup_warnings:\n'
        sed 's/^/  /' "$NFT_SETUP_LOG"
    fi

    line_count="$(wc -l <"$NFT_LOG" 2>/dev/null | tr -d ' ')"
    is_number "$line_count" || line_count=0
    printf 'captured: %s nft trace lines\n' "$line_count"

    if [ "$line_count" -eq 0 ]; then
        printf 'decision: no nft trace captured\n'
        printf 'check:\n'
        printf '  - request did not match TCP port %s\n' "$PORT"
        printf '  - client mode was used but no matching client request arrived\n'
        printf '  - traffic was not handled by table inet hijpass\n'
        return
    fi

    printf 'decision: %s\n' "$(firewall_decision)"
    printf 'path: %s\n' "$(trace_path)"
    printf 'key_rules:\n'
    print_trace_steps

    if [ "$VERBOSE" -eq 1 ]; then
        printf 'raw_trace_tail:\n'
        grep -E 'trace id| rule | verdict |tproxy|mark|jump|return|accept|reject|drop' "$NFT_LOG" 2>/dev/null |
            tail -n 80 |
            sed 's/^/  /'
    fi
}

remote_ip_from_curl() {
    get_curl_value remote_ip
}

tcpdump_related_lines() {
    [ -s "$TCPDUMP_LOG" ] || return 1

    remote_ip="$(remote_ip_from_curl)"
    {
        for target_ip in $TARGET_IPS $remote_ip; do
            [ -n "$target_ip" ] && grep -F "$target_ip" "$TCPDUMP_LOG" 2>/dev/null
        done
    } | limit_unique_lines 200
}

tcpdump_clean_errors() {
    [ -s "$TCPDUMP_ERR" ] || return 1
    grep -Eiv 'listening on|verbose output suppressed|packets captured|packets received|packets dropped|promiscuous mode|doesn.t support promiscuous' \
        "$TCPDUMP_ERR" 2>/dev/null
}

print_tcpdump_line_summary() {
    awk '
        NF {
            iface = $2
            dir = $3
            proto = $4
            src = $5
            dst = $7

            if (proto != "IP" && proto != "IP6") {
                iface = "-"
                dir = "-"
                src = $3
                dst = $5
            }

            sub(/:$/, "", dst)

            iface_key = iface "/" dir
            iface_count[iface_key]++
            if (iface == "lo") lo_count++

            flow = src " -> " dst
            flow_count[flow]++

            if ($0 ~ /Flags \[S\]/) syn++
            if ($0 ~ /Flags \[S\.\]/) syn_ack++
            if ($0 ~ /Flags \[F/) fin++
            if ($0 ~ /Flags \[R/) rst++
            if (match($0, /length [0-9]+/)) {
                len = substr($0, RSTART + 7, RLENGTH - 7) + 0
                if (len > 0) {
                    payload_packets++
                    payload_bytes += len
                }
            }
        }
        END {
            if (NR == 0) {
                print "target_summary: none"
                exit
            }

            printf "target_summary:\n"
            printf "  tcp: syn=%d syn_ack=%d fin=%d rst=%d payload_packets=%d payload_bytes=%d\n", syn + 0, syn_ack + 0, fin + 0, rst + 0, payload_packets + 0, payload_bytes + 0

            printf "  interfaces:\n"
            for (key in iface_count) {
                printf "    - %s packets=%d\n", key, iface_count[key]
            }

            printf "  flows:\n"
            shown = 0
            for (key in flow_count) {
                printf "    - %s packets=%d\n", key, flow_count[key]
                shown++
                if (shown >= 6) break
            }

            if (lo_count == NR) {
                print "  note: all related packets were observed on lo; this is expected for tproxy loopback interception"
            }
        }
    '
}

print_tcpdump_summary() {
    [ "$ENABLE_TCPDUMP" -eq 1 ] || return 0

    print_section "Packet capture"
    printf 'interface: %s\n' "$TCPDUMP_IFACE"
    printf 'filter: %s\n' "$TCPDUMP_FILTER"

    tcpdump_errors="$(tcpdump_clean_errors)"
    if [ -n "$tcpdump_errors" ]; then
        printf 'tcpdump_warnings:\n'
        printf '%s\n' "$tcpdump_errors" | sed -n '1,6p' | sed 's/^/  /'
    fi

    packet_total="$(wc -l <"$TCPDUMP_LOG" 2>/dev/null | tr -d ' ')"
    is_number "$packet_total" || packet_total=0

    related="$(tcpdump_related_lines)"
    related_count="$(printf '%s\n' "$related" | awk 'NF { count++ } END { print count + 0 }')"
    other_count=$((packet_total - related_count))
    [ "$other_count" -ge 0 ] 2>/dev/null || other_count=0

    printf 'captured: total=%s related=%s other_same_port=%s\n' \
        "$packet_total" "$related_count" "$other_count"

    if [ "$related_count" -gt 0 ]; then
        printf '%s\n' "$related" | print_tcpdump_line_summary
    else
        printf 'related_packets: none\n'
    fi

    if [ "$other_count" -gt 0 ]; then
        printf 'other_same_port_packets: %s hidden; use -v to inspect possible proxy outbound/noise\n' "$other_count"
    fi

    if [ "$VERBOSE" -eq 1 ] && [ "$packet_total" -gt 0 ]; then
        printf 'raw_packet_tail:\n'
        tail -n 80 "$TCPDUMP_LOG" | sed 's/^/  /'
    fi
}

log_seed_lines() {
    log_file="$1"
    [ -s "$log_file" ] || return 1

    remote_ip="$(remote_ip_from_curl)"
    {
        [ -n "$HOST" ] && grep -F "$HOST" "$log_file" 2>/dev/null
        for target_ip in $TARGET_IPS $remote_ip; do
            [ -n "$target_ip" ] && grep -F "$target_ip" "$log_file" 2>/dev/null
        done
    } | limit_unique_lines 80
}

extract_connection_ids() {
    awk '
        {
            line = $0
            while (match(line, /\[[0-9][0-9]*\]/)) {
                id = substr(line, RSTART + 1, RLENGTH - 2)
                if (!seen[id]++) print id
                line = substr(line, RSTART + RLENGTH)
            }
        }
    '
}

log_related_lines() {
    log_file="$1"
    [ -s "$log_file" ] || return 1

    seeds="$(log_seed_lines "$log_file")"
    [ -n "$seeds" ] || return 1

    ids="$(printf '%s\n' "$seeds" | extract_connection_ids)"
    {
        printf '%s\n' "$seeds"
        for id in $ids; do
            grep -F "[$id]" "$log_file" 2>/dev/null
        done
    } | limit_unique_lines 100
}

print_log_summary() {
    label="$1"
    log_file="$2"

    related="$(log_related_lines "$log_file")"
    [ -n "$related" ] || return 1

    printf '%s:\n' "$label"

    issues="$(printf '%s\n' "$related" | grep -Ei 'error|failed|timeout|warn' 2>/dev/null | limit_unique_lines 8)"
    dns="$(printf '%s\n' "$related" |
        grep -Ei 'dns|lookup|resolve|resolved|query|answer|reply|cache' 2>/dev/null |
        grep -Eiv 'error|failed|timeout|warn' 2>/dev/null |
        limit_unique_lines 12)"
    flow="$(printf '%s\n' "$related" |
        grep -Ei 'inbound|outbound|routing|route|detour|accepted|connection|tproxy|mark' 2>/dev/null |
        grep -Eiv 'error|failed|timeout|warn|dns|lookup|resolve|resolved|query|answer|reply|cache' 2>/dev/null |
        limit_unique_lines 12)"

    if [ -n "$issues" ]; then
        printf '  issues:\n'
        printf '%s\n' "$issues" | sed 's/^/    /'
    fi

    if [ -n "$dns" ]; then
        printf '  dns:\n'
        printf '%s\n' "$dns" | sed 's/^/    /'
    fi

    if [ -n "$flow" ]; then
        printf '  flow:\n'
        printf '%s\n' "$flow" | sed 's/^/    /'
    fi

    if [ -z "$issues" ] && [ -z "$dns" ] && [ -z "$flow" ]; then
        printf '  matched:\n'
        printf '%s\n' "$related" | limit_unique_lines 8 | sed 's/^/    /'
    fi

    if [ "$VERBOSE" -eq 1 ]; then
        printf '  raw_related:\n'
        printf '%s\n' "$related" | sed 's/^/    /'
    fi
}

print_core_logs() {
    print_section "Core logs"

    collect_new_service_logs

    printed=0
    if print_log_summary "service" "$SERVICE_LOG"; then
        printed=1
    fi

    if print_log_summary "system" "$SYS_LOG"; then
        printed=1
    fi

    if [ "$printed" -eq 0 ]; then
        printf 'no related core/system log lines captured\n'
        printf 'hint: enable proxy/shunt logs or raise core log level for more detail\n'
    fi
}

snapshot_log_positions
start_monitors
sleep 1

TARGET_IPS="$(resolve_host)"

if [ "$MODE" = "client" ]; then
    add_client_trace_rules || die "failed to insert nft trace rule; see $NFT_SETUP_LOG"
else
    add_router_trace_rules || die "failed to insert nft trace rule; see $NFT_SETUP_LOG"
fi

if [ "$ENABLE_TCPDUMP" -eq 1 ]; then
    start_tcpdump || die "failed to start tcpdump on $TCPDUMP_IFACE; see $TCPDUMP_ERR"
fi

if [ "$MODE" = "client" ]; then
    wait_for_client_request
else
    run_router_curl
fi

sleep 1
stop_tcpdump
stop_monitors

print_request_summary
print_nft_summary
print_tcpdump_summary
print_core_logs
