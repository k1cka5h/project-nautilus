/**
 * Required tagging policy.
 * Injects mandatory tags onto every Azure resource.
 * Developers never call this directly — constructs call it automatically.
 */
export function requiredTags(
  project: string,
  environment: string,
  extra: Record<string, string> = {},
): Record<string, string> {
  return {
    ...extra,
    managed_by:  "terraform",
    project,
    environment,
  };
}
