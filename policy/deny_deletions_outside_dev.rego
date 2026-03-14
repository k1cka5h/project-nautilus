package nautilus.deny_deletions_outside_dev

import future.keywords.in

# Resource types that can never be deleted outside dev via Terraform.
# Management locks in the modules enforce this at the cloud level too,
# but this policy catches it earlier — before terraform apply runs.
#
# "replace" (destroy + create) counts as a deletion and is also blocked.
# A replace is indicated by actions == ["delete", "create"] or ["create", "delete"].

environment := data.environment

is_destroying(actions) {
  "delete" in actions
}

deny[msg] {
  environment != "dev"

  change := input.resource_changes[_]
  is_destroying(change.change.actions)

  msg := sprintf(
    "DENY [deletions-outside-dev] %s: destroying resources in '%s' is not permitted via automated pipelines. To decommission a resource in staging/prod, open a #platform-infra ticket for a supervised removal.",
    [change.address, environment],
  )
}
