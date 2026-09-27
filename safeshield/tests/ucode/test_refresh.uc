'use strict';

let runtime = require('runtime');
let refresh = require('refresh');

let accepted = refresh.call();
assert(accepted.ok == true && accepted.accepted == true, 'accepted refresh succeeds');
assert(accepted.status.marker == 'test-status', 'refresh returns current status');

runtime.state.accepted = false;
runtime.state.reason = 'already_running';
let running = refresh.call();
assert(running.ok == true && running.accepted == false, 'already-running refresh is idempotent');
assert(running.reason == 'already_running', 'already-running reason is preserved');

runtime.state.reason = 'disabled';
let disabled = refresh.call();
assert(disabled.ok == false && disabled.accepted == false, 'disabled refresh is rejected');
assert(disabled.reason == 'disabled', 'disabled reason is preserved');

print('ucode refresh tests: ok\n');
