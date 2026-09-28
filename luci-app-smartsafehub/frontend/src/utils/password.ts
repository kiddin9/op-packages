export interface PasswordPolicy {
  length: boolean;
  letter: boolean;
  number: boolean;
}

export function passwordPolicy(password: string): PasswordPolicy {
  return {
    length: password.length >= 8,
    letter: /[A-Za-z]/.test(password),
    number: /[0-9]/.test(password),
  };
}

export function passwordPolicySatisfied(policy: PasswordPolicy): boolean {
  return policy.length && policy.letter && policy.number;
}
