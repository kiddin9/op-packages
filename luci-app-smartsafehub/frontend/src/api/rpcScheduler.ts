/** Shared bounded queue. Reserve one connection for user-triggered requests. */
export type RpcPriority = 'high' | 'normal' | 'low';
interface Waiter {
  priority: RpcPriority;
  start: (release: () => void) => void;
  abort: () => void;
}
const MAX_RUNNING = 4;
const MAX_BACKGROUND = 3;
let running = 0;
let background = 0;
const queue: Waiter[] = [];

function drain() {
  while (running < MAX_RUNNING) {
    const index = queue.findIndex((waiter) => waiter.priority !== 'low' || background < MAX_BACKGROUND);
    if (index === -1) return;
    const waiter = queue.splice(index, 1)[0];
    if (!waiter) continue;
    running += 1;
    if (waiter.priority === 'low') background += 1;
    waiter.start(() => {
      running -= 1;
      if (waiter.priority === 'low') background -= 1;
      drain();
    });
  }
}

export function acquireRpcSlot(priority: RpcPriority, signal?: AbortSignal): Promise<() => void> {
  if (signal?.aborted) return Promise.reject(new DOMException('Cancelled', 'AbortError'));
  return new Promise((resolve, reject) => {
    const waiter: Waiter = {
      priority,
      start: (release) => { signal?.removeEventListener('abort', waiter.abort); resolve(release); },
      abort: () => {
        const index = queue.indexOf(waiter);
        if (index !== -1) queue.splice(index, 1);
        signal?.removeEventListener('abort', waiter.abort);
        reject(new DOMException('Cancelled', 'AbortError'));
      },
    };
    signal?.addEventListener('abort', waiter.abort, { once: true });
    // Preserve FIFO within priority while permitting interactive RPC ahead of polls.
    const last = queue.findIndex((item) =>
      (priority === 'high' && item.priority !== 'high') ||
      (priority === 'normal' && item.priority === 'low'));
    if (last === -1) queue.push(waiter);
    else queue.splice(last, 0, waiter);
    drain();
  });
}
