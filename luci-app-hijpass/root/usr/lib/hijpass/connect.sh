#!/bin/sh

# 用法：
#   sh net_check.sh https://www.example.com
#   sh net_check.sh https://www.example.com 5   # 超时 5 秒
. /usr/lib/hijpass/app-logger.sh

URL="$1"
TIMEOUT="${2:-5}"   # 默认总超时 5 秒

if [ -z "$URL" ]; then
  echo "Usage: $0 <url> [timeout_seconds]" >&2
  exit 1
fi
case "$URL" in
  https://*) ;;
  *)
    echo "Only https URLs are allowed" >&2
    exit 1
    ;;
esac
case "$TIMEOUT" in
  ''|*[!0-9]*)
    echo "Invalid timeout" >&2
    exit 1
    ;;
esac

TMP_ERR=/tmp/net_check_curl_err.$$.log

# 说明：
#  curl 的 time_* 都是秒（浮点数），这里先用秒输出，
#  再交给 jq 乘以 1000 转换成毫秒。
CURL_OUTPUT=$(curl -I -o /dev/null -sSk -D /dev/null \
  -w '{
    "url": "%{url_effective}",
    "http_code": %{http_code},
    "dns_lookup_time_s": %{time_namelookup},
    "tcp_connect_time_s": %{time_connect},
    "tls_handshake_time_s": %{time_appconnect},
    "server_processing_time_s": %{time_starttransfer},
    "first_byte_time_s": %{time_starttransfer},
    "total_time_s": %{time_total},
    "remote_ip": "%{remote_ip}",
    "remote_port": %{remote_port},
    "exit_code": 0
  }' \
  --max-time "$TIMEOUT" \
  "$URL" 2>"$TMP_ERR")

RET=$?

if [ $RET -ne 0 ]; then
  # 失败时输出简洁 JSON（不带原始错误文本，避免控制字符问题）
  printf '%s\n' "{
    \"url\": \"${URL}\",
    \"success\": false,
    \"exit_code\": ${RET}
}" | jq '.'

  # 错误详情仍然打到 stderr 便于调试
  if [ -s "$TMP_ERR" ]; then
    log_error "$(cat "$TMP_ERR")"
  fi
  rm -f "$TMP_ERR"
  exit $RET
fi

rm -f "$TMP_ERR"

# 成功时：
# 1. 把 *_s 的秒字段转换成 *_ms 的毫秒字段（整数）
# 2. 保留原秒字段或删掉都可以，这里顺便删掉秒字段，只保留毫秒
echo "$CURL_OUTPUT" \
  | jq '
    .success = true
    | .dns_lookup_time_ms        = ((.dns_lookup_time_s        * 1000) | floor)
    | .tcp_connect_time_ms       = ((.tcp_connect_time_s       * 1000) | floor)
    | .tls_handshake_time_ms     = ((.tls_handshake_time_s     * 1000) | floor)
    | .server_processing_time_ms = ((.server_processing_time_s * 1000) | floor)
    | .total_time_ms             = ((.total_time_s             * 1000) | floor)
    | .first_byte_time_ms        = ((.first_byte_time_s        * 1000) | floor)
    | del(.dns_lookup_time_s,
          .tcp_connect_time_s,
          .tls_handshake_time_s,
          .server_processing_time_s,
          .total_time_s,
          .first_byte_time_s)
  '
