'use strict';

let core = require('core');
let ubus = require('ubus');
let runtime = require('runtime');

ubus.state.services.safeshield = {
    instances: {
        refreshd: { running: true },
        stopped: { running: false }
    }
};
assert(runtime.service_running('safeshield') == true, 'service_running accepts any running instance');
assert(runtime.service_instance_running('safeshield', 'refreshd') == true, 'service_instance_running finds a running instance');
assert(runtime.service_instance_running('safeshield', 'stopped') == false, 'service_instance_running preserves stopped state');
assert(runtime.service_running('missing') == false, 'service_running rejects missing services');
assert(runtime.service_instance_running('missing', 'refreshd') == false, 'service_instance_running rejects missing services');

ubus.state.services.dnsmasq = { instances: { main: { running: true } } };
assert(runtime.dnsmasq_running() == true, 'dnsmasq_running accepts a running dnsmasq instance');
ubus.state.services.dnsmasq.instances.main.running = false;
assert(runtime.dnsmasq_running() == false, 'dnsmasq_running rejects stopped dnsmasq instances');

let action = runtime.run_service_action('status', 1000);
assert(action.ok == true && action.rc == 0, 'run_service_action reports successful service commands');

core.state.status = { data: { status: 'running' } };
assert(runtime.refresh_running() == true, 'refresh_running recognizes running status');
core.state.status = { data: { status: 'ready' } };
assert(runtime.refresh_running() == false, 'refresh_running rejects non-running status');

core.values.enabled = '0';
let refresh_disabled = runtime.start_refresh_async();
assert(refresh_disabled.accepted == false && refresh_disabled.reason == 'disabled', 'start_refresh_async rejects disabled SafeShield');

core.values.enabled = '1';
ubus.state.services.safeshield = null;
let refresh_stopped = runtime.start_refresh_async();
assert(refresh_stopped.accepted == false && refresh_stopped.reason == 'service_stopped', 'start_refresh_async rejects a stopped service');

ubus.state.services.safeshield = { instances: { refreshd: { running: true } } };
core.state.status = { data: { status: 'running' } };
let refresh_running = runtime.start_refresh_async();
assert(refresh_running.accepted == false && refresh_running.reason == 'already_running', 'start_refresh_async is idempotent during a refresh');

core.state.status = { data: { status: 'ready' } };
let refresh_spawned = runtime.start_refresh_async();
assert(refresh_spawned.accepted == true && refresh_spawned.reason == '' && refresh_spawned.rc == 0, 'start_refresh_async launches the detached refresh worker');

core.values.enabled = '0';
let local_disabled = runtime.start_local_apply_async();
assert(local_disabled.accepted == false && local_disabled.reason == 'disabled', 'start_local_apply_async rejects disabled SafeShield');

core.values.enabled = '1';
core.values.apply_local_overrides = '0';
let local_overrides_disabled = runtime.start_local_apply_async();
assert(local_overrides_disabled.accepted == false && local_overrides_disabled.reason == 'local_overrides_disabled', 'start_local_apply_async requires local overrides');

core.values.apply_local_overrides = '1';
ubus.state.services.safeshield = null;
let local_stopped = runtime.start_local_apply_async();
assert(local_stopped.accepted == false && local_stopped.reason == 'service_stopped', 'start_local_apply_async rejects a stopped service');

ubus.state.services.safeshield = { instances: { refreshd: { running: true } } };
let local_spawned = runtime.start_local_apply_async();
assert(local_spawned.accepted == true && local_spawned.reason == '' && local_spawned.rc == 0, 'start_local_apply_async launches the detached local-rule worker');

assert(core.state.reloads >= 8, 'async entrypoints reload UCI before checking runtime state');

print('ucode runtime tests: ok\n');
