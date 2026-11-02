/** Only an explicit Hub first-party value may receive SmartSafeHub branding. */
export function isFirstPartyPublisher(type: unknown): boolean {
  return type === 'first_party';
}
