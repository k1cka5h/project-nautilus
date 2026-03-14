# Nautilus — OPA Policy Enforcement

These [OPA](https://www.openpolicyagent.org/) policies are run by
[conftest](https://www.conftest.dev/) against the `terraform show -json` plan
output **before `terraform apply` runs**. A policy violation fails the pipeline
and posts the reason to the PR.

Policies complement the Azure Policy definitions in `tf-modules/governance/`.
Azure Policy is the hard stop at the cloud level; these policies are the
earlier, developer-friendly signal in the PR.

## Policies

| File | Rule | Environments |
|------|------|--------------|
| `deny_public_resources.rego` | No public IPs, no `public_network_access_enabled = true`, no public blob storage | All |
| `deny_network_outside_dev.rego` | No network resource creation (VNets, NSGs, subnets, DNS zones, private endpoints) | staging, prod |
| `deny_permission_changes_outside_dev.rego` | No role assignments, role definitions, or managed identity creation/modification | staging, prod |
| `deny_deletions_outside_dev.rego` | No resource deletions or replacements | staging, prod |
| `deny_budget_violations.rego` | VM and PostgreSQL SKUs must be on the approved allowlist for the environment | All |

## How it works

The pipeline runs after `terraform plan`:

```yaml
- name: Export plan JSON
  run: terraform show -json tfplan > tfplan.json

- name: Check policies
  run: |
    conftest test tfplan.json \
      --policy policy/ \
      --data <(printf '{"environment":"%s"}' "$ENVIRONMENT") \
      --output github
```

The `--data` flag injects the current environment so policies can distinguish
dev from staging/prod. The `--output github` flag formats violations as GitHub
annotations on the PR diff.

## Adding a new policy

1. Create a new `.rego` file in this directory.
2. Use `package nautilus.<policy_name>`.
3. Define `deny[msg]` rules — each violation produces one message.
4. Access the environment via `data.environment`.
5. Access the Terraform plan via `input.resource_changes`.
6. Test locally: `conftest test tfplan.json --policy policy/ --data env.json`

Where `env.json` is `{"environment": "prod"}` for a staging/prod test.

## Updating the SKU allowlist

The SKU allowlist in `deny_budget_violations.rego` is the canonical source of
approved compute tiers per environment. To add a SKU:

1. Get platform team approval (Jira board).
2. Add it to the appropriate environment's set in `deny_budget_violations.rego`.
3. Open a PR — the change is reviewed like any other policy change.

## Relationship to Azure Policy

| Layer | Where enforced | When caught |
|-------|---------------|-------------|
| OPA/conftest (this folder) | CI/CD pipeline | Before apply — developer sees it in the PR |
| Azure Policy (`tf-modules/governance/`) | Azure ARM API | At apply time — hard deny from Azure |
| Management locks (in each TF module) | Azure ARM API | Prevents deletion even if locks are bypassed |

All three layers are intentional. OPA gives fast feedback; Azure Policy and
management locks provide defence-in-depth if the pipeline is bypassed.
