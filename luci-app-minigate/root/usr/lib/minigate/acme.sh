#!/bin/sh
ACME_HOME="/etc/minigate/acme/data"
ACME_BIN="${ACME_HOME}/acme.sh"
CERT_DIR="/etc/minigate/certs"
LOGFILE="/var/log/minigate-acme.log"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [ACME] $*" >> "$LOGFILE"; }

safe_dir() { echo "$1" | sed 's/\*/_wildcard_/g'; }

find_token_for_domain() {
    local target="$1"
    local sections=$(uci -q show minigate | grep '=ddns$' | cut -d. -f2 | cut -d= -f1)
    for sec in $sections; do
        local d=$(uci -q get minigate.${sec}.domain)
        if [ "$d" = "$target" ]; then
            echo "$(uci -q get minigate.${sec}.cf_api_token)|$(uci -q get minigate.${sec}.cf_zone_id)"
            return 0
        fi
    done
    local parent=$(echo "$target" | sed 's/^[^.]*\.//')
    for sec in $sections; do
        local d=$(uci -q get minigate.${sec}.domain)
        local db=$(echo "$d" | sed 's/^\*\.//')
        if [ "$db" = "$parent" ] || [ "$d" = "*.$parent" ]; then
            echo "$(uci -q get minigate.${sec}.cf_api_token)|$(uci -q get minigate.${sec}.cf_zone_id)"
            return 0
        fi
    done
    for sec in $sections; do
        local t=$(uci -q get minigate.${sec}.cf_api_token)
        local z=$(uci -q get minigate.${sec}.cf_zone_id)
        [ -n "$t" ] && echo "${t}|${z}" && return 0
    done
    return 1
}

do_install() {
    if [ -x "$ACME_BIN" ] && [ -d "${ACME_HOME}/dnsapi" ]; then
        log "acme.sh 已安装"; return 0
    fi
    log "下载 acme.sh ..."
    mkdir -p "$ACME_HOME" "$CERT_DIR"
    cd /tmp; rm -rf acme.sh-master acme-master.tar.gz
    local ok=0
    for url in "https://github.com/acmesh-official/acme.sh/archive/master.tar.gz"; do
        wget -qO /tmp/acme-master.tar.gz "$url" 2>/dev/null && ok=1 && break
        curl -sLo /tmp/acme-master.tar.gz "$url" 2>/dev/null && ok=1 && break
    done
    [ "$ok" != "1" ] && { log "下载失败"; return 1; }
    tar xzf /tmp/acme-master.tar.gz -C /tmp/ 2>/dev/null
    cd /tmp/acme.sh-master
    ./acme.sh --install --home "$ACME_HOME" --no-cron --no-profile 2>>"$LOGFILE"
    cd /tmp; rm -rf /tmp/acme-master.tar.gz /tmp/acme.sh-master
    if [ -x "$ACME_BIN" ] && [ -d "${ACME_HOME}/dnsapi" ]; then
        "$ACME_BIN" --home "$ACME_HOME" --set-default-ca --server letsencrypt 2>>"$LOGFILE"
        log "安装成功"; uci -q set minigate.acme.status="installed"; uci commit minigate; return 0
    else
        log "安装失败"; return 1
    fi
}

do_issue() {
    local domain="$1"
    local email=$(uci -q get minigate.acme.email)
    local staging=$(uci -q get minigate.acme.staging)
    local key_type=$(uci -q get minigate.acme.key_type)

    if [ -z "$domain" ]; then
        local fs=$(uci -q show minigate | grep '=ddns$' | head -1 | cut -d. -f2 | cut -d= -f1)
        [ -n "$fs" ] && domain=$(uci -q get minigate.${fs}.domain)
    fi
    [ -z "$domain" ] && { log "未指定域名"; uci -q set minigate.acme.status="error"; uci commit minigate; return 1; }

    local ti=$(find_token_for_domain "$domain")
    local token=$(echo "$ti" | cut -d'|' -f1)
    local zone_id=$(echo "$ti" | cut -d'|' -f2)
    [ -z "$token" ] && { log "无API令牌"; uci -q set minigate.acme.status="error"; uci commit minigate; return 1; }

    do_install || return 1
    local safe=$(safe_dir "$domain")
    mkdir -p "${CERT_DIR}/${safe}"
    export CF_Token="$token"
    [ -n "$zone_id" ] && export CF_Zone_ID="$zone_id"

    local kl="ec-256"
    case "$key_type" in ec-256|ec-384) kl="$key_type";; rsa-2048) kl="2048";; rsa-4096) kl="4096";; esac
    local sf="--server letsencrypt"
    [ "$staging" = "1" ] && sf="--staging --server letsencrypt"

    log "签发: $domain (staging=$staging)"
    uci -q set minigate.acme.status="issuing"; uci commit minigate

    "$ACME_BIN" --home "$ACME_HOME" --issue --dns dns_cf $sf -d "$domain" --keylength "$kl" \
        ${email:+--accountemail "$email"} \
        --cert-file "${CERT_DIR}/${safe}/cert.pem" --key-file "${CERT_DIR}/${safe}/key.pem" \
        --fullchain-file "${CERT_DIR}/${safe}/fullchain.pem" --force >> "$LOGFILE" 2>&1
    local ret=$?

    if [ $ret -eq 0 ] && [ -f "${CERT_DIR}/${safe}/fullchain.pem" ]; then
        local expiry=$(openssl x509 -in "${CERT_DIR}/${safe}/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
        log "成功: $domain (过期: $expiry)"
        uci -q set minigate.acme.status="ok"
        uci -q set minigate.acme.last_domain="$domain"
        uci -q set minigate.acme.last_issue="$(date '+%Y-%m-%d %H:%M:%S')"
        uci -q set minigate.acme.cert_expiry="$expiry"
        uci commit minigate
        if echo "$domain" | grep -q '^\*\.'; then
            local base=$(echo "$domain" | sed 's/^\*\.//')
            [ ! -e "${CERT_DIR}/${base}" ] && ln -sf "${safe}" "${CERT_DIR}/${base}"
        fi
        [ -f /usr/lib/minigate/proxy.sh ] && /bin/sh /usr/lib/minigate/proxy.sh reload 2>/dev/null
        return 0
    else
        log "失败 (exit=$ret)"; uci -q set minigate.acme.status="error"; uci commit minigate; return 1
    fi
}

do_renew() { do_install || return 1; log "续期..."; "$ACME_BIN" --home "$ACME_HOME" --renew-all --server letsencrypt >> "$LOGFILE" 2>&1; log "完成"; }

case "${1:-issue}" in install) do_install;; issue) do_issue "$2";; renew) do_renew;; *) echo "用法: $0 {install|issue [域名]|renew}";; esac
