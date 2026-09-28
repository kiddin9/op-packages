interface Ipv4OctetInputProps {
  disabled?: boolean;
  label: string;
  value: string;
  onChange: (value: string) => void;
}

export function splitIpv4(value: string): [string, string, string, string] {
  const parts = value.split('.');
  return [parts[0] ?? '', parts[1] ?? '', parts[2] ?? '', parts[3] ?? ''];
}

export function normalizeIpv4Octet(value: string): string {
  return value.replace(/\D/g, '').slice(0, 3);
}

function joinIpv4Octets(octets: [string, string, string, string]): string {
  return octets.every((octet) => octet === '') ? '' : octets.join('.');
}

export function Ipv4OctetInput({
  disabled = false,
  label,
  value,
  onChange,
}: Ipv4OctetInputProps) {
  const octets = splitIpv4(value);

  const updateOctet = (index: number, nextValue: string) => {
    const next = [...octets] as [string, string, string, string];
    next[index] = normalizeIpv4Octet(nextValue);
    onChange(joinIpv4Octets(next));
  };

  return (
    <div class="ssh-ipv4-segments mt-2 min-h-11" aria-label={`${label} 입력`}>
      {octets.map((octet, index) => (
        <div class="ssh-ipv4-segment" key={index}>
          <input
            aria-label={`${label} ${index + 1}번째 옥텟`}
            autocomplete="off"
            class="min-h-11 w-full min-w-0 max-w-full rounded-xl border-2 border-slate-300 bg-slate-50 px-1.5 py-2.5 text-center text-sm font-semibold text-slate-950 shadow-inner outline-none transition focus:border-teal-500 focus:bg-white focus:ring-4 focus:ring-teal-100 disabled:cursor-not-allowed disabled:bg-slate-100 sm:px-2"
            disabled={disabled}
            inputMode="numeric"
            maxLength={3}
            onInput={(event) => updateOctet(index, event.currentTarget.value)}
            pattern="[0-9]*"
            spellcheck={false}
            value={octet}
          />
          {index < octets.length - 1 ? (
            <span aria-hidden="true" class="ssh-ipv4-separator text-sm font-black text-slate-400">
              .
            </span>
          ) : null}
        </div>
      ))}
    </div>
  );
}
