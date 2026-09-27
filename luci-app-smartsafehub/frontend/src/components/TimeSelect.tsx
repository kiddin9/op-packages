import { CustomSelect } from './CustomSelect';

interface TimeSelectProps {
  ariaLabel: string;
  className?: string;
  disabled?: boolean;
  id: string;
  onChange: (value: string) => void;
  value: string;
  variant?: 'default' | 'emphasized';
}

const HOUR_OPTIONS = Array.from({ length: 24 }, (_, hour) => {
  const value = String(hour).padStart(2, '0');
  return { value, label: `${value}시` };
});

const MINUTE_OPTIONS = Array.from({ length: 60 }, (_, minute) => {
  const value = String(minute).padStart(2, '0');
  return { value, label: `${value}분` };
});

function splitTime(value: string): { hour: string; minute: string } {
  const match = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(value);
  return {
    hour: match?.[1] ?? '03',
    minute: match?.[2] ?? '00',
  };
}

export function TimeSelect({
  ariaLabel,
  className = '',
  disabled = false,
  id,
  onChange,
  value,
  variant = 'default',
}: TimeSelectProps) {
  const { hour, minute } = splitTime(value);

  const update = (nextHour: string, nextMinute: string) => {
    onChange(`${nextHour}:${nextMinute}`);
  };

  return (
    <div
      aria-label={ariaLabel}
      class={`ssh-time-select ${className}`.trim()}
      data-time-select={id}
      role="group"
    >
      <CustomSelect
        ariaLabel={`${ariaLabel} 시`}
        disabled={disabled}
        id={`${id}-hour`}
        onChange={(nextHour) => update(nextHour, minute)}
        options={HOUR_OPTIONS}
        value={hour}
        variant={variant}
      />
      <CustomSelect
        ariaLabel={`${ariaLabel} 분`}
        disabled={disabled}
        id={`${id}-minute`}
        onChange={(nextMinute) => update(hour, nextMinute)}
        options={MINUTE_OPTIONS}
        value={minute}
        variant={variant}
      />
    </div>
  );
}
