#!/bin/sh

. /usr/lib/hijpass/app-logger.sh

log_debug "$0"

GEO_IP_URL=$(uci -q get hijpass.@rule[0].geoip || :)
GEO_SITE_URL=$(uci -q get hijpass.@rule[0].geosite || :)
DATA_DIR="/usr/share/v2ray"

check_url() {
    local url name
    url=$1
    name=$2

    if [ -z "$url" ]; then
        log_error "$name URL is empty"
        exit 1
    fi

    if ! echo "$url" | grep -qE '^https?://'; then
        log_error "$name URL must start with http:// or https://"
        exit 1
    fi
}

update_file() {
    local url output name
    url=$1
    output=$2
    name=$3

    log_info "Downloading new $name database..."
    if curl -L -o "$output.new" "$url"; then
        mv "$output.new" "$output"
        log_info "$name database updated successfully"
    else
        rm -f "$output.new"
        log_error "Failed to download $name database"
    fi
}

check_url "$GEO_IP_URL" "GeoIP"
check_url "$GEO_SITE_URL" "GeoSite"

mkdir -p "$DATA_DIR"

log_info "Checking GeoIP database..."
REMOTE_GEOIP_HASH=$(curl -sL "$GEO_IP_URL" | md5sum | cut -d' ' -f1)
if [ -f "$DATA_DIR/geoip.dat" ]; then
    LOCAL_GEOIP_HASH=$(md5sum "$DATA_DIR/geoip.dat" | cut -d' ' -f1)
else
    LOCAL_GEOIP_HASH=""
fi

if [ "$REMOTE_GEOIP_HASH" != "$LOCAL_GEOIP_HASH" ]; then
    update_file "$GEO_IP_URL" "$DATA_DIR/geoip.dat" "GeoIP"
else
    log_info "GeoIP database is up to date"
fi

log_info "Checking GeoSite database..."
REMOTE_GEOSITE_HASH=$(curl -sL "$GEO_SITE_URL" | md5sum | cut -d' ' -f1)
if [ -f "$DATA_DIR/geosite.dat" ]; then
    LOCAL_GEOSITE_HASH=$(md5sum "$DATA_DIR/geosite.dat" | cut -d' ' -f1)
else
    LOCAL_GEOSITE_HASH=""
fi

if [ "$REMOTE_GEOSITE_HASH" != "$LOCAL_GEOSITE_HASH" ]; then
    update_file "$GEO_SITE_URL" "$DATA_DIR/geosite.dat" "GeoSite"
else
    log_info "GeoSite database is up to date"
fi
