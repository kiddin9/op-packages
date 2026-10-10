// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

import * as fs from 'fs';
import {
  emit_activity_event, failure, new_uci_cursor, run_command, safe_call, string_value, success
} from './core.uc';
import { wifi_summary_payload } from './wifi.uc';

// Separate UCI section names prevent interference with existing LAN APs.
const GUEST = 'ssh_guest';
const BRIDGE = 'ssh_guest_br';
const ZONE = 'ssh_guest';
const OWNED = [
  [ 'network', BRIDGE, 'device' ], [ 'network', GUEST, 'interface' ],
  [ 'dhcp', GUEST, 'dhcp' ], [ 'firewall', ZONE, 'zone' ],
  [ 'firewall', 'ssh_guest_wan', 'forwarding' ],
  [ 'firewall', 'ssh_guest_dns', 'rule' ],
  [ 'firewall', 'ssh_guest_dhcp', 'rule' ],
  [ 'firewall', 'ssh_guest_block_10', 'rule' ],
  [ 'firewall', 'ssh_guest_block_172', 'rule' ],
  [ 'firewall', 'ssh_guest_block_192', 'rule' ],
  [ 'firewall', 'ssh_guest_block_cgnat', 'rule' ],
  [ 'firewall', 'ssh_guest_block_link', 'rule' ],
  [ 'firewall', 'ssh_guest_block_ipv6', 'rule' ],
  [ 'wireless', GUEST, 'wifi-iface' ],
];
const PACKAGES = [ 'network', 'dhcp', 'firewall', 'wireless', 'smartsafehub' ];
const LOCK = '/tmp/smartsafehub/wifi-update.lock';
const PRIVATE_DESTINATIONS = {
  ssh_guest_block_10: '10.0.0.0/8',
  ssh_guest_block_172: '172.16.0.0/12',
  ssh_guest_block_192: '192.168.0.0/16',
  ssh_guest_block_cgnat: '100.64.0.0/10',
  ssh_guest_block_link: '169.254.0.0/16',
};
const CANDIDATE_SUBNETS = [ 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 160, 170, 180, 190, 200, 210, 220 ];

function valid_ssid(value) {
  return type(value) == 'string' && length(value) > 0 && length(value) <= 32 && match(value, /[\r\n]/) == null;
}
function valid_key(value) {
  return type(value) == 'string' && ((length(value) >= 8 && length(value) <= 63) ||
    (length(value) == 64 && match(value, /^[0-9a-fA-F]{64}$/) != null));
}
function guest_default_ssid(base) {
  let ssid = string_value(base, 'SmartSafeHub');
  // SmartSafeHub-2G -> SmartSafeHub-Guest, rather than -2G-Guest.
  if (match(ssid, /-2G$/i) != null) {
    ssid = substr(ssid, 0, length(ssid) - 3);
  }
  const result = sprintf('%s-Guest', ssid);
  return valid_ssid(result) ? result : 'SmartSafeHub-Guest';
}
function primary_2g(ctx) {
  const summary = wifi_summary_payload();
  for (let network in summary?.networks ?? []) {
    if (network.band == '2g') {
      return network;
    }
  }
  return null;
}
function managed(ctx) {
  return ctx.get('smartsafehub', 'guest_wifi', 'managed') == '1';
}
function reserved_sections_safe(ctx, is_managed) {
  for (let item in OWNED) {
    const section = ctx.get_all(item[0], item[1]);
    if (section != null && (!is_managed || section['.type'] != item[2])) {
      return false;
    }
  }
  let name_conflict = false;
  ctx.foreach('firewall', 'zone', function(section) {
    if (section.name == ZONE && section['.name'] != ZONE) name_conflict = true;
  });
  if (name_conflict) return false;
  // Avoid accidentally taking control of a manually configured guest network.
  const config = ctx.get_all('smartsafehub', 'guest_wifi');
  return config == null || (is_managed && config['.type'] == 'guest_wifi');
}
function pow2(exponent) {
  let result = 1;
  for (let i = 0; i < exponent; i++) result *= 2;
  return result;
}
function ipv4_number(value) {
  if (type(value) != 'string') return null;
  const parts = split(value, '.');
  if (length(parts) != 4) return null;
  let result = 0;
  for (let part in parts) {
    if (match(part, /^(0|[1-9][0-9]{0,2})$/) == null || int(part) > 255) return null;
    result = result * 256 + int(part);
  }
  return result;
}
function occupied_subnets(ctx) {
  const result = [];
  ctx.foreach('network', 'interface', function(section) {
    if (section['.name'] == GUEST) return;
    const address = string_value(section.ipaddr, null);
    if (address == null) return;
    const parts = split(address, '/');
    const ip = ipv4_number(parts[0]);
    const prefix = length(parts) == 2 ? int(parts[1]) : null;
    const netmask = ipv4_number(string_value(section.netmask, '255.255.255.0'));
    if (ip == null) return;
    const size = prefix != null && prefix >= 0 && prefix <= 32
      ? pow2(32 - prefix) : netmask != null ? (4294967296 - netmask) : null;
    if (size != null && size >= 1 && size <= 4294967296) {
      const start = int(ip / size) * size;
      push(result, { start: start, end: start + size - 1 });
    }
  });
  const runtime = safe_call('network.interface', 'dump', {});
  for (let item in runtime?.interface ?? []) {
    if (item.interface == GUEST) continue;
    for (let address in item?.['ipv4-address'] ?? []) {
      const ip = ipv4_number(address.address);
      const prefix = int(address.mask);
      if (ip == null || prefix < 0 || prefix > 32) continue;
      const size = pow2(32 - prefix);
      const start = int(ip / size) * size;
      push(result, { start: start, end: start + size - 1 });
    }
  }
  return result;
}
function guest_address(ctx) {
  const used = occupied_subnets(ctx);
  for (let octet in CANDIDATE_SUBNETS) {
    const start = ipv4_number(sprintf('192.168.%d.0', octet));
    let conflict = false;
    for (let subnet in used) {
      if (start <= subnet.end && subnet.start <= start + 255) conflict = true;
    }
    if (!conflict) return sprintf('192.168.%d.1', octet);
  }
  return null;
}
function set_section(ctx, config, section, section_type, options) {
  if (ctx.get_all(config, section) == null && ctx.set(config, section, section_type) != true) return false;
  for (let key in keys(options)) {
    if (ctx.set(config, section, key, options[key]) != true) return false;
  }
  return true;
}
function snapshot_files() {
  const snapshot = {};
  for (let name in PACKAGES) {
    const contents = fs.readfile(sprintf('/etc/config/%s', name));
    if (contents == null) return null;
    snapshot[name] = contents;
  }
  return snapshot;
}
function restore_files(snapshot) {
  let okay = true;
  for (let name in PACKAGES) {
    const written = fs.writefile(sprintf('/etc/config/%s', name), snapshot[name]);
    if (type(written) != 'int' || written != length(snapshot[name])) okay = false;
  }
  return okay;
}
function reload_after_rollback() {
  run_command([ '/etc/init.d/network', 'reload' ], 30000);
  run_command([ '/etc/init.d/dnsmasq', 'restart' ], 30000);
  run_command([ '/etc/init.d/firewall', 'restart' ], 30000);
  run_command([ '/sbin/wifi', 'reload' ], 25000);
}

export function guest_wifi_summary() {
  const ctx = new_uci_cursor();
  if (!ctx) return null;
  const two_g = primary_2g(ctx);
  const active = managed(ctx);
  const guest = active ? ctx.get_all('wireless', GUEST) : null;
  const ssid = guest == null ? guest_default_ssid(two_g?.ssid) : string_value(guest.ssid, '');
  return {
    supported: two_g != null,
    configured: guest != null,
    enabled: guest != null && guest.disabled != '1',
    ssid: ssid,
    passwordConfigured: guest != null && length(string_value(guest.key, '')) > 0,
    subnet: active ? string_value(ctx.get('network', GUEST, 'ipaddr'), '') : '',
    radio: string_value(two_g?.device, ''),
  };
};

// Return the password only for an explicit, administrator-authorized QR request.
// Never include it in the ordinary guest Wi-Fi summary or device diagnostics.
export function read_guest_wifi_qr() {
  const ctx = new_uci_cursor();
  if (!ctx) return failure('GUEST_WIFI_READ_FAILED', '설정을 읽지 못했습니다.');
  if (!managed(ctx)) return failure('GUEST_WIFI_QR_UNAVAILABLE', '게스트 Wi-Fi가 설정되지 않았습니다.');

  const guest = ctx.get_all('wireless', GUEST);
  const ssid = string_value(guest?.ssid, '');
  const key = string_value(guest?.key, '');
  if (guest?.['.type'] != 'wifi-iface' || guest?.mode != 'ap' ||
      guest?.network != GUEST || guest?.encryption != 'sae-mixed' ||
      guest?.disabled == '1' || !valid_ssid(ssid) || !valid_key(key)) {
    return failure('GUEST_WIFI_QR_UNAVAILABLE', '게스트 Wi-Fi가 켜져 있고 비밀번호가 설정되어 있어야 합니다.');
  }
  return success({ ssid: ssid, security: 'sae-mixed', password: key });
};

function update_guest(request) {
  const args = request?.args ?? {};
  if (type(args.enabled) != 'bool' || !valid_ssid(args.ssid) || type(args.password) != 'string') {
    return failure('GUEST_WIFI_INVALID', '게스트 Wi-Fi 설정을 확인해 주세요.');
  }
  if (length(args.password) && !valid_key(args.password)) {
    return failure('GUEST_WIFI_PASSWORD_INVALID', '비밀번호는 8~63자 또는 64자리 16진수여야 합니다.');
  }
  const ctx = new_uci_cursor();
  if (!ctx) return failure('GUEST_WIFI_READ_FAILED', '설정을 읽지 못했습니다.');
  const two_g = primary_2g(ctx);
  if (two_g == null) return failure('GUEST_WIFI_UNSUPPORTED', '2.4GHz 기본 Wi-Fi를 찾지 못했습니다.');
  for (let current in wifi_summary_payload()?.networks ?? []) {
    if (current.ssid == args.ssid) return failure('GUEST_WIFI_SSID_CONFLICT', '기본 Wi-Fi와 다른 이름을 입력해 주세요.');
  }
  let wan_exists = false;
  ctx.foreach('firewall', 'zone', function(section) {
    if (section.name == 'wan') wan_exists = true;
  });
  if (args.enabled && !wan_exists) return failure('GUEST_WIFI_WAN_MISSING', '인터넷 방화벽 구역을 찾지 못했습니다.');
  if (!reserved_sections_safe(ctx, managed(ctx))) {
    return failure('GUEST_WIFI_CONFLICT', '기존 고급 설정과 충돌합니다. LuCI의 게스트 네트워크 설정을 확인해 주세요.');
  }
  const old = managed(ctx) ? ctx.get_all('wireless', GUEST) : null;
  const current_password = string_value(old?.key, '');
  if (args.enabled && !valid_key(length(args.password) ? args.password : current_password)) {
    return failure('GUEST_WIFI_PASSWORD_REQUIRED', '게스트 전용 비밀번호를 입력해 주세요.');
  }
  if (!args.enabled && old == null) {
    return success({ changed: false, reloaded: false, guest: guest_wifi_summary() });
  }
  const ip = old == null ? guest_address(ctx) : ctx.get('network', GUEST, 'ipaddr');
  if (ip == null) return failure('GUEST_WIFI_SUBNET_CONFLICT', '사용 가능한 게스트 IP 대역을 찾지 못했습니다.');
  const guest_numeric = ipv4_number(ip);
  if (args.enabled && guest_numeric != null) {
    const guest_start = int(guest_numeric / 256) * 256;
    for (let subnet in occupied_subnets(ctx)) {
      if (guest_start <= subnet.end && subnet.start <= guest_start + 255) {
        return failure('GUEST_WIFI_SUBNET_CONFLICT', '기존 네트워크와 게스트 IP 대역이 충돌합니다.');
      }
    }
  }
  const key = length(args.password) ? args.password : current_password;
  const no_changes = old != null && string_value(old.ssid, '') == args.ssid &&
    old.disabled == (args.enabled ? '0' : '1') && current_password == key &&
    old.device == two_g.device;
  if (no_changes) return success({ changed: false, reloaded: false, guest: guest_wifi_summary() });

  const snapshot = snapshot_files();
  if (snapshot == null) return failure('GUEST_WIFI_BACKUP_FAILED', '설정 백업에 실패해 변경하지 않았습니다.');
  // Disable first for an existing enabled guest when changing firewall/network.
  let written =
    set_section(ctx, 'network', BRIDGE, 'device', { type: 'bridge', name: 'br-sshguest', bridge_empty: '1' }) &&
    set_section(ctx, 'network', GUEST, 'interface', { proto: 'static', device: 'br-sshguest', ipaddr: ip, netmask: '255.255.255.0' }) &&
    set_section(ctx, 'dhcp', GUEST, 'dhcp', { interface: GUEST, start: '100', limit: '150', leasetime: '12h', ignore: '0', dhcpv6: 'disabled', ra: 'disabled', ndp: 'disabled' }) &&
    set_section(ctx, 'firewall', ZONE, 'zone', { name: ZONE, network: GUEST, input: 'REJECT', output: 'ACCEPT', forward: 'REJECT' }) &&
    set_section(ctx, 'firewall', 'ssh_guest_wan', 'forwarding', { src: ZONE, dest: 'wan', family: 'ipv4' }) &&
    set_section(ctx, 'firewall', 'ssh_guest_dns', 'rule', { name: 'SSH Guest DNS', src: ZONE, proto: [ 'tcp', 'udp' ], dest_port: '53', target: 'ACCEPT', family: 'ipv4' }) &&
    set_section(ctx, 'firewall', 'ssh_guest_dhcp', 'rule', { name: 'SSH Guest DHCP', src: ZONE, proto: 'udp', dest_port: '67', target: 'ACCEPT', family: 'ipv4' });
  for (let name in keys(PRIVATE_DESTINATIONS)) {
    written = written && set_section(ctx, 'firewall', name, 'rule', {
      name: name, src: ZONE, dest: 'wan', dest_ip: PRIVATE_DESTINATIONS[name],
      proto: 'all', target: 'REJECT', family: 'ipv4'
    });
  }
  written = written &&
    set_section(ctx, 'firewall', 'ssh_guest_block_ipv6', 'rule', {
      name: 'SSH Guest IPv6 Block', src: ZONE, dest: 'wan',
      proto: 'all', target: 'REJECT', family: 'ipv6'
    }) &&
    set_section(ctx, 'wireless', GUEST, 'wifi-iface', {
      device: two_g.device, mode: 'ap', network: GUEST, ssid: args.ssid,
      encryption: 'sae-mixed', key: key, isolate: '1', disabled: '1'
    }) &&
    set_section(ctx, 'smartsafehub', 'guest_wifi', 'guest_wifi', { managed: '1' });
  if (!written) {
    return failure('GUEST_WIFI_WRITE_FAILED', '게스트 설정을 준비하지 못했습니다.');
  }
  let committed = true;
  for (let name in PACKAGES) {
    if (ctx.commit(name) != true) { committed = false; break; }
  }
  // Reenable the AP ONLY after network, DNS and firewall have applied successfully.
  let applied = committed && run_command([ '/etc/init.d/network', 'reload' ], 30000) &&
    run_command([ '/etc/init.d/dnsmasq', 'restart' ], 30000) &&
    run_command([ '/etc/init.d/firewall', 'restart' ], 30000);
  if (applied && args.enabled) {
    applied = ctx.set('wireless', GUEST, 'disabled', '0') == true &&
      ctx.commit('wireless') == true;
  }
  if (applied) applied = run_command([ '/sbin/wifi', 'reload' ], 25000);
  if (!applied) {
    const restored = restore_files(snapshot);
    if (restored) reload_after_rollback();
    return restored
      ? failure('GUEST_WIFI_APPLY_FAILED', '게스트 Wi-Fi 적용에 실패하여 이전 설정으로 복원했습니다.')
      : failure('GUEST_WIFI_ROLLBACK_FAILED', '설정 복원이 실패했습니다. LuCI에서 설정을 확인해 주세요.');
  }
  return success({ changed: true, reloaded: true, guest: guest_wifi_summary() });
}

export function update_guest_wifi(request) {
  const stat = fs.stat(LOCK);
  if (stat && time() - int(stat.mtime) < 300) {
    return failure('WIFI_UPDATE_RUNNING', '다른 Wi-Fi 설정 변경이 진행 중입니다.');
  }
  if (stat) fs.rmdir(LOCK);
  if (fs.mkdir(LOCK) != true) return failure('WIFI_UPDATE_RUNNING', 'Wi-Fi 설정 변경이 진행 중입니다.');
  let result;
  try { result = update_guest(request); }
  catch (e) { result = failure('GUEST_WIFI_FAILED', '게스트 Wi-Fi 설정 중 오류가 발생했습니다.'); }
  fs.rmdir(LOCK);
  if (result?.ok && result.data?.changed) {
    emit_activity_event('network', 'settings.wifi.guest.updated', 'info', { enabled: request.args.enabled });
  }
  return result;
};
