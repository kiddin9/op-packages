import type { RecommendedRuleAssignment, RecommendedRulesStatus } from '../types/rules';

export function filterRuleGroups(
  rules: readonly string[],
  query: string,
  splitOwnership: boolean,
  recommendedDomainSet: ReadonlySet<string>,
): { filteredRules: readonly string[]; manualRules: readonly string[]; managedRules: readonly string[] } {
  const filteredRules = query ? rules.filter((domain) => domain.includes(query)) : rules;
  if (!splitOwnership) return { filteredRules, manualRules: filteredRules, managedRules: [] };

  const manualRules: string[] = [];
  const managedRules: string[] = [];
  for (const domain of filteredRules) {
    (recommendedDomainSet.has(domain) ? managedRules : manualRules).push(domain);
  }
  return { filteredRules, manualRules, managedRules };
}

export function filterRecommendedAssignments(
  rules: readonly RecommendedRuleAssignment[],
  query: string,
): readonly RecommendedRuleAssignment[] {
  if (!query) return rules;
  return rules.filter((rule) =>
    rule.title.toLowerCase().includes(query) ||
    rule.domains.some((domain) => domain.includes(query)),
  );
}

function sameStrings(left: readonly string[], right: readonly string[]): boolean {
  return left === right || (left.length === right.length && left.every((value, index) => value === right[index]));
}

function sameAssignments(
  left: readonly RecommendedRuleAssignment[],
  right: readonly RecommendedRuleAssignment[],
): boolean {
  return left === right || (left.length === right.length && left.every((rule, index) => {
    const other = right[index];
    return other !== undefined && rule.id === other.id && rule.title === other.title &&
      sameStrings(rule.domains, other.domains);
  }));
}

// Preserve only the arrays that feed the expensive rule cards. Other status
// fields (including stage and timestamps) must always be allowed to update.
export function sameRecommendationContent(
  previous: RecommendedRulesStatus,
  next: RecommendedRulesStatus,
): Pick<RecommendedRulesStatus, 'domains' | 'rules'> {
  return {
    domains: sameStrings(previous.domains, next.domains) ? previous.domains : next.domains,
    rules: sameAssignments(previous.rules, next.rules) ? previous.rules : next.rules,
  };
}
