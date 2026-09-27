import type { RuntimeMemory } from '../types/status';

const NUMBER_FORMATTER = new Intl.NumberFormat('ko-KR');
const TIMESTAMP_FORMATTER = new Intl.DateTimeFormat('ko-KR', {
  dateStyle: 'medium',
  timeStyle: 'short',
});

export function formatUptime(totalSeconds: number): string {
  if (!Number.isFinite(totalSeconds) || totalSeconds < 0) {
    return '확인 불가';
  }

  const days = Math.floor(totalSeconds / 86_400);
  const hours = Math.floor((totalSeconds % 86_400) / 3_600);
  const minutes = Math.floor((totalSeconds % 3_600) / 60);

  if (days > 0) {
    return `${days}일 ${hours}시간`;
  }

  if (hours > 0) {
    return `${hours}시간 ${minutes}분`;
  }

  return `${Math.max(minutes, 1)}분`;
}

export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes < 0) {
    return '확인 불가';
  }

  const units = ['B', 'KB', 'MB', 'GB'];
  let value = bytes;
  let unitIndex = 0;

  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }

  return `${value.toFixed(unitIndex === 0 ? 0 : 1)} ${units[unitIndex] ?? 'B'}`;
}

export function formatLoadAverage(value: number): string {
  return Number.isFinite(value) ? (value / 65_536).toFixed(2) : '-';
}

export function formatNumber(value: number): string {
  return Number.isFinite(value) ? NUMBER_FORMATTER.format(value) : '-';
}

export function formatBootTime(localtime: number, uptime: number): string {
  if (
    !Number.isFinite(localtime) ||
    localtime <= 0 ||
    !Number.isFinite(uptime) ||
    uptime < 0
  ) {
    return '확인 불가';
  }

  return formatTimestamp(localtime - uptime);
}

export function formatTimestamp(timestamp: number): string {
  if (!Number.isFinite(timestamp) || timestamp <= 0) {
    return '기록 없음';
  }

  return TIMESTAMP_FORMATTER.format(new Date(timestamp * 1000));
}

export function formatRelativeTime(timestamp: number, nowTimestamp = Date.now() / 1000): string {
  if (!Number.isFinite(timestamp) || timestamp <= 0) {
    return '기록 없음';
  }

  const elapsedSeconds = Math.max(0, Math.floor(nowTimestamp - timestamp));

  if (elapsedSeconds < 60) {
    return '방금 전';
  }

  if (elapsedSeconds < 3_600) {
    return `${Math.floor(elapsedSeconds / 60)}분 전`;
  }

  if (elapsedSeconds < 86_400) {
    return `${Math.floor(elapsedSeconds / 3_600)}시간 전`;
  }

  return `${Math.floor(elapsedSeconds / 86_400)}일 전`;
}

export function formatTimestampInTimezone(
  timestamp: number,
  zonename: string,
): string {
  if (!Number.isFinite(timestamp) || timestamp <= 0) {
    return '확인 불가';
  }

  const normalizedZonename = zonename.replaceAll(' ', '_');

  try {
    return new Intl.DateTimeFormat('ko-KR', {
      dateStyle: 'medium',
      timeStyle: 'medium',
      timeZone: normalizedZonename,
    }).format(new Date(timestamp * 1000));
  } catch {
    return TIMESTAMP_FORMATTER.format(new Date(timestamp * 1000));
  }
}

export function formatInterval(totalSeconds: number): string {
  if (!Number.isFinite(totalSeconds) || totalSeconds <= 0) {
    return '확인 불가';
  }

  const hours = Math.floor(totalSeconds / 3_600);
  const minutes = Math.floor((totalSeconds % 3_600) / 60);

  if (hours > 0) {
    return minutes > 0 ? `${hours}시간 ${minutes}분` : `${hours}시간`;
  }

  return `${minutes}분`;
}

export function getMemoryUsage(memory: RuntimeMemory): {
  used: number;
  percent: number;
} {
  const total = Math.max(0, memory.total);
  const fallbackAvailable = memory.free + memory.buffered + memory.cached;
  const available = Math.min(
    total,
    Math.max(0, memory.available > 0 ? memory.available : fallbackAvailable),
  );
  const used = Math.max(0, total - available);
  const percent = total > 0 ? (used / total) * 100 : 0;

  return { used, percent };
}
