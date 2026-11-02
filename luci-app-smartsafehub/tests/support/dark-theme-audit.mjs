// SPDX-License-Identifier: GPL-3.0-or-later
// Source-only dark theme contract: no browser, Tailwind compiler or build artifacts.
// It detects complete static Tailwind utilities, including those assembled in
// string/template expressions. Dynamically constructed names are out of scope.

const CLASS = /(?<![\w./:-])(?<variants>(?:[a-z][a-z-]*:)*)((?<utility>(?:divide|bg|border|ring|text)-(?:[a-z]+-(?:50|100|200|300|400|500|600|700|800|900|950)(?:\/\d{1,3})?|white(?:\/\d{1,3})?)))(?![\w./-])/g;
const DARK = ".ssh-app[data-theme='dark']";
const PALE = new Set(['50', '100', '200', '300']);

function category(utility) {
  const match = /^(divide|bg|border|ring|text)-([a-z]+)(?:-(\d+))?(?:\/\d+)?$/.exec(utility);
  if (!match) return null;
  const [, family, color, shade] = match;
  if (family === 'divide' && shade && Number(shade) <= 400) return 'border-color';
  if (family === 'bg' && (color === 'white' || PALE.has(shade))) return 'background-color';
  if (family === 'border' && (color === 'white' || PALE.has(shade))) return 'border-color';
  if (family === 'ring' && (color === 'white' || PALE.has(shade))) return '--tw-ring-color';
  // Dark-mode text contrasts need an explicit mapping for strong dark text.
  if (family === 'text' && shade && Number(shade) >= 700) return 'color';
  return null;
}

export function collectColorUtilities(sources) {
  const found = new Map();
  for (const [filename, source] of Object.entries(sources)) {
    for (const match of source.matchAll(CLASS)) {
      const utility = match.groups.utility;
      const declaration = category(utility);
      if (!declaration) continue;
      const variants = match.groups.variants.replace(/:$/, '');
      const key = variants ? `${variants}:${utility}` : utility;
      if (!found.has(key)) found.set(key, { key, utility, variants, declaration, files: new Set() });
      found.get(key).files.add(filename);
    }
  }
  return found;
}

function cssRules(css) {
  // Split grouped selectors *before* matching them. Otherwise an unrelated
  // selector in the same rule could falsely satisfy a requested utility.
  const withoutComments = css.replace(/\/\*[\s\S]*?\*\//g, '');
  return [...withoutComments.matchAll(/([^{}]+)\{([^{}]*)\}/g)].flatMap(([, selectors, block]) => {
    const declarations = new Map();
    for (const [, name, value] of block.matchAll(/(--[\w-]+|[\w-]+)\s*:\s*([^;]+);/g)) {
      declarations.set(name, value.trim());
    }
    return selectors.split(',').map((selector) => ({ selector: selector.trim(), declarations }));
  });
}

function contrastSafe(value, property) {
  // Text in a dark surface must be visibly brighter; pale surfaces/rings
  // must remain dark. These are coarse luminance guards, not WCAG checks.
  const hex = /^#([\da-f]{3}|[\da-f]{6})$/i.exec(value);
  const rgb = /^rgba?\(\s*(\d+)\s*[ ,]\s*(\d+)\s*[ ,]\s*(\d+)(?:\s*\/\s*(0?\.\d+|1(?:\.0+)?)|\s*,\s*(0?\.\d+|1(?:\.0+)?))?\s*\)$/i.exec(value);
  let channels, alpha = 1;
  if (hex) {
    const v = hex[1].length === 3 ? [...hex[1]].map(x => x + x).join('') : hex[1];
    channels = [0, 2, 4].map(i => parseInt(v.slice(i, i + 2), 16));
  } else if (rgb) {
    channels = [Number(rgb[1]), Number(rgb[2]), Number(rgb[3])];
    alpha = Number(rgb[4] ?? rgb[5] ?? 1);
  } else {
    return false; // Unresolvable values must be explicitly reviewed.
  }
  if (channels.some(c => c > 255) || alpha < 0 || alpha > 1) return false;
  // Composite translucent colors over the actual dark card background.
  const mixed = channels.map((x, i) => x * alpha + [15, 23, 42][i] * (1 - alpha));
  const srgb = mixed.map(v => {
    const c = v / 255;
    return c <= .04045 ? c / 12.92 : ((c + .055) / 1.055) ** 2.4;
  });
  const luminance = srgb[0] * .2126 + srgb[1] * .7152 + srgb[2] * .0722;
  return property === 'color' ? luminance >= .28 : luminance < .40;
}

function selectorFor(entry) {
  if (!entry.variants) return `[class~='${entry.utility}']`;
  const variants = entry.variants.split(':');
  if (variants.length !== 1 || !['hover', 'focus', 'focus-visible', 'disabled'].includes(variants[0])) return null;
  const state = variants[0];
  const className = `${state}\\:${entry.utility.replaceAll('/', '\\/')}`;
  return `.${className}:${state}`;
}

function hasOverride(entry, rules) {
  const target = selectorFor(entry);
  if (!target) return false;
  return rules.some(({ selector, declarations }) => {
    if (!selector.startsWith(DARK) || !selector.includes(target)) return false;
    // Tailwind v4 divide-* colors apply to list children. Parent rules do not work.
    if (entry.utility.startsWith('divide-') && !selector.includes(`${target} > :not(:last-child)`)) return false;
    const value = declarations.get(entry.declaration);
    return value !== undefined && contrastSafe(value, entry.declaration);
  });
}

export function auditDarkTheme({ sources, css, exceptions = [] }) {
  const found = collectColorUtilities(sources);
  const rules = cssRules(css);
  const ignored = new Set();
  const problems = [];
  for (const exception of exceptions) {
    if (!exception || typeof exception.file !== 'string' || !/^[\w./-]+\.tsx$/.test(exception.file) ||
        exception.file.includes('..') || typeof exception.utility !== 'string' || !exception.utility ||
        typeof exception.reason !== 'string' || exception.reason.trim().length < 20 ||
        Object.keys(exception).some(key => !['file', 'utility', 'reason'].includes(key))) {
      problems.push('예외에는 특정 TSX 파일, 정확한 utility와 20자 이상의 사유가 필요합니다.');
      continue;
    }
    const token = `${exception.file}::${exception.utility}`;
    if (ignored.has(token)) problems.push(`중복 다크 모드 예외: ${token}`);
    else if (!found.get(exception.utility)?.files.has(exception.file)) problems.push(`사용하지 않는 다크 모드 예외: ${token}`);
    else ignored.add(token);
  }
  for (const entry of found.values()) {
    if (hasOverride(entry, rules)) continue;
    for (const filename of [...entry.files].sort()) {
      if (ignored.has(`${filename}::${entry.key}`)) continue;
      problems.push(`${filename}: ${entry.key} 다크 모드 대응 누락 또는 밝은 색상 유지 (예외 등록 시 사유 필수)`);
    }
  }
  return { problems, checked: found.size, exceptions: ignored.size };
}
