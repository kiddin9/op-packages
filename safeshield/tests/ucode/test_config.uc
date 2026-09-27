'use strict';

let core = require('core');
let runtime = require('runtime');
let config = require('config');

let built = config.build();
assert(built.schema.name == 'safeshield.config', 'config schema name is preserved');
assert(built.values.enabled == false, 'disabled state is normalized to boolean');
assert(built.values.download_retry == 3, 'integer options are normalized');
assert(built.license.configured == true, 'configured license is reported');
assert(built.license.key_masked == 'abcd...wxyz', 'license key is masked');
assert(built.device.memory_mb == 256, 'device memory is normalized to integer');

let invalid_values = config.update({ args: { values: 'not-an-object' } });
assert(invalid_values.ok == false && invalid_values.error.code == 'invalid_type', 'config_update requires an object');

let invalid_type = config.update({ args: { values: { debug: 'true' } } });
assert(invalid_type.ok == false && invalid_type.error.code == 'invalid_type', 'boolean options reject strings');

let out_of_range = config.update({ args: { values: { download_retry: 101 } } });
assert(out_of_range.ok == false && out_of_range.error.code == 'out_of_range', 'integer options enforce ranges');

let unknown = config.update({ args: { values: { unknown_option: true } } });
assert(unknown.ok == false && unknown.error.code == 'unknown_option', 'unknown options are rejected');

let dedicated = config.update({ args: { values: { enabled: true } } });
assert(dedicated.ok == false && dedicated.error.code == 'dedicated_method_required', 'enabled requires dedicated method');

let dedicated_license = config.update({ args: { values: { license_key: 'new-key' } } });
assert(dedicated_license.ok == false && dedicated_license.error.code == 'dedicated_method_required', 'license_key requires dedicated method');

runtime.state.last_action = '';
let statistics = config.update({ args: { values: { statistics_enabled: false } } });
assert(statistics.ok == true, 'statistics update succeeds');
assert(statistics.reconciled == true && statistics.restarted == false, 'statistics-only update reconciles without restart');
assert(runtime.state.last_action == 'reconcile_statistics', 'statistics update requests reconciliation');
assert(core.values.statistics_enabled == '0', 'statistics update commits UCI value');

runtime.state.last_action = '';
runtime.state.refresh_count = 0;
let debug = config.update({ args: { values: { debug: true } } });
assert(debug.ok == true && debug.restarted == true, 'regular config update restarts service');
assert(runtime.state.last_action == 'restart', 'regular config update requests restart');
assert(runtime.state.refresh_count == 1, 'regular config update requests refresh');
assert(core.values.debug == '1', 'regular config update commits UCI value');

runtime.state.last_action = '';
runtime.state.refresh_count = 0;
let unchanged = config.update({ args: { values: { debug: true } } });
assert(unchanged.ok == true && length(unchanged.changed) == 0 && unchanged.restarted == false, 'unchanged config is a no-op');
assert(runtime.state.last_action == '' && runtime.state.refresh_count == 0, 'unchanged config does not touch runtime');

runtime.state.service_ok = false;
runtime.state.service_rc = 9;
let statistics_failure = config.update({ args: { values: { statistics_enabled: true } } });
assert(statistics_failure.ok == false && statistics_failure.committed == true, 'statistics reconcile failure reports committed configuration');
assert(statistics_failure.error.code == 'statistics_reconcile_failed' && statistics_failure.service_rc == 9, 'statistics reconcile failure preserves runtime error');

runtime.state.service_rc = 11;
let restart_failure = config.update({ args: { values: { download_retry: 4 } } });
assert(restart_failure.ok == false && restart_failure.committed == true, 'restart failure reports committed configuration');
assert(restart_failure.error.code == 'service_restart_failed' && restart_failure.service_rc == 11, 'restart failure preserves runtime error');
runtime.state.service_ok = true;
runtime.state.service_rc = 0;

let missing_enabled = config.set_enabled({ args: {} });
assert(missing_enabled.ok == false && missing_enabled.error.code == 'missing_argument', 'set_enabled requires enabled argument');

let invalid_enabled = config.set_enabled({ args: { enabled: 1 } });
assert(invalid_enabled.ok == false && invalid_enabled.error.code == 'invalid_type', 'set_enabled requires boolean');

let enabled = config.set_enabled({ args: { enabled: true } });
assert(enabled.ok == true && enabled.changed == true, 'set_enabled updates changed state');
assert(core.values.enabled == '1', 'set_enabled commits enabled state');

runtime.state.service_ok = false;
runtime.state.service_rc = 13;
let disable_failure = config.set_enabled({ args: { enabled: false } });
assert(disable_failure.ok == false && disable_failure.committed == true, 'set_enabled reports a committed change when runtime reconciliation fails');
assert(disable_failure.error.code == 'service_restart_failed' && disable_failure.service_rc == 13, 'set_enabled failure preserves runtime error');

print('ucode config tests: ok\n');
