import { createPortal } from 'preact/compat';
import type { JSX } from 'preact';
import { useEffect, useId, useMemo, useRef, useState } from 'preact/hooks';

import { ChevronDownIcon } from './Icons';

export interface CustomSelectOption {
  disabled?: boolean;
  label: string;
  value: string;
}

interface CustomSelectProps {
  ariaLabel: string;
  className?: string;
  disabled?: boolean;
  id?: string;
  onChange: (value: string) => void;
  options: ReadonlyArray<CustomSelectOption>;
  value: string;
  variant?: 'default' | 'emphasized';
}

type MenuPlacement = 'bottom' | 'top';

const MENU_GAP = 8;
const MENU_MAX_HEIGHT = 256;
const VIEWPORT_MARGIN = 8;

function firstEnabledIndex(options: ReadonlyArray<CustomSelectOption>): number {
  return options.findIndex((option) => !option.disabled);
}

function lastEnabledIndex(options: ReadonlyArray<CustomSelectOption>): number {
  for (let index = options.length - 1; index >= 0; index -= 1) {
    if (!options[index]?.disabled) {
      return index;
    }
  }
  return -1;
}

function nextEnabledIndex(
  options: ReadonlyArray<CustomSelectOption>,
  currentIndex: number,
  direction: 1 | -1,
): number {
  if (options.length === 0) {
    return -1;
  }

  let index = currentIndex;
  for (let count = 0; count < options.length; count += 1) {
    index = (index + direction + options.length) % options.length;
    if (!options[index]?.disabled) {
      return index;
    }
  }

  return -1;
}

function selectedOptionIndex(
  options: ReadonlyArray<CustomSelectOption>,
  value: string,
): number {
  const selectedIndex = options.findIndex(
    (option) => option.value === value && !option.disabled,
  );
  return selectedIndex >= 0 ? selectedIndex : firstEnabledIndex(options);
}

export function CustomSelect({
  ariaLabel,
  className = '',
  disabled = false,
  id,
  onChange,
  options,
  value,
  variant = 'default',
}: CustomSelectProps) {
  const generatedId = useId();
  const triggerId = id ?? `ssh-custom-select-${generatedId}`;
  const menuId = `${triggerId}-menu`;
  const rootRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const optionRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const [open, setOpen] = useState(false);
  const [activeIndex, setActiveIndex] = useState(() =>
    selectedOptionIndex(options, value),
  );
  const [placement, setPlacement] = useState<MenuPlacement>('bottom');
  const [menuMaxHeight, setMenuMaxHeight] = useState(MENU_MAX_HEIGHT);
  const [menuStyle, setMenuStyle] = useState<JSX.CSSProperties>({});
  const [portalRoot, setPortalRoot] = useState<Element | DocumentFragment | null>(
    null,
  );

  const selectedOption = useMemo(
    () => options.find((option) => option.value === value) ?? options[0] ?? null,
    [options, value],
  );

  const updateMenuPosition = () => {
    const trigger = triggerRef.current;
    if (!trigger) {
      return;
    }

    const rect = trigger.getBoundingClientRect();
    const estimatedHeight = Math.min(
      MENU_MAX_HEIGHT,
      Math.max(44, options.length * 42 + 12),
    );
    const availableBelow = window.innerHeight - rect.bottom - VIEWPORT_MARGIN;
    const availableAbove = rect.top - VIEWPORT_MARGIN;
    const nextPlacement: MenuPlacement =
      availableBelow < Math.min(estimatedHeight, MENU_MAX_HEIGHT) &&
      availableAbove > availableBelow
        ? 'top'
        : 'bottom';
    const menuWidth = Math.min(
      rect.width,
      Math.max(0, window.innerWidth - VIEWPORT_MARGIN * 2),
    );
    const clampedLeft = Math.max(
      VIEWPORT_MARGIN,
      Math.min(rect.left, window.innerWidth - menuWidth - VIEWPORT_MARGIN),
    );
    const availableSpace =
      nextPlacement === 'bottom' ? availableBelow : availableAbove;

    setPlacement(nextPlacement);
    setMenuMaxHeight(
      Math.max(44, Math.min(MENU_MAX_HEIGHT, Math.floor(availableSpace))),
    );
    setMenuStyle({
      left: `${clampedLeft}px`,
      width: `${menuWidth}px`,
      ...(nextPlacement === 'bottom'
        ? { top: `${rect.bottom + MENU_GAP}px` }
        : { bottom: `${window.innerHeight - rect.top + MENU_GAP}px` }),
    });
  };

  const close = (restoreFocus = false) => {
    setOpen(false);
    if (restoreFocus) {
      window.requestAnimationFrame(() => triggerRef.current?.focus());
    }
  };

  const focusOption = (index: number) => {
    if (index < 0) {
      return;
    }
    setActiveIndex(index);
    window.requestAnimationFrame(() => optionRefs.current[index]?.focus());
  };

  const choose = (index: number) => {
    const option = options[index];
    if (!option || option.disabled) {
      return;
    }
    onChange(option.value);
    setOpen(false);
    window.requestAnimationFrame(() => triggerRef.current?.focus());
  };

  const openFromKeyboard = (preferredIndex?: number) => {
    if (disabled || options.length === 0) {
      return;
    }
    updateMenuPosition();
    setOpen(true);
    focusOption(
      preferredIndex ?? selectedOptionIndex(options, value),
    );
  };

  useEffect(() => {
    const appRoot = rootRef.current?.closest('.ssh-app');
    if (appRoot) {
      setPortalRoot(appRoot);
      return;
    }

    const rootNode = rootRef.current?.getRootNode();
    if (rootNode instanceof ShadowRoot) {
      setPortalRoot(rootNode);
    } else if (typeof document !== 'undefined') {
      setPortalRoot(document.body);
    }
  }, []);

  useEffect(() => {
    setActiveIndex(selectedOptionIndex(options, value));
    optionRefs.current = optionRefs.current.slice(0, options.length);
  }, [options, value]);

  useEffect(() => {
    if (!open) {
      return undefined;
    }

    updateMenuPosition();

    const closeFromOutside = (event: PointerEvent) => {
      const path = event.composedPath();
      if (
        (rootRef.current && path.includes(rootRef.current)) ||
        (menuRef.current && path.includes(menuRef.current))
      ) {
        return;
      }
      close();
    };
    const closeFromEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        close(true);
      }
    };
    const reposition = () => updateMenuPosition();

    document.addEventListener('pointerdown', closeFromOutside);
    document.addEventListener('keydown', closeFromEscape);
    window.addEventListener('resize', reposition);
    window.addEventListener('scroll', reposition, true);
    return () => {
      document.removeEventListener('pointerdown', closeFromOutside);
      document.removeEventListener('keydown', closeFromEscape);
      window.removeEventListener('resize', reposition);
      window.removeEventListener('scroll', reposition, true);
    };
  }, [open, options.length]);

  useEffect(() => {
    if (disabled && open) {
      close();
    }
  }, [disabled, open]);

  const triggerClasses =
    variant === 'emphasized'
      ? 'min-h-11 border-2 border-slate-300 bg-slate-50 px-4 py-2.5 text-sm font-semibold text-slate-950 shadow-inner focus:border-teal-500 focus:bg-white focus:ring-4 focus:ring-teal-100'
      : 'min-h-11 border border-slate-300 bg-slate-50 px-3 py-2.5 text-sm font-bold text-slate-900 focus:border-teal-500 focus:ring-2 focus:ring-teal-100';

  const menu = open ? (
    <div
      aria-label={`${ariaLabel} 목록`}
      class="ssh-custom-select-menu fixed z-[1000] overflow-hidden rounded-xl border border-slate-200 bg-white p-1.5 shadow-xl shadow-slate-950/10"
      id={menuId}
      ref={menuRef}
      role="listbox"
      style={menuStyle}
    >
      <div class="overflow-y-auto overscroll-contain" style={{ maxHeight: `${menuMaxHeight}px` }}>
        {options.map((option, index) => {
          const active = option.value === value;
          return (
            <button
              aria-selected={active}
              class={`flex min-h-10 w-full items-center justify-between gap-3 rounded-lg px-3 py-2.5 text-left text-sm font-bold transition ${
                active
                  ? 'bg-teal-50 text-teal-800'
                  : 'text-slate-700 hover:bg-slate-50'
              } ${option.disabled ? 'cursor-not-allowed opacity-50' : ''}`}
              disabled={option.disabled}
              key={option.value}
              onClick={() => choose(index)}
              onFocus={() => setActiveIndex(index)}
              onKeyDown={(event) => {
                switch (event.key) {
                  case 'ArrowDown':
                    event.preventDefault();
                    focusOption(nextEnabledIndex(options, index, 1));
                    break;
                  case 'ArrowUp':
                    event.preventDefault();
                    focusOption(nextEnabledIndex(options, index, -1));
                    break;
                  case 'Home':
                    event.preventDefault();
                    focusOption(firstEnabledIndex(options));
                    break;
                  case 'End':
                    event.preventDefault();
                    focusOption(lastEnabledIndex(options));
                    break;
                  case 'Enter':
                  case ' ':
                    event.preventDefault();
                    choose(index);
                    break;
                  case 'Escape':
                    event.preventDefault();
                    close(true);
                    break;
                  case 'Tab':
                    setOpen(false);
                    break;
                  default:
                    break;
                }
              }}
              ref={(element) => {
                optionRefs.current[index] = element;
              }}
              role="option"
              tabIndex={activeIndex === index ? 0 : -1}
              type="button"
            >
              <span class="min-w-0 truncate">{option.label}</span>
              {active ? (
                <span
                  aria-hidden="true"
                  class="size-2 shrink-0 rounded-full bg-teal-500"
                />
              ) : null}
            </button>
          );
        })}
      </div>
    </div>
  ) : null;

  return (
    <div class={`relative ${className}`} ref={rootRef}>
      <button
        aria-controls={menuId}
        aria-expanded={open}
        aria-haspopup="listbox"
        aria-label={ariaLabel}
        class={`ssh-custom-select-trigger flex w-full cursor-pointer items-center justify-between gap-3 rounded-xl text-left outline-none transition disabled:cursor-not-allowed disabled:bg-slate-100 disabled:text-slate-400 disabled:opacity-60 ${triggerClasses}`}
        disabled={disabled}
        id={triggerId}
        onClick={() => {
          if (open) {
            close();
            return;
          }
          updateMenuPosition();
          setOpen(true);
        }}
        onKeyDown={(event) => {
          switch (event.key) {
            case 'ArrowDown':
              event.preventDefault();
              openFromKeyboard(
                open
                  ? nextEnabledIndex(options, activeIndex, 1)
                  : selectedOptionIndex(options, value),
              );
              break;
            case 'ArrowUp':
              event.preventDefault();
              openFromKeyboard(
                open
                  ? nextEnabledIndex(options, activeIndex, -1)
                  : selectedOptionIndex(options, value),
              );
              break;
            case 'Home':
              event.preventDefault();
              openFromKeyboard(firstEnabledIndex(options));
              break;
            case 'End':
              event.preventDefault();
              openFromKeyboard(lastEnabledIndex(options));
              break;
            case 'Enter':
            case ' ':
              event.preventDefault();
              if (open) {
                close();
              } else {
                openFromKeyboard();
              }
              break;
            case 'Escape':
              if (open) {
                event.preventDefault();
                close();
              }
              break;
            default:
              break;
          }
        }}
        ref={triggerRef}
        type="button"
      >
        <span class="min-w-0 truncate">{selectedOption?.label ?? '선택하세요'}</span>
        <ChevronDownIcon
          aria-hidden="true"
          class={`size-4 shrink-0 text-slate-400 transition-transform ${
            open ? 'rotate-180' : ''
          }`}
        />
      </button>
      {menu && portalRoot ? createPortal(menu, portalRoot) : null}
      <span class="sr-only" aria-live="polite">
        {placement === 'top' ? '선택 목록이 위쪽에 열렸습니다.' : ''}
      </span>
    </div>
  );
}
