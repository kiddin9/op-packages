#!/bin/sh
NGINX_CONF="/etc/minigate/nginx/minigate.conf"
SITES_DIR="/etc/minigate/nginx/sites"
CERT_DIR="/etc/minigate/certs"
LOGFILE="/var/log/minigate-proxy.log"
PID_FILE="/var/run/minigate-nginx.pid"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [PROXY] $*" >> "$LOGFILE"; }

generate_main_conf() {
    mkdir -p "$(dirname $NGINX_CONF)" "$SITES_DIR"
    cat > "$NGINX_CONF" <<'EOF'
worker_processes auto;
pid /var/run/minigate-nginx.pid;
error_log /var/log/minigate-nginx-error.log warn;
events { worker_connections 512; }
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on; keepalive_timeout 65; client_max_body_size 100m;
    gzip on; gzip_types text/plain text/css application/json application/javascript text/xml;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    log_format minigate_json escape=json
        '{"time":"$time_iso8601",'
        '"domain":"$server_name",'
        '"client":"$remote_addr",'
        '"method":"$request_method",'
        '"uri":"$request_uri",'
        '"status":$status,'
        '"size":$body_bytes_sent,'
        '"referer":"$http_referer",'
        '"ua":"$http_user_agent"}';
    access_log /var/log/minigate-access.log minigate_json;
    include /etc/minigate/nginx/sites/*.conf;
}
EOF
}

find_cert() {
    local domain="$1"
    local parent=$(echo "$domain" | sed 's/^[^.]*\.//')
    for try in "$domain" "_wildcard_.${parent}" "$parent"; do
        [ -f "${CERT_DIR}/${try}/fullchain.pem" ] && { echo "${CERT_DIR}/${try}"; return 0; }
    done
    for try in "$parent" "$domain"; do
        [ -L "${CERT_DIR}/${try}" ] && {
            local t=$(readlink -f "${CERT_DIR}/${try}")
            [ -f "${t}/fullchain.pem" ] && { echo "$t"; return 0; }
        }
    done
    return 1
}

check_h2() {
    local m=$(nginx -v 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f2)
    [ "${m:-0}" -ge 25 ] && echo "new" || echo "old"
}

# 读取全局 IPv6 监听设置
get_ipv6_listen() {
    local v6=$(uci -q get minigate.global.ipv6_listen)
    echo "${v6:-0}"
}

# 写一个完整的 server block（带 proxy_pass），同时支持 IPv6
write_server() {
    local conf="$1" domain="$2" lport="$3" taddr="$4" tport="$5" ssl="$6" h2="$7" ws="$8" h2s="$9"
    shift 9
    local ipv6_listen="${1:-0}"

    log "生成: $domain:${lport} -> ${taddr}:${tport} (ipv6=$ipv6_listen)"

    local ll="listen ${lport}"; local ll6=""; local ex=""
    [ "$ssl" = "1" ] && ll="${ll} ssl"

    # IPv6 listen
    if [ "$ipv6_listen" = "1" ]; then
        ll6="listen [::]:${lport}"
        [ "$ssl" = "1" ] && ll6="${ll6} ssl"
    fi

    # HTTPS 模式自动启用 HTTP/2
    if [ "$ssl" = "1" ]; then
        if [ "$h2s" = "new" ]; then
            ex="    http2 on;"
        else
            ll="${ll} http2"
            [ -n "$ll6" ] && ll6="${ll6} http2"
        fi
    fi

    cat >> "$conf" <<SEOF
server {
    ${ll};
SEOF
    [ -n "$ll6" ] && echo "    ${ll6};" >> "$conf"
    cat >> "$conf" <<SEOF
    server_name ${domain};
${ex}
SEOF
    if [ "$ssl" = "1" ]; then
        local cp=$(find_cert "$domain")
        [ -n "$cp" ] && cat >> "$conf" <<SEOF
    ssl_certificate ${cp}/fullchain.pem;
    ssl_certificate_key ${cp}/key.pem;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
SEOF
    fi

    # 判断目标地址是否为 IPv6
    local target_host="$taddr"
    echo "$taddr" | grep -q ':' && target_host="[${taddr}]"

    cat >> "$conf" <<SEOF
    location / {
        # 拒绝直接 IP 访问（非域名）
        if (\$host ~* "^\d+\.\d+\.\d+\.\d+") {
            return 444;
        }
        proxy_pass http://${target_host}:${tport};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_read_timeout 300s;
        proxy_buffering off;
SEOF
    [ "$ws" = "1" ] && cat >> "$conf" <<SEOF
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
SEOF
    echo "    }" >> "$conf"; echo "}" >> "$conf"
}

generate_sites() {
    rm -f "$SITES_DIR"/*.conf
    local h2s=$(check_h2)
    local idx=0
    local ipv6_listen=$(get_ipv6_listen)

    # === 通配符域名设置 (proxy_wildcard sections) ===
    local wc_sections=$(uci -q show minigate | grep '=proxy_wildcard$' | cut -d. -f2 | cut -d= -f1)
    for sec in $wc_sections; do
        local enabled=$(uci -q get minigate.${sec}.enabled)
        [ "$enabled" = "1" ] || continue
        local domain=$(uci -q get minigate.${sec}.domain)
        [ -z "$domain" ] && continue
        local lport=$(uci -q get minigate.${sec}.listen_port); lport=${lport:-443}
        local ssl=$(uci -q get minigate.${sec}.ssl); ssl=${ssl:-0}
        local base=$(echo "$domain" | sed 's/^\*\.//')
        echo "${lport}|${ssl}" > "/tmp/minigate_proxy_${base}.tmp"
        log "通配符: $domain (端口:$lport https:$ssl ipv6:$ipv6_listen)"
    done

    # === 非通配符代理规则 (proxy sections) ===
    local sections=$(uci -q show minigate | grep '=proxy$' | cut -d. -f2 | cut -d= -f1)
    for sec in $sections; do
        local enabled=$(uci -q get minigate.${sec}.enabled)
        [ "$enabled" = "1" ] || continue
        local domain=$(uci -q get minigate.${sec}.domain)
        local lport=$(uci -q get minigate.${sec}.listen_port); lport=${lport:-443}
        local taddr=$(uci -q get minigate.${sec}.target_addr)
        local tport=$(uci -q get minigate.${sec}.target_port); tport=${tport:-80}
        local ssl=$(uci -q get minigate.${sec}.ssl); ssl=${ssl:-1}
        local h2=$(uci -q get minigate.${sec}.http2); h2=${h2:-1}
        local ws=$(uci -q get minigate.${sec}.websocket); ws=${ws:-0}
        [ -z "$domain" ] || [ -z "$taddr" ] && continue
        idx=$((idx + 1))
        local conf="${SITES_DIR}/site_${idx}.conf"; > "$conf"
        write_server "$conf" "$domain" "$lport" "$taddr" "$tport" "$ssl" "$h2" "$ws" "$h2s" "$ipv6_listen"
    done

    # === 子域名规则：继承通配符主域名设置 ===
    local subs=$(uci -q show minigate | grep '=subproxy$' | cut -d. -f2 | cut -d= -f1)
    for sec in $subs; do
        local parent=$(uci -q get minigate.${sec}.parent_domain)
        local prefix=$(uci -q get minigate.${sec}.prefix)
        local taddr=$(uci -q get minigate.${sec}.target_addr)
        local tport=$(uci -q get minigate.${sec}.target_port); tport=${tport:-80}
        [ -z "$parent" ] || [ -z "$prefix" ] || [ -z "$taddr" ] && continue

        local domain="${prefix}.${parent}"

        local parent_conf="/tmp/minigate_proxy_${parent}.tmp"
        local lport="443" ssl="0"
        if [ -f "$parent_conf" ]; then
            local settings=$(cat "$parent_conf")
            lport=$(echo "$settings" | cut -d'|' -f1)
            ssl=$(echo "$settings" | cut -d'|' -f2)
        fi

        idx=$((idx + 1))
        local conf="${SITES_DIR}/site_${idx}.conf"; > "$conf"
        write_server "$conf" "$domain" "$lport" "$taddr" "$tport" "$ssl" "1" "0" "$h2s" "$ipv6_listen"
    done

    rm -f /tmp/minigate_proxy_*.tmp
}

do_stop() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$pid" ]; then
            kill "$pid" 2>/dev/null
            local i=0
            while [ $i -lt 10 ] && kill -0 "$pid" 2>/dev/null; do
                sleep 1; i=$((i + 1))
            done
            kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
        fi
        rm -f "$PID_FILE"
        log "已停止"
    fi
}

do_start() {
    [ -z "$(which nginx 2>/dev/null)" ] && { log "nginx未安装"; return 1; }
    do_stop 2>/dev/null
    sleep 1
    generate_main_conf; generate_sites
    nginx -t -c "$NGINX_CONF" >> "$LOGFILE" 2>&1 || { log "配置错误"; return 1; }
    nginx -c "$NGINX_CONF" >> "$LOGFILE" 2>&1 && log "已启动" || { log "启动失败"; return 1; }
}

do_reload() {
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE" 2>/dev/null) 2>/dev/null; then
        generate_main_conf; generate_sites
        nginx -t -c "$NGINX_CONF" >> "$LOGFILE" 2>&1 && kill -HUP $(cat "$PID_FILE") && log "已重载"
    else
        do_start
    fi
}

case "$1" in start) do_start;; stop) do_stop;; reload) do_reload;; *) echo "用法: $0 {start|stop|reload}";; esac
