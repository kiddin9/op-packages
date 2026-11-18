import baseclass from 'baseclass';
import uci from 'uci';
import ui from 'ui';
import request from 'request';
import session from 'session';
import fs from 'fs';
import rpc from 'rpc';
import type { Editor } from '../utils/backend';
import { fileDiff } from '../utils/feature/config/diff';
import { DraftStore, FileDraft, normalizeFile } from '../utils/feature/config/drafts';

const sid: string = L.env.sessionid;
const store = new DraftStore(sid);
const changes = ui.changes;
const notice = (error: Error) => ui.addNotification(null, E('p', {}, error.message), 'error');
let uploaded: FileDraft[] = [];
let applying: Promise<void> | null = null;

const access = rpc.declare({ object: 'session', method: 'access',
    params: ['scope', 'object', 'function'], expect: { access: false } });
const activeSessions = rpc.declare({ object: 'hijpass', method: 'editor_sessions',
    params: ['sessions'], expect: { '': {} }, reject: true });

async function checkSession() {
    const allowed = await access('access-group', 'luci-app-hijpass', 'write').catch(async error => {
        // 原生 LuCI 可能在返回 access=false 前直接拒绝过期会话；网络故障保留草稿。
        if (error.name === 'SessionError' || (error.name === 'RPCError' && /-32002/.test(error.message))) await store.clear();
        throw error;
    });
    if (!allowed) {
        await store.clear();
        throw new Error(_('Login session expired or file access denied'));
    }
}

function filePath(editor: Editor): string {
    const paths = {
        ip_direct: '/etc/hijpass/rules/ip-direct.txt', ip_proxy: '/etc/hijpass/rules/ip-proxy.txt',
        domain_direct: '/etc/hijpass/rules/domain-direct.txt', domain_proxy: '/etc/hijpass/rules/domain-proxy.txt',
        firewall_template: '/etc/hijpass/firewall.ut', nft_hook: '/etc/hijpass/hook/nft-hook.sh',
        dns_hook: '/etc/hijpass/hook/dns-hook.sh', shunt_conf: '/etc/hijpass/shunt.json',
    };
    if (Object.hasOwn(paths, editor.resource)) return paths[editor.resource];
    if (!['proxy_config', 'server_config'].includes(editor.resource)) throw new Error('Unknown editor resource');
    const server = editor.resource === 'server_config', id = editor.section;
    const name = editor.name || uci.get(server ? 'hijserver' : 'hijpass', id, 'name') || id;
    if (!id || !/^[A-Za-z0-9_-]+$/.test(id) || typeof name !== 'string' || /[\/\\\r\n\0]/.test(name))
        throw new Error('Invalid node name or section ID');
    return `/etc/hijpass/${server ? 'server' : 'client'}/${name}-${id}.json`;
}

async function readFile(editor: Editor): Promise<string> {
    try { return normalizeFile(await fs.read_direct(filePath(editor))); }
    catch (error) {
        if (error.name === 'NotFoundError' && ['proxy_config', 'server_config', 'shunt_conf'].includes(editor.resource)) return '';
        throw error;
    }
}

async function writeFile(draft: FileDraft) {
    if (draft.editor.resource === 'server_config') throw new Error('Server configurations are generated from UCI');
    const data = new FormData();
    data.append('sessionid', sid);
    data.append('filename', filePath(draft.editor));
    data.append('filemode', ['dns_hook', 'nft_hook'].includes(draft.editor.resource) ? '0755' : '0600');
    // 与 LuCI 文本编辑器一致，空内容也保留末尾换行，原生上传不接受零字节文件。
    data.append('filedata', new Blob([draft.content + '\n']), 'config');
    const response = await request.request((L.env.cgi_base || '/cgi-bin') + '/cgi-upload', {
        method: 'POST', content: data, timeout: 0,
    });
    const result = response.json();
    if (!response.ok || result.failure || result.error)
        throw new Error(result.message || result.error || _('Cannot write configuration file'));
}

async function read(editor: Editor): Promise<string> {
    const draft = await store.get(editor);
    if (draft) {
        await checkSession();
        return draft.content;
    }
    return readFile(editor);
}

async function save(editor: Editor, value: string, section: string, field: string) {
    await checkSession();
    const content = normalizeFile(value);
    if (new Blob([content]).size > 16 * 1024 * 1024) throw new Error(_('Configuration file exceeds 16 MiB'));
    const previous = await store.get(editor);
    // 重命名节点时，比较新文件的内容；不能沿用原文件的基线。
    const original = previous && previous.editor.name === editor.name ? previous.original
        : await readFile(editor);
    if (content === original) {
        if (previous) await store.remove(previous);
    } else {
        await store.put({ id: store.key(editor), editor, section, field, original, content,
            revision: Date.now() + ':' + Math.random() });
    }
    await refresh();
    channel?.postMessage('changed');
}

function hash(content: string) {
    let result = 0;
    for (let i = 0; i < content.length; i++) result = ((result << 5) - result + content.charCodeAt(i)) | 0;
    return String(result);
}

async function upload() {
    uploaded = [];
    const drafts = await store.list();
    if (!drafts.length) return;
    await checkSession();
    // 全局应用可能发生在其他页面；重新读取同一 RPC session 的待提交 UCI。
    uci.unload('hijpass');
    await uci.load('hijpass');
    for (const draft of drafts) {
        const section = uci.get('hijpass', draft.section);
        if (!section || (['proxy_config', 'shunt_conf'].includes(draft.editor.resource) && section.config_type === 'tmpl')) {
            await store.remove(draft); continue;
        }
        if (draft.editor.resource === 'proxy_config') {
            const name = section.name || draft.section;
            if (name !== draft.editor.name) {
                draft.editor = { ...draft.editor, name };
                draft.original = '';
            }
        }
        uploaded.push(draft);
    }
    for (const draft of uploaded) {
        await writeFile(draft);
        uci.set('hijpass', draft.section, draft.field, hash(draft.content));
    }
    await uci.save();
}

async function finish() {
    for (const draft of uploaded) await store.complete(draft);
    uploaded = [];
    await refresh();
    channel?.postMessage('changed');
}

function label(editor: Editor) {
    const names = { ip_direct: _('IP Direct List'), ip_proxy: _('IP Proxy List'),
        domain_direct: _('Domain Direct List'), domain_proxy: _('Domain Proxy List'),
        firewall_template: _('Firewall Template'), nft_hook: _('Firewall Hook'), dns_hook: _('DNS Hook'),
        shunt_conf: _('Edit Shunt Configuration File'), proxy_config: _('Proxy Configuration'), server_config: _('Server Configuration') };
    return names[editor.resource] + (editor.section ? ': ' + (editor.name || editor.section) : '');
}

async function revertFiles() {
    const drafts = await store.list();
    // 先读取正式文件；失败时保留草稿和当前表单，供用户重试。
    const contents = await Promise.all(drafts.map(async draft =>
        readFile(draft.editor)));
    await store.clear();
    for (const [index, draft] of drafts.entries()) {
        for (const map of document.querySelectorAll('.cbi-map')) {
            const option = L.dom.callClassMethod(map, 'lookupOption', draft.field, draft.section)?.[0] as LuCI.form.AbstractValue;
            if (!option) continue;
            option.cfgvalue(draft.section, contents[index]);
            option.getUIElement(draft.section)?.setValue(contents[index]);
        }
    }
    await refresh();
    channel?.postMessage('changed');
    ui.hideModal();
}

async function showDrafts() {
    const drafts = await store.list();
    const list = E('div', { class: 'uci-change-list' });
    for (const draft of drafts) {
        const diff = fileDiff(draft.original, draft.content);
        list.appendChild(E('h5', {}, document.createTextNode('# ' + label(draft.editor))));
        list.appendChild(E('var', { style: 'max-height:50vh;overflow:auto;white-space:pre' },
            diff.lines.map(line => E(line.startsWith('+') ? 'ins' : line.startsWith('-') ? 'del' : 'span',
                { style: 'display:block;min-height:1em' }, document.createTextNode(line)))));
        if (diff.truncated) list.appendChild(E('p', {}, _('Diff preview is limited; open the editor to view the full content.')));
    }
    list.appendChild(E('br'));
    const dialog = ui.showModal(_('Configuration files') + ' / ' + _('Changes'), [
        E('div', { class: 'cbi-section' }, [
            E('strong', {}, _('Legend:')),
            E('div', { class: 'uci-change-legend' }, [
                E('div', { class: 'uci-change-legend-label' }, [E('var', {}, E('ins', {}, '\u00a0')), ' ', _('Added lines')]),
                E('div', { class: 'uci-change-legend-label' }, [E('var', {}, E('del', {}, '\u00a0')), ' ', _('Removed lines')]),
            ]),
            E('br'), list,
            E('div', { class: 'button-row' }, [
                E('button', { class: 'btn cbi-button', click: ui.hideModal }, _('Close')), ' ',
                new ui.ComboButton('0', { 0: [_('Save & Apply')], 1: [_('Apply unchecked')] }, {
                    classes: { 0: 'btn cbi-button cbi-button-positive important', 1: 'btn cbi-button cbi-button-negative important' },
                    click: (_event: Event, mode: string) => changes.apply(mode === '0'),
                }).render(), ' ',
                E('button', { class: 'btn cbi-button cbi-button-reset', click: async (event: Event) => {
                    const button = event.currentTarget as HTMLButtonElement;
                    button.disabled = true;
                    try { await revertFiles(); }
                    catch (error) { notice(error); }
                    finally { button.disabled = false; }
                } }, _('Revert')),
            ]),
        ]),
    ]);
    dialog.classList.add('uci-dialog');
}

async function refresh() {
    const drafts = await store.list();
    // 原生提示按 ID 排序：poll-status、uci-changes、uci-file-changes。
    if (drafts.length) ui.showIndicator('uci-file-changes', _('Pending files: %d').format(String(drafts.length)), () => showDrafts().catch(notice));
    else ui.hideIndicator('uci-file-changes');
}

// 不复制 LuCI 的确认、回滚和重连逻辑。只在用户确认后、原生应用 POST 发出前上传。
const nativeRequest = request.request;
const applyUrls = [L.url('admin/uci/apply_rollback'), L.url('admin/uci/apply_unchecked')];
request.request = function (url, options) {
    if (!applyUrls.includes(url) || options?.method?.toLowerCase() !== 'post') return nativeRequest.call(this, url, options);
    if (applying) return Promise.resolve({ status: 409, responseText: _('Configuration apply is already in progress') });
    applying = upload();
    return applying.then(() => nativeRequest.call(this, url, options)).then(async response => {
        // checked apply 返回 204 表示 UCI 无变化；文件可能已在上次重试中应用。
        if (response.status === 204 && url === applyUrls[0]) await finish();
        return response;
    }).catch(error => ({ status: 409, responseText: error.message })).finally(() => { applying = null; });
};
document.addEventListener('uci-applied', () => { finish().catch(notice); });
document.addEventListener('uci-reverted', () => { store.clear().then(refresh).then(() => channel?.postMessage('changed')).catch(notice); });
const channel = typeof BroadcastChannel === 'function' ? new BroadcastChannel('hijpass-file-drafts:' + sid) : null;
if (channel) channel.onmessage = () => refresh().catch(notice);

// 新功能首次安装时，此 session 可能已缓存空的 preload 列表。
const preloads = session.getLocalData('preload');
if (Array.isArray(preloads) && !preloads.includes('preload.hijpass')) session.setLocalData('preload', [...preloads, 'preload.hijpass']);
async function initialize() {
    // 原生 session.list 不触碰其他会话的超时；只清理 rpcd 已销毁的会话草稿。
    const previous = (await store.sessions()).filter(value => value !== sid);
    if (previous.length) {
        const result = await activeSessions(previous);
        if (result.error || !Array.isArray(result.sessions)) throw new Error(result.error || 'Invalid session response');
        for (const id of previous) if (!result.sessions.includes(id)) await store.clear(id);
    }
    if ((await store.list()).length) await checkSession();
    await refresh();
}
// preload 在 DOM 就绪后加载，直接初始化，避免等待已触发的 luci-loaded。
initialize().catch(notice);

export default baseclass.extend({ read, save }) as { read: typeof read; save: typeof save };
