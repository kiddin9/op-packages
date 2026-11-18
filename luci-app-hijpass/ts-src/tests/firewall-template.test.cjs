const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const vm = require('node:vm');
const ts = require('typescript');
const path = require('node:path');

function formFixture(defaultTemplate = async () => 'default template\n') {
    const options = [], resources = [], writes = [], errors = [], hashes = [];
    let value = 'edited template';
    const section = { taboption(tab, type, field, title) {
        const input = { attributes: {}, setAttribute(name, value) { this.attributes[name] = value; } };
        const option = { tab, type, field, title, input,
            renderWidget() { return { querySelector: () => input }; },
            getUIElement() { return { setValue(content) { value = content; } }; },
        };
        options.push(option);
        return option;
    } };
    const context = vm.createContext({ exports: {}, _: value => value,
        require(name) {
            if (name === 'view') return { extend: value => value };
            if (name.endsWith('/backend')) return { Backend: {
                defaultFirewallTemplate: defaultTemplate,
                writeEditor: async (editor, content) => writes.push([editor.resource, content]),
            } };
            if (name === 'uci') return { load: async () => {}, set: (...args) => hashes.push(args) };
            if (name === 'form') return { ListValue: 'selector', Button: 'button', TextValue: 'editor' };
            if (name === 'hijpass.editor') return { configure() {} };
            if (name.endsWith('/hijpass')) return { LuciFlied: { CONF_NAME: 'hijpass' } };
            if (name.endsWith('/base/luci/form')) return { FormUtils: {
                createTextOption(section, tab, field, title, description, editor) {
                    resources.push(editor);
                    const option = section.taboption(tab, 'editor', field, title);
                    option.write = async (_, content) => writes.push([editor.resource, content]);
                    return option;
                },
            } };
            if (name.endsWith('/firewall/editor')) return { FirewallEditorUtils: { mount(widget, label) { widget.querySelector('textarea').setAttribute('aria-label', label); } } };
            if (name.endsWith('/firewall/form')) return { FirewallFormUtils: { createNftViewOption() {} } };
            if (name.endsWith('/firewall/migration')) return { FirewallMigrationUtils: { createDismissOption() {} } };
            if (name.endsWith('/base/luci/notification')) return { NotificationUtils: { error: (...args) => errors.push(args) } };
            if (name.endsWith('/save-apply/index')) return { SaveApplyUtils: { genHandleSaveApply() {} } };
            return {};
        },
    });
    const source = readFileSync(path.join(__dirname, '../views/firewall.ts'), 'utf8');
    vm.runInContext(ts.transpileModule(source, { compilerOptions: {
        module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, esModuleInterop: true,
    } }).outputText, context);
    context.createTextOptions(section);
    return { options, resources, writes, errors, hashes, get value() { return value; } };
}

test('firewall presents one untitled, labelled template editor and a native restore button', () => {
    const f = formFixture(), controls = f.options.filter(option => option.tab === 'nftables');
    assert.equal(controls.length, 2);
    assert.equal(controls.filter(option => option.type === 'selector').length, 0);
    const editor = controls.find(option => option.type === 'editor');
    assert.equal(editor.title, null);
    editor.renderWidget();
    assert.equal(editor.input.attributes['aria-label'], 'Firewall Template');
    assert.equal(controls.find(option => option.type === 'button').inputtitle, 'Restore Default Template');
    assert.equal(f.resources.filter(editor => editor.resource === 'firewall_template').length, 1);
    assert.equal(f.resources.some(editor => 'path' in editor), false);
});

test('restore changes the editor first, disables repeat clicks and delegates saving to the shared file draft editor', async () => {
    let complete;
    const f = formFixture(() => new Promise(resolve => { complete = resolve; }));
    const restore = f.options.find(option => option.field === '_restore_template');
    const button = { disabled: false }, pending = restore.onclick({ currentTarget: button }, 'fw');
    assert.equal(button.disabled, true);
    assert.equal(f.value, 'edited template');
    complete('default template\n');
    await pending;
    assert.equal(button.disabled, false);
    assert.equal(f.value, 'default template');
    assert.deepEqual(f.writes, []);
    assert.deepEqual(f.hashes, []);
    await f.options.find(option => option.field === 'nft_hash').write('fw', f.value);
    assert.deepEqual(f.writes, [['firewall_template', 'default template']]);
    assert.deepEqual(f.hashes, []);
});

test('failed restore preserves current edits and re-enables the button', async () => {
    const f = formFixture(async () => { throw new Error('default unavailable'); });
    const button = { disabled: false };
    await f.options.find(option => option.field === '_restore_template').onclick({ currentTarget: button }, 'fw');
    assert.equal(button.disabled, false);
    assert.equal(f.value, 'edited template');
    assert.equal(f.errors[0][1], 'default unavailable');
    assert.deepEqual(f.writes, []);
});

test('ACL limits native editor access to configuration files and keeps server JSON read-only', () => {
    const acl = JSON.parse(readFileSync(path.join(__dirname, '../../root/usr/share/rpcd/acl.d/luci-app-hijpass.json'), 'utf8'))['luci-app-hijpass'];
    assert.ok(acl.read.ubus.hijpass.includes('firewall_template_default'));
    assert.equal(acl.read.ubus.hijpass.includes('firewall_chains'), false);
    assert.deepEqual(acl.read.file['/etc/hijpass/firewall.ut'], ['read']);
    assert.deepEqual(acl.write.file['/etc/hijpass/firewall.ut'], ['write']);
    assert.deepEqual(acl.read.file['/etc/hijpass/server/*.json'], ['read']);
    assert.equal(acl.write.file['/etc/hijpass/server/*.json'], undefined);
    assert.equal(acl.write.file['/etc/*'], undefined);
    assert.deepEqual(acl.write['cgi-io'], ['upload']);
    assert.deepEqual(acl.read['cgi-io'], ['download']);
    assert.equal(acl.read.ubus.hijpass.includes('editor_write'), false);
    assert.equal(acl.write.ubus.hijpass.includes('editor_write'), false);
});
