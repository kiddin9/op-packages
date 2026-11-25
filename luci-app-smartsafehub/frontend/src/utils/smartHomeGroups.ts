// SPDX-License-Identifier: GPL-3.0-or-later
import type { JarbisDevice } from '../types/jarbis';

// Closed set of room IDs, shared with the Jarbis UCI/RPC contract.
export const HOME_ROOMS = [
  { id: 'unassigned', label: '공간 미지정' },
  { id: 'living', label: '거실' },
  { id: 'bedroom', label: '침실' },
  { id: 'study', label: '서재' },
  { id: 'kitchen', label: '주방' },
  { id: 'other', label: '기타' },
] as const;

export type HomeRoom = typeof HOME_ROOMS[number]['id'];

export function normalizeHomeRoom(room: string | undefined): HomeRoom {
  return HOME_ROOMS.find(item => item.id === room)?.id ?? 'unassigned';
}

export function homeRoomLabel(room: string | undefined): string {
  return HOME_ROOMS.find(item => item.id === normalizeHomeRoom(room))!.label;
}

export function groupHomeDevices<T extends Pick<JarbisDevice, 'room'>>(devices: T[]): { room: HomeRoom; label: string; devices: T[] }[] {
  return HOME_ROOMS.flatMap(item => {
    const members = devices.filter(device => normalizeHomeRoom(device.room) === item.id);
    return members.length ? [{ room: item.id, label: item.label, devices: members }] : [];
  });
}

// Round-robin through ALL registered IDs; never drop IDs after a fixed prefix.
// The caller chooses a batch size that bounds each RPC burst on low-memory routers.
export function nextHomePollBatch(ids: string[], cursor: number, limit: number): { ids: string[]; nextCursor: number } {
  if (!ids.length || !Number.isInteger(limit) || limit < 1) return { ids: [], nextCursor: 0 };
  const start = Number.isFinite(cursor) ? Math.max(0, Math.floor(cursor)) % ids.length : 0;
  const count = Math.min(ids.length, limit);
  return {
    ids: Array.from({ length: count }, (_, offset) => ids[(start + offset) % ids.length]!),
    nextCursor: (start + count) % ids.length,
  };
}
