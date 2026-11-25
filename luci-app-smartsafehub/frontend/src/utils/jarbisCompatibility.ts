// SPDX-License-Identifier: GPL-3.0-or-later
import type { JarbisStatus } from '../types/jarbis';

// SmartSafeHub's production compatibility baseline. An APK such as
// 0.2.4-r1 satisfies 0.2.4, but feature flags are still validated because
// beta/stable builds may differ or a package may be incomplete.
export const JARBIS_FULL_FEATURE_VERSION = '0.2.4';
export const JARBIS_REQUIREMENTS = [
  { key: 'shellyHtg3', label: '온습도 센서 측정값', minimum: JARBIS_FULL_FEATURE_VERSION },
  { key: 'shellyQuickPair', label: '온습도 센서 자동 연결', minimum: JARBIS_FULL_FEATURE_VERSION },
  { key: 'rooms', label: '공간별 기기 관리', minimum: JARBIS_FULL_FEATURE_VERSION },
] as const;

type FeatureKey = typeof JARBIS_REQUIREMENTS[number]['key'];
export type JarbisFeatureIssue = { key: FeatureKey; label: string; minimum: string; reason: 'version' | 'capability' | 'unknown' };

/** Returns null for unrecognized versions, never treating them as old or new. */
export function compareJarbisVersions(a: string, b: string): number | null {
  const parse = (value: string): number[] | null => {
    const match = /^(\d+)\.(\d+)\.(\d+)(?:-r(\d+))?$/.exec(value.trim());
    return match ? match.slice(1).map(part => Number(part || 0)) : null;
  };
  const left = parse(a);
  const right = parse(b);
  if (!left || !right || left.some(n => !Number.isSafeInteger(n)) || right.some(n => !Number.isSafeInteger(n))) return null;
  for (let i = 0; i < left.length; i += 1) {
    if (left[i]! > right[i]!) return 1;
    if (left[i]! < right[i]!) return -1;
  }
  return 0;
}

export function assessJarbisCompatibility(status: JarbisStatus | null): {
  issues: JarbisFeatureIssue[];
  needsUpgrade: boolean;
  needsAttention: boolean;
} {
  if (!status) return { issues: [], needsUpgrade: false, needsAttention: false };
  const issues: JarbisFeatureIssue[] = [];
  for (const requirement of JARBIS_REQUIREMENTS) {
    const order = compareJarbisVersions(status.version, requirement.minimum);
    const supported = status.features?.[requirement.key] === true;
    // An old version must not be mistaken for compatible even if a capability
    // flag is accidentally present (e.g. backports or partial installations).
    if (order !== null && order < 0) {
      issues.push({ ...requirement, reason: 'version' });
    } else if (!supported) {
      issues.push({ ...requirement, reason: order === null ? 'unknown' : 'capability' });
    }
  }
  return {
    issues,
    needsUpgrade: issues.some(issue => issue.reason === 'version'),
    needsAttention: issues.length > 0,
  };
}
