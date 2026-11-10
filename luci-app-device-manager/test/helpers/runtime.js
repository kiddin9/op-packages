'use strict';
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '../..');

String.prototype.format = function(...values) {
    let index = 0;
    return this.replace(/%[sd]/g, () => String(values[index++]));
};

class Node extends EventTarget {
    constructor(tag, attrs = {}) {
        super();
        this.tag = tag;
        this.attrs = attrs;
        this.children = [];
        this.style = {};
        // LuCI sets every non-null attribute; even disabled="false" disables a button.
        this.disabled = attrs.disabled != null;
        this.selected = false;
        this._value = attrs.value;
        this.classes = new Set((attrs.class || '').split(/\s+/));
        this.classList = { add: name => this.classes.add(name), remove: name => this.classes.delete(name) };
        for (const [name, value] of Object.entries(attrs)) {
            if (typeof value === 'function') this.addEventListener(name, event => { this.operation = value(event); });
        }
    }
    appendChild(child) { this.children.push(child); return child; }
    get value() {
        if (this._value != null) return this._value;
        if (this.tag === 'select') {
            const option = this.children.find(child => child.selected) || this.children[0];
            return option ? option.attrs.value : '';
        }
        return '';
    }
    set value(value) { this._value = value; }
    get textContent() { return this.children.map(child => child instanceof Node ? child.textContent : String(child)).join(''); }
    set textContent(value) { this.children = [String(value)]; }
    querySelectorAll(selector) {
        return this.children.filter(child => child instanceof Node).flatMap(child => [child, ...child.querySelectorAll('*')])
            .filter(child => selector === '*' || selector === child.tag ||
                (selector.startsWith('#') && child.attrs.id === selector.slice(1)) ||
                (selector.startsWith('.') && child.classes.has(selector.slice(1))));
    }
    querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
    focus() { this.focused = true; }
    remove() { this.removed = true; }
    getAttribute(name) { return this.attrs[name]; }
    click() {
        if (this.disabled) return Promise.resolve();
        this.dispatchEvent(new Event('click'));
        return Promise.resolve(this.operation);
    }
}

function environment(extra = {}) {
    const htmlSinks = [], notifications = [];
    const timeouts = new Map(), session = new Map();
    let nextTimeout = 1;
    const E = (tag, attrs, children) => {
        if (!attrs || typeof attrs !== 'object' || Array.isArray(attrs)) { children = attrs; attrs = {}; }
        const node = new Node(tag, attrs);
        if (Array.isArray(children)) children.forEach(child => node.appendChild(child));
        else if (children instanceof Node) node.appendChild(children);
        else if (children != null) {
            // Match LuCI dom.append: scalar content uses innerHTML, array items use text nodes.
            htmlSinks.push(String(children));
            node.appendChild(String(children));
        }
        return node;
    };
    const dom = { content: (node, children) => {
        node.children = [];
        if (Array.isArray(children)) children.forEach(child => node.appendChild(child));
        else if (children != null) node.appendChild(children);
    } };
    const ui = {
        modal: null,
        showModal(title, children) { this.modal = E('modal', { title }, children); },
        hideModal() { ui.modal = null; },
        addNotification(title, content, level) {
            const node = new Node('notification');
            notifications.push({ content, level, node });
            return node;
        }
    };
    return Object.assign({
        baseclass: { extend: value => value }, view: { extend: value => value }, E, dom, ui,
        rpc: { declare: () => () => Promise.resolve({ language: 'auto' }) },
        _: value => value, htmlSinks, notifications, timeouts,
        setTimeout: (callback, delay) => { const id = nextTimeout++; timeouts.set(id, { callback, delay }); return id; },
        clearTimeout: id => timeouts.delete(id),
        L: { hasViewPermission: () => true, resource: value => '/resources/' + value },
        window: {
            localStorage: { getItem: () => null, setItem() {} },
            sessionStorage: { getItem: key => session.get(key) || null, setItem: (key, value) => session.set(key, value), removeItem: key => session.delete(key) }
        }
    }, extra);
}

function loadModule(name, env, cache = new Map()) {
    if (cache.has(name)) return cache.get(name);
    const file = path.join(root, 'htdocs/luci-static/resources', name.replace(/\./g, '/') + '.js');
    const source = fs.readFileSync(file, 'utf8');
    const dependencies = Object.assign({}, env);
    for (const match of source.matchAll(/'require ([\w.-]+)(?: as (\w+))?';/g)) {
        const [, dependency, alias] = match;
        dependencies[alias || dependency] = env[dependency] || loadModule(dependency, env, cache);
    }
    const result = new Function(...Object.keys(dependencies), source)(...Object.values(dependencies));
    cache.set(name, result);
    return result;
}

function backend(initial = []) {
    const clone = value => JSON.parse(JSON.stringify(value));
    const state = { saved: clone(initial), staged: null, cached: null, reads: 0, commits: 0, reverts: 0, calls: [], declarations: [] };
    const uci = {
        unload() { state.cached = null; },
        load() {
            if (!state.cached) { state.reads++; state.cached = clone(state.staged || state.saved); }
            return Promise.resolve();
        },
        sections(config, type) { return state.cached.filter(section => section['.type'] === type); },
        get(config, id) { return state.cached.find(section => section['.name'] === id) || null; },
        add(config, type, id) { state.cached.push({ '.type': type, '.name': id }); return id; },
        set(config, id, key, value) { uci.get(config, id)[key] = value; },
        unset(config, id, key) { delete uci.get(config, id)[key]; },
        remove(config, id) { state.cached = state.cached.filter(section => section['.name'] !== id); },
        save() {
            state.staged = clone(state.cached);
            return state.failSave ? Promise.reject(new Error('save failed')) : Promise.resolve();
        }
    };
    const replies = {
        'luci-rpc.getHostHints': {},
        'luci-rpc.getDHCPLeases': { dhcp_leases: [], dhcp6_leases: [] },
        'luci-rpc.getWirelessDevices': {},
        'luci-rpc.getNetworkDevices': {},
        'luci.device-manager.get_online_status': { ok: true, neighbors: [] },
        'luci.device-manager.scan_devices': { ok: true },
        'luci.device-manager.ping_device': { ok: true, ip: '192.168.1.20', interface: 'br-lan', reachable: true, output: '1 packets transmitted, 1 packets received' },
        'iwinfo.assoclist': { results: [] }
    };
    const rpc = { getSessionID: () => state.session || 'test-session', declare(options) {
        state.declarations.push(options);
        return (...args) => {
            const key = options.object + '.' + options.method;
            state.calls.push({ key, args });
            if (key === 'uci.commit') {
                if (state.failCommit) return options.reject ? Promise.reject(new Error('commit failed')) : Promise.resolve(6);
                state.saved = clone(state.staged || state.saved); state.staged = null; state.commits++;
                return Promise.resolve({});
            }
            if (key === 'uci.revert') {
                state.reverts++;
                if (state.failRevert) return Promise.reject(new Error('revert failed'));
                state.staged = null; return Promise.resolve({});
            }
            const result = typeof replies[key] === 'function' ? replies[key](...args) : replies[key];
            return result instanceof Error ? Promise.reject(result) : Promise.resolve(clone(result));
        };
    } };
    return { state, uci, rpc, replies, fs: { read: () => Promise.resolve('IP address HW type Flags HW address Mask Device\n') } };
}

async function renderLoadedPage(page) {
    const node = page.render(await page.load());
    if (page.initialLoading) await page.refresh();
    return node;
}

module.exports = { root, Node, environment, loadModule, backend, renderLoadedPage };
