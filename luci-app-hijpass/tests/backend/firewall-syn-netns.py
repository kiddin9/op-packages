#!/usr/bin/env python3
"""Run with unshare -Urn python3: real nft/TPROXY checks in an isolated network."""
import json
import pathlib
import socket
import struct
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
COMMENT = 'hijpass: skip global SYN limit'


def run(*args, **kwargs):
    result = subprocess.run(args, text=True, capture_output=True, **kwargs)
    assert result.returncode == 0, result.stderr
    return result


def nft(text):
    return run('nft', '-f', '-', input=text)


def chain(name):
    data = json.loads(run('nft', '-j', 'list', 'chain', 'inet', 'fw4', name).stdout)
    return [entry['rule'] for entry in data['nftables'] if 'rule' in entry]


def count(comment, name='input'):
    return sum(expr['counter']['packets'] for rule in chain(name)
               if rule.get('comment') == comment for expr in rule['expr'] if 'counter' in expr)


def exemptions():
    return [rule for rule in chain('syn_flood') if rule.get('comment') == COMMENT]


def system_rules():
    nft('''table inet fw4 {
 chain input {
  type filter hook input priority 0; policy drop;
  ct state invalid drop
  tcp flags & (fin | syn | rst | ack) == syn jump syn_flood
  tcp dport 81 counter drop comment "zone reject"
  counter accept comment "zone accept"
 }
 chain syn_flood {
  limit rate 1/minute burst 1 packets counter return comment "limited SYN"
  counter drop comment "excess SYN"
 }
}''')


def checksum(data):
    if len(data) % 2:
        data += b'\0'
    total = sum(struct.unpack('!' + 'H' * (len(data) // 2), data))
    while total >> 16:
        total = (total & 65535) + (total >> 16)
    return (~total) & 65535


run('ip', 'link', 'set', 'lo', 'up')
run('ip', 'link', 'add', 'syn_client', 'type', 'veth', 'peer', 'name', 'syn_router')
for interface in ['syn_router', 'syn_client']:
    run('ip', 'link', 'set', interface, 'up')
run('ip', 'addr', 'add', '192.0.2.1/24', 'dev', 'syn_router')
run('ip', '-6', 'addr', 'add', '2001:db8:1::1/64', 'dev', 'syn_router', 'nodad')
for family, prefix in [('-4', '0.0.0.0/0'), ('-6', '::/0')]:
    run('ip', family, 'rule', 'add', 'fwmark', '1', 'table', '233')
    run('ip', family, 'route', 'add', 'local', prefix, 'dev', 'lo', 'table', '233')
router_mac = bytes.fromhex(json.loads(run('ip', '-j', 'link', 'show', 'syn_router').stdout)[0]['address'].replace(':', ''))
source_mac = bytes.fromhex('020000000001')
listeners = []
for family, address in [(socket.AF_INET, '0.0.0.0'), (socket.AF_INET6, '::')]:
    listener = socket.socket(family, socket.SOCK_STREAM)
    if family == socket.AF_INET6:
        listener.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
        listener.setsockopt(socket.IPPROTO_IPV6, 75, 1)  # IPV6_TRANSPARENT
    else:
        listener.setsockopt(socket.SOL_IP, 19, 1)  # IP_TRANSPARENT
    listener.bind((address, 18081))
    listener.listen(128)
    listeners.append(listener)

sequence = 0

def send(destination, port=80):
    global sequence
    sequence += 1
    ipv6 = ':' in destination
    family = socket.AF_INET6 if ipv6 else socket.AF_INET
    src = socket.inet_pton(family, '2001:db8:1::2' if ipv6 else '192.0.2.2')
    dst = socket.inet_pton(family, destination)
    tcp = struct.pack('!HHIIBBHHH', 30000 + sequence, port, sequence, 0, 0x50, 2, 4096, 0, 0)
    pseudo = src + dst + (struct.pack('!I3xB', len(tcp), 6) if ipv6 else struct.pack('!BBH', 0, 6, len(tcp)))
    tcp = tcp[:16] + struct.pack('!H', checksum(pseudo + tcp)) + tcp[18:]
    if ipv6:
        header = struct.pack('!IHBB', 6 << 28, len(tcp), 6, 64) + src + dst
    else:
        header = struct.pack('!BBHHHBBH', 0x45, 0, 40, sequence, 0, 64, 6, 0) + src + dst
        header = header[:10] + struct.pack('!H', checksum(header)) + header[12:]
    with socket.socket(socket.AF_PACKET, socket.SOCK_RAW) as sock:
        sock.bind(('syn_client', 0))
        sock.send(router_mac + source_mac + (b'\x86\xdd' if ipv6 else b'\x08\x00') + header + tcp)
    time.sleep(0.08)


with tempfile.TemporaryDirectory(prefix='hijpass-syn-test-') as directory:
    base = pathlib.Path(directory)
    rules = base / 'rules.nft'
    rules.write_text('''table inet hijpass {
 chain pre {
  type filter hook prerouting priority -50; policy accept;
  ip daddr 198.51.100.1 meta l4proto tcp ct mark set 1 tproxy ip to :18081 meta mark set 1
  ip6 daddr 2001:db8:2::1 meta l4proto tcp ct mark set 3 tproxy ip6 to :18081 meta mark set 1
  ip daddr 198.51.100.2 ct mark set 1 meta mark set 1
 }
}''')
    source = (ROOT / 'root/usr/lib/hijpass/firewall/fw4.sh').read_text()
    source = source.replace('. /usr/lib/hijpass/common.sh', 'hijpass_run_logged() { shift; "$@"; }\nhijpass_log() { :; }')
    source = source.replace('/etc/hijpass/fw4-rules.nft', str(rules)).replace('/etc/hijpass/hook/nft-hook.sh', str(base / 'no-hook'))
    entry = base / 'fw4.sh'
    entry.write_text(source)
    system_rules()
    for _ in range(3):
        run('sh', str(entry))
        assert len(exemptions()) == 1
    print('PASS repeated hijpass loads retain exactly one exemption')

    # Exhaust the shared bucket, then prove both intercepted families bypass it.
    send('192.0.2.1')
    send('192.0.2.1')
    assert count('limited SYN', 'syn_flood') == 1
    assert count('excess SYN', 'syn_flood') == 1
    before = count('zone accept')
    send('198.51.100.1')
    send('2001:db8:2::1')
    assert count(COMMENT, 'syn_flood') == 2
    assert count('zone accept') == before + 2
    send('198.51.100.1', 81)
    assert count('zone reject') == 1
    send('198.51.100.2')
    send('2001:db8:1::1')
    assert count('excess SYN', 'syn_flood') == 3
    print('PASS real IPv4/IPv6 TPROXY bypass; local services and mark-only packets remain limited; zone rejection still applies')

    nft('delete table inet fw4')
    system_rules()
    run('sh', str(entry))
    assert len(exemptions()) == 1
    print('PASS system firewall rebuild restores the exemption')

    # Reclaim even duplicate old rules without touching other applications.
    nft('insert rule inet fw4 syn_flood counter comment "other application"')
    nft('insert rule inet fw4 syn_flood counter return comment "' + COMMENT + '"')
    run('sh', str(entry))
    assert len(exemptions()) == 1
    assert any(rule.get('comment') == 'other application' for rule in chain('syn_flood'))
    original = rules.read_text()
    rules.write_text('invalid nft syntax')
    failed = subprocess.run(['sh', str(entry)], capture_output=True)
    assert failed.returncode != 0
    assert not exemptions()
    print('PASS failed rule loading removes old exemption')
    rules.write_text(original)
    run('sh', str(entry))
    rules.unlink()
    run('sh', str(entry))
    assert not exemptions()
    assert any(rule.get('comment') == 'other application' for rule in chain('syn_flood'))
    assert any(rule.get('comment') == 'excess SYN' for rule in chain('syn_flood'))
    print('PASS stop removes only hijpass exemption, preserving system and unrelated rules')

    nft('flush chain inet fw4 input\ndelete chain inet fw4 syn_flood')
    rules.write_text(original)
    run('sh', str(entry))
    run('nft', 'list', 'table', 'inet', 'hijpass')
    assert subprocess.run(['nft', 'list', 'chain', 'inet', 'fw4', 'syn_flood'], capture_output=True).returncode != 0
    print('PASS absent SYN chain is skipped without breaking hijpass loading')
