import type { ComponentChildren } from 'preact';

interface SectionHeadingProps {
  action?: ComponentChildren;
  description: string;
  eyebrow: string;
  id?: string;
  title: string;
}

/** Section context is outside the content card; controls stay with their functional card. */
export function SectionHeading({ action, description, eyebrow, id, title }: SectionHeadingProps) {
  return (
    <div class="ssh-section-heading mb-4 min-w-0">
      <div class={action ? 'grid min-w-0 items-start gap-x-4 gap-y-3 sm:grid-cols-[minmax(0,1fr)_auto]' : ''}>
        {/* Keep the three heading lines together so a tall action cannot stretch their spacing. */}
        <div class="min-w-0">
          <p class="m-0 text-[0.68rem] font-black uppercase tracking-[0.18em] text-teal-700">{eyebrow}</p>
          <h2 class="mt-2 mb-0 min-w-0 text-xl font-black tracking-tight text-slate-950" id={id}>{title}</h2>
          <p class="mt-2 mb-0 text-sm leading-6 text-slate-500">{description}</p>
        </div>
        {action ? <div class="min-w-0 justify-self-start sm:mt-3 sm:justify-self-end">{action}</div> : null}
      </div>
    </div>
  );
}
