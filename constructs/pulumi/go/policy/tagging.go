// Package policy provides the organization's required resource tagging rules.
// Components call RequiredTags automatically — developers never call it directly.
package policy

// RequiredTags returns the mandatory tag map for all Azure resources.
// Required tags always win over keys in extra.
func RequiredTags(project, environment string, extra map[string]string) map[string]string {
	tags := map[string]string{
		"managed_by":  "pulumi",
		"project":     project,
		"environment": environment,
	}
	for k, v := range extra {
		if _, reserved := tags[k]; !reserved {
			tags[k] = v
		}
	}
	return tags
}
