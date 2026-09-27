'use strict';

let core = require('core');
let runtime = require('runtime');
let license = require('license');

let current = license.get();
assert(current.ok == true && current.license.key == 'existing-license-key', 'license_get returns current key');

let missing = license.update({ args: {} });
assert(missing.ok == false && missing.error.code == 'missing_argument', 'license_update requires license_key');

let multiline = license.update({ args: { license_key: 'line1\nline2' } });
assert(multiline.ok == false && multiline.error.code == 'invalid_license_key', 'license_update rejects line breaks');

let oversized_key = '';
for (let i = 0; i < 513; i++) oversized_key += 'x';
let too_long = license.update({ args: { license_key: oversized_key } });
assert(too_long.ok == false && too_long.error.code == 'invalid_license_key', 'license_update rejects keys longer than 512 characters');

runtime.state.refresh_count = 0;
runtime.state.statistics_reset_count = 0;
let updated = license.update({ args: { license_key: '  new-license-key  ' } });
assert(updated.ok == true && updated.changed == true, 'license_update accepts a new key');
assert(core.state.license_key == 'new-license-key', 'license_update trims key before saving');
assert(updated.license.key_masked == 'new-...-key', 'license_update masks saved key');
assert(runtime.state.refresh_count == 1, 'license_update requests refresh after change');
assert(runtime.state.statistics_reset_count == 1, 'license_update resets statistics upload entitlement after change');

runtime.state.refresh_count = 0;
runtime.state.statistics_reset_count = 0;
let unchanged = license.update({ args: { license_key: 'new-license-key' } });
assert(unchanged.ok == true && unchanged.changed == false, 'unchanged license does not write');
assert(runtime.state.refresh_count == 0, 'unchanged license does not refresh');
assert(runtime.state.statistics_reset_count == 0, 'unchanged license keeps statistics upload entitlement');

runtime.state.statistics_reset_count = 0;
let cleared = license.update({ args: { license_key: '' } });
assert(cleared.ok == true && cleared.changed == true, 'empty license clears configured key');
assert(core.state.license_key == '' && core.state.deletes == 1, 'empty license uses delete helper');
assert(cleared.license.configured == false, 'cleared license is reported unconfigured');
assert(runtime.state.statistics_reset_count == 1, 'clearing the license resets statistics upload entitlement');

print('ucode license tests: ok\n');
