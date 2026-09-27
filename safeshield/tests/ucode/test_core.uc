'use strict';

let core = require('core');

assert(core.trim('  example.com\n') == 'example.com', 'trim removes surrounding whitespace');
assert(core.trim('\t value \r\n') == 'value', 'trim removes tabs and line breaks');
assert(core.trim('value   ') == 'value', 'trim removes trailing whitespace');
assert(core.trim('   value') == 'value', 'trim removes leading whitespace');

assert(core.to_bool('1', false) == true, 'to_bool accepts 1');
assert(core.to_bool('yes', false) == true, 'to_bool accepts yes');
assert(core.to_bool('off', true) == false, 'to_bool accepts off');
assert(core.to_bool('invalid', true) == true, 'to_bool falls back to default');
assert(core.to_bool(null, false) == false, 'to_bool handles null');

assert(core.to_optional_bool('true') == true, 'to_optional_bool accepts true');
assert(core.to_optional_bool('0') == false, 'to_optional_bool accepts 0');
assert(core.to_optional_bool('') == null, 'to_optional_bool treats empty as null');
assert(core.to_optional_bool('invalid') == null, 'to_optional_bool rejects invalid values');

assert(core.to_int('42', 7) == 42, 'to_int converts numeric strings');
assert(core.to_int('', 7) == 7, 'to_int uses default for empty values');
assert(core.to_int(null, 7) == 7, 'to_int uses default for null');

assert(core.mask_secret('') == '', 'mask_secret keeps empty secrets empty');
assert(core.mask_secret('short') == '********', 'mask_secret fully masks short secrets');
assert(core.mask_secret('abcd1234wxyz') == 'abcd...wxyz', 'mask_secret partially masks long secrets');

let error = core.api_error('invalid_value', 'Invalid value', 'field_name');
assert(error.ok == false, 'api_error marks response as failed');
assert(error.error.code == 'invalid_value', 'api_error preserves error code');
assert(error.error.field == 'field_name', 'api_error preserves error field');
assert(core.bool_uci(true) == '1', 'bool_uci serializes true');
assert(core.bool_uci(false) == '0', 'bool_uci serializes false');

print('ucode core tests: ok\n');
