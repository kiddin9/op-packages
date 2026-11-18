const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');

function fixture(global) {
    const context = vm.createContext({ exports: {}, _: text => text,
        E: (tag, attrs, children) => ({ tag, attrs, children }),
        require(name) {
            if (name === 'uci') return { get_first: () => global };
            if (name === 'form') return { Flag: 'flag' };
            return { LuciFlied: { CONF_NAME: 'hijpass', GLOBAL_SECTION_TYPE: 'hijpass' } };
        },
    });
    vm.runInContext("String.prototype.format = function(value) { return this.replace('%s', value); };", context);
    const source = readFileSync(path.join(__dirname, '../utils/feature/firewall/migration.ts'), 'utf8');
    vm.runInContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, esModuleInterop: true } }).outputText, context);
    return context.exports.FirewallMigrationUtils;
}

test('legacy template notice names the source and dismiss option saves against the global section', () => {
    const source = '/custom/old-template.nft';
    const utils = fixture({ '.name': 'global', legacy_firewall_template: source });
    const notice = utils.renderNotice('/firewall');
    assert.equal(notice[0].attrs.role, 'status');
    assert.match(JSON.stringify(notice), /cannot be upgraded automatically/);
    assert.ok(JSON.stringify(notice).includes(source));
    assert.equal(notice[0].children.at(-1).attrs.href, '/firewall');
    const option = {};
    utils.createDismissOption({ taboption(tab, type, field) {
        assert.equal(tab, 'nftables');
        assert.equal(field, 'firewall_template_migration_ack');
        return option;
    } });
    assert.equal(option.ucisection, 'global');
    assert.equal(option.default, '0');
});

test('fresh installations and acknowledged migrations show neither notice nor dismiss option', () => {
    for (const global of [null, { '.name': 'global' }, { '.name': 'global', legacy_firewall_template: '/old.nft', firewall_template_migration_ack: '1' }]) {
        const utils = fixture(global);
        assert.equal(utils.renderNotice().length, 0);
        utils.createDismissOption({ taboption() { assert.fail('unexpected migration option'); } });
    }
});
