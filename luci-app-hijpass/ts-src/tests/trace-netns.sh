#!/bin/sh
# All network changes below run in a new user/network namespace.
set -eu
trace_repository="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
trace_runtime="$(mktemp -d /tmp/hijpass-trace-runtime-XXXXXXXX)"
trap 'rm -rf "$trace_runtime"' EXIT
# 固定安装路径只在测试副本中重写，原脚本保持与路由器上的安装行为一致。
cp -R "$trace_repository/root/usr/lib/hijpass/." "$trace_runtime/"
find "$trace_runtime" \( -name '*.sh' -o -name '*.uc' \) -exec sed -i \
    -e "s#/usr/lib/hijpass#$trace_runtime#g" \
    -e 's@#!/bin/sh$@#!/usr/bin/busybox ash@' {} +
sed -i \
    -e "s#ucode -S --#'${UCODE:-ucode}' -S -L '$trace_repository/root/usr/share/ucode' --#" \
    -e "s#/usr/share/libubox/jshn.sh#${JSHN_SH:-/usr/share/libubox/jshn.sh}#" \
    "$trace_runtime/common.sh"
trace_script="$trace_runtime/diagnostics/capture.sh"
unshare -Urn sh -s -- "$trace_script" <<'NAMESPACE'
set -eu
trace_check_dir="$(mktemp -d /tmp/hijpass-trace-netns-XXXXXXXX)"
trap 'rm -rf "$trace_check_dir"' EXIT
ip link set lo up
ip link add trace_client type veth peer name trace_router
ip link set trace_client up
ip link set trace_router up
ip addr add 192.168.1.1/24 dev trace_router
ip addr add 8.8.8.8/32 dev lo
nft add table inet hijpass
nft add chain inet hijpass dns-forward '{ type nat hook prerouting priority -101; policy accept; }'
nft add rule inet hijpass dns-forward udp dport 53 redirect to :1053
nft add chain inet hijpass pre-filter '{ type filter hook prerouting priority -50; policy accept; }'
nft add rule inet hijpass pre-filter udp dport 1053 counter
"$1" -c 192.168.1.100 -n udp -P 53 -t 2 -v >"$trace_check_dir/report" 2>"$trace_check_dir/errors" &
trace_check_pid=$!
while ! grep -q 'Trace is active' "$trace_check_dir/report"; do
    kill -0 "$trace_check_pid"
    sleep 0.05
done
python3 - <<'PY'
import socket,struct,json,subprocess
router_mac=bytes.fromhex(json.loads(subprocess.check_output(['ip','-j','link','show','trace_router']))[0]['address'].replace(':',''))
client_mac=bytes.fromhex('020000000001')
def checksum(data):
    words=struct.unpack('!10H',data)
    value=sum(words)
    while value>>16: value=(value&65535)+(value>>16)
    return (~value)&65535
with socket.socket(socket.AF_PACKET,socket.SOCK_RAW) as sock:
    sock.bind(('trace_client',0))
    for src,port in [('192.168.1.100',53),('192.168.1.100',443),('192.168.1.200',53)]:
        payload=b'hijpass trace test'
        udp=struct.pack('!HHHH',50000,port,8+len(payload),0)+payload
        ip=struct.pack('!BBHHHBBH4s4s',0x45,0,20+len(udp),123,0,64,17,0,socket.inet_aton(src),socket.inet_aton('8.8.8.8'))
        ip=ip[:10]+struct.pack('!H',checksum(ip))+ip[12:]
        sock.send(router_mac+client_mac+b'\x08\x00'+ip+udp)

PY
wait "$trace_check_pid"
python3 - "$trace_check_dir/report" <<'PY'
import sys
s=open(sys.argv[1]).read()
assert 'client_flows_total: 1' in s,s
assert '[8.8.8.8]:53' in s,s
assert 'redirect to :1053' in s,s
assert 'dport 1053' in s,s
assert '192.168.1.200' not in s,s
assert 'dport 443' not in s,s
print('PASS: real UDP port filter precedes DNAT and excludes other clients/ports')
PY
if nft list table inet hijpass | grep -q 'chain trace-'; then exit 1; fi
printf 'PASS: temporary trace chain removed; original NAT/filter chains retained\n'
NAMESPACE
