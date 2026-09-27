import type { ComponentChildren } from 'preact';

interface StatusCardProps {
  eyebrow: string;
  title: string;
  description: string;
  icon: ComponentChildren;
  badge?: ComponentChildren;
  progress?: number;
}

export function StatusCard({
  eyebrow,
  title,
  description,
  icon,
  badge,
  progress,
}: StatusCardProps) {
  return (
    <article class="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-900/5 sm:p-5">
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <p class="m-0 text-xs font-bold uppercase tracking-[0.16em] text-slate-500">
            {eyebrow}
          </p>
          <h2 class="mt-3 mb-0 break-words text-lg font-extrabold tracking-tight text-slate-950 sm:text-xl">
            {title}
          </h2>
        </div>
        <span class="grid size-11 shrink-0 place-items-center rounded-xl bg-teal-50 text-teal-700">
          {icon}
        </span>
      </div>

      <p class="mt-3 mb-0 text-sm leading-5 text-slate-600 sm:min-h-10">
        {description}
      </p>

      {typeof progress === 'number' ? (
        <div class="mt-4" aria-label={`사용률 ${Math.round(progress)}%`}>
          <div class="h-2 overflow-hidden rounded-full bg-slate-100">
            <div
              class="h-full rounded-full bg-teal-600 transition-[width] duration-300"
              style={{ width: `${Math.min(100, Math.max(0, progress))}%` }}
            />
          </div>
        </div>
      ) : null}

      {badge ? <div class="mt-4">{badge}</div> : null}
    </article>
  );
}
