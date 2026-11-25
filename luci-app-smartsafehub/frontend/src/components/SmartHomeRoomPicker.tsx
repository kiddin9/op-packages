// SPDX-License-Identifier: GPL-3.0-or-later
import { CustomSelect } from './CustomSelect';
import { HOME_ROOMS, normalizeHomeRoom, type HomeRoom } from '../utils/smartHomeGroups';

const ROOM_OPTIONS = HOME_ROOMS.map(option => ({ value: option.id, label: option.label }));

interface Props {
  room: string | undefined;
  supported: boolean;
  disabled: boolean;
  onChange: (room: HomeRoom) => void;
}

export function SmartHomeRoomPicker({ room, supported, disabled, onChange }: Props) {
  if (!supported) return null;
  return <div class="ssh-home-room-picker">
    <span>공간</span>
    <CustomSelect
      ariaLabel="기기 공간 변경"
      disabled={disabled}
      onChange={value => onChange(value as HomeRoom)}
      options={ROOM_OPTIONS}
      value={normalizeHomeRoom(room)}
    />
  </div>;
}
