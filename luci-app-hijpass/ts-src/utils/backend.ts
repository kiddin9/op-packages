import rpc from 'rpc';
import drafts from 'hijpass.drafts';

export type EditorResource = 'ip_direct' | 'ip_proxy' | 'domain_direct' | 'domain_proxy'
    | 'nft_hook' | 'dns_hook' | 'shunt_conf' | 'firewall_template' | 'proxy_config' | 'server_config';
export type Editor = { resource: EditorResource; section?: string; name?: string };
export type Log = { id: string; kind: 'main' | 'shunt' | 'proxy' | 'server'; name: string };
export type UpdateProgress = { phase: string; resource: string; attempt?: number; bytes?: number | null };
export type ProgressHandler = (progress: UpdateProgress) => void;

export type RuleUpdateResult = { success: boolean; failed?: string[]; code?: string };

// 页面只使用业务方法；编辑文件由 drafts 模块通过 LuCI 原生接口读写。
function method(name: string, params: string[] = [], nobatch = false) {
    const call = rpc.declare({ object: 'hijpass', method: name, params, reject: true, nobatch,
        expect: { '': { error: 'Invalid backend response' } } });
    return async (...args: any[]) => {
        const result = await call(...args);
        if (result.error) throw new Error(result.error);
        return result;
    };
}

const logRead = method('log_read', ['id', 'action', 'lines']);
const firewallShow = method('firewall_show');
const firewallDefault = method('firewall_template_default');
const logs = method('log_list');
const jobStatus = method('job_status', ['id']);

// 每次轮询都是短 RPC；页面等待不会占住一次持续下载的 RPC 请求。
async function runJob(start: (...args: any[]) => Promise<any>, jsonOutput: boolean, onProgress?: ProgressHandler, ...args: any[]) {
    const job = await start(...args);
    if (job.success === false) return job;
    return waitForJob(job.id, jsonOutput, onProgress);
}

async function waitForJob(id: string, jsonOutput: boolean, onProgress?: ProgressHandler) {
    if (typeof id !== 'string' || !/^[A-Za-z0-9]{8}$/.test(id)) throw new Error('Invalid job ID');
    const deadline = Date.now() + 30 * 60 * 1000;
    while (Date.now() < deadline) {
        const status = await jobStatus(id);
        if (!status.running) {
            const result = jsonOutput ? JSON.parse(status.stdout || '{}') : status;
            if (result.error) throw new Error(result.error);
            if (status.code !== 0) {
                if (jsonOutput && result.success === false) return result;
                throw new Error(_('Backend operation failed; see main log'));
            }
            return result;
        }
        if (status.progress) onProgress?.(status.progress);
        await new Promise(resolve => window.setTimeout(resolve, 1000));
    }
    throw new Error('Timed out waiting for backend job');
}

const coreCalls = {
    version: method('core_version', ['core']),
    latest: method('core_latest', ['core'], true),
    update: (core: string, onProgress?: ProgressHandler) => runJob(method('core_update', ['core']), true, onProgress, core),
};

export const Backend = {
    defaultFirewallTemplate: async (): Promise<string> => (await firewallDefault()).content,
    readEditor: (editor: Editor): Promise<string> => drafts.read(editor),
    renderConfigs: method('config_render', ['sections', 'target']),
    validateConfigs: method('config_validate', ['sections']),
    logList: async (): Promise<Log[]> => (await logs()).logs,
    readLog: async (id: string, lines: string = '200'): Promise<string> => (await logRead(id, 'read', lines)).content,
    downloadLog: (id: string) => logRead(id, 'download', ''),
    clearLog: method('log_clear', ['id']),
    renderServer: method('server_render', ['sections', 'target']),
    validateServers: method('server_validate', ['sections']),
    cleanupNode: method('cleanup_node', ['kind', 'section', 'name']),
    restartService: () => runJob(method('service_restart'), false),
    resetFirewall: method('firewall_reset'),
    showFirewall: async (): Promise<string> => {
        const result = await firewallShow();
        if (result.code !== 0) throw new Error(result.stderr || 'Cannot read firewall rules');
        return result.stdout;
    },
    connect: method('network_connect', ['url', 'timeout']),
    ping: method('network_ping', ['port']),
    updateRules: (onProgress?: ProgressHandler): Promise<RuleUpdateResult> => runJob(method('rule_update'), true, onProgress),
    ruleUpdateStatus: (): Promise<{ id: string | null }> => method('rule_update_status', [], true)(),
    resumeRuleUpdate: (id: string, onProgress?: ProgressHandler): Promise<RuleUpdateResult> => waitForJob(id, true, onProgress),
    queryRules: method('rule_query', ['keyword']),
    matchRule: method('rule_match', ['keyword']),
    lookupGeo: method('geo_lookup', ['type', 'keyword', 'mode']),
    queryGeo: method('geo_query', ['keyword']),
    coreAction: (action: 'version' | 'latest' | 'update', core: string, onProgress?: ProgressHandler) => coreCalls[action](core, onProgress),
    coreUpdateStatus: (core: string): Promise<{ id: string | null }> => method('core_update_status', ['core'], true)(core),
    resumeCoreUpdate: (id: string, onProgress?: ProgressHandler) => waitForJob(id, true, onProgress),
    traceCapabilities: (): Promise<{ tcpdump: boolean }> => method('trace_capabilities')(),
    startTrace: method('trace_start', ['args']),
    traceStatus: method('trace_status', ['id']),
    releaseTrace: method('trace_release', ['id']),
};
