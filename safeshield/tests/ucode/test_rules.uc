'use strict';

let fs = require('fs');
let runtime = require('runtime');
let rules = require('rules');

let invalid_action = rules.add({ args: { action: 'deny', domain: 'example.com' } });
assert(invalid_action.ok == false && invalid_action.error.code == 'invalid_action', 'rules reject invalid actions');

let invalid_domain = rules.add({ args: { action: 'block', domain: 'bad..example.com' } });
assert(invalid_domain.ok == false && invalid_domain.error.code == 'invalid_domain', 'rules reject invalid domains');

let allow = rules.add({ args: { action: 'allow', domain: ' Example.COM ', refresh: false } });
assert(allow.ok == true && allow.added == true, 'allow rule is added');
assert(allow.domain == 'example.com', 'rule domain is normalized to lowercase');
assert(allow.refresh.reason == 'not_requested', 'refresh=false skips local apply');

let duplicate = rules.add({ args: { action: 'allow', domain: 'example.com' } });
assert(duplicate.ok == true && duplicate.added == false, 'duplicate rule is idempotent');
assert(duplicate.refresh.reason == 'unchanged', 'duplicate rule does not refresh');

runtime.state.apply_count = 0;
let block = rules.add({ args: { action: 'block', domain: '0.0.0.0 Ads.Example.COM' } });
assert(block.ok == true && block.domain == 'ads.example.com', 'hosts-format rule is normalized');
assert(runtime.state.apply_count == 1, 'changed rule requests local apply');

let listed = rules.list({ args: {} });
assert(listed.ok == true, 'rules_list succeeds');
assert(listed.counts.allow == 1 && listed.counts.block == 1, 'rules_list reports counts');
assert(listed.allow[0] == 'example.com', 'rules_list returns allow entry');
assert(listed.block[0] == 'ads.example.com', 'rules_list returns block entry');

let allow_only = rules.list({ args: { action: 'allow' } });
assert(length(allow_only.block) == 0 && length(allow_only.allow) == 1, 'rules_list filters by action');

let deleted = rules.delete({ args: { action: 'allow', domain: 'EXAMPLE.COM', refresh: false } });
assert(deleted.ok == true && deleted.deleted == true, 'rule_delete removes normalized rule');
assert(deleted.rules.counts.allow == 0, 'rule_delete returns updated rule count');

let content = fs.readfile(sprintf('%s/blocklist', TEST_TMP));
assert(content == 'ads.example.com\n', 'block rule file stores normalized domain');

print('ucode rules tests: ok\n');
