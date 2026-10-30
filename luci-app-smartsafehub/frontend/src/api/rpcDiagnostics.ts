// Browser-local, bounded RPC diagnostics. Never store URL, session, request
// arguments, headers, response data, or error messages.
export const RPC_SLOW_THRESHOLD_MS = 1_500;
const MAX_RECENT = 60;
const MAX_METHODS = 64;

export interface RpcTiming {
  object: string;
  method: string;
  elapsedMs: number;
  responseMs: number | null;
  decodeMs: number | null;
  result: string;
}

interface RpcEvent extends RpcTiming {
  at: string;
}

interface RpcSummary {
  method: string;
  calls: number;
  slow: number;
  errors: number;
  lastMs: number;
  maxMs: number;
  averageMs: number;
}

interface MutableSummary extends RpcSummary { totalMs: number }

export interface RpcDiagnosticsSnapshot {
  slowThresholdMs: number;
  summary: RpcSummary[];
  recent: RpcEvent[];
}

export interface RpcDiagnosticsApi {
  snapshot: () => RpcDiagnosticsSnapshot;
  reset: () => void;
}

declare global {
  interface Window {
    __SMARTHUB_RPC_DIAGNOSTICS__?: RpcDiagnosticsApi;
  }
}

const summaries = new Map<string, MutableSummary>();
const recent: RpcEvent[] = [];

function rounded(milliseconds: number | null): number | null {
  return milliseconds === null ? null : Math.max(0, Math.round(milliseconds));
}

export function recordRpcTiming(timing: RpcTiming): boolean {
  const method = `${timing.object}.${timing.method}`;
  const elapsedMs = rounded(timing.elapsedMs) ?? 0;
  const slow = elapsedMs >= RPC_SLOW_THRESHOLD_MS;
  const failed = timing.result !== 'ok';
  let summary = summaries.get(method);
  if (!summary && summaries.size < MAX_METHODS) {
    summary = { method, calls: 0, slow: 0, errors: 0, lastMs: 0, maxMs: 0, averageMs: 0, totalMs: 0 };
    summaries.set(method, summary);
  }
  if (summary) {
    summary.calls++;
    summary.slow += Number(slow);
    summary.errors += Number(failed);
    summary.totalMs += elapsedMs;
    summary.lastMs = elapsedMs;
    summary.maxMs = Math.max(summary.maxMs, elapsedMs);
    summary.averageMs = Math.round(summary.totalMs / summary.calls);
  }

  if (slow || failed) {
    recent.push({
      at: new Date().toISOString(),
      object: timing.object,
      method: timing.method,
      elapsedMs,
      responseMs: rounded(timing.responseMs),
      decodeMs: rounded(timing.decodeMs),
      result: timing.result,
    });
    if (recent.length > MAX_RECENT) recent.shift();
  }
  return slow;
}

export function snapshotRpcDiagnostics(): RpcDiagnosticsSnapshot {
  return {
    slowThresholdMs: RPC_SLOW_THRESHOLD_MS,
    summary: [...summaries.values()].map(({ totalMs: _totalMs, ...summary }) => ({ ...summary })),
    recent: recent.map((entry) => ({ ...entry })),
  };
}

export function resetRpcDiagnostics(): void {
  summaries.clear();
  recent.length = 0;
}

const diagnosticsApi: RpcDiagnosticsApi = {
  snapshot: snapshotRpcDiagnostics,
  reset: resetRpcDiagnostics,
};

export function ensureRpcDiagnostics(): void {
  // Enable in production as well, without persistent storage or remote transfer.
  window.__SMARTHUB_RPC_DIAGNOSTICS__ ??= diagnosticsApi;
}
