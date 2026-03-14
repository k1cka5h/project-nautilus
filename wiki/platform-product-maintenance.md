# Platform Guide — Product Team Maintenance

This guide covers the platform team's responsibilities for product teams that use
Nautilus: reviewing their CDKTF stacks, managing state, handling incidents, and
onboarding new teams.

---

## What the platform team owns

When a product team adopts Nautilus, the platform team is responsible for:

| Responsibility | Details |
|----------------|---------|
| CI/CD pipeline template | `infra.yml` — the team copies it, the platform team maintains it |
| Remote state backend | Blob Storage account, container, and RBAC |
| Azure provider credentials | Service principal per product, least-privilege scoped |
| Module access | Deploy key provisioning (`TF_MODULES_DEPLOY_KEY`) |
| Production approval gate | Required reviewer on GitHub `production` Environment |
| OPA/conftest policies | `policy/` rules that gate every `terraform apply` |
| Azure Policy governance | Policy definitions and assignments across all subscriptions |
| Management lock removal | Supervised decommissions of protected resources |
| Incident response | Failed applies, state corruption, unexpected drift |
| Module upgrades | Coordinating breaking changes across all consuming repos |

The product team owns their stack file, their package version pin, and their
application-level configuration.

---

## Reviewing a product team's CDKTF stack PR

The platform team is a required reviewer for all PRs that touch infrastructure
in production environments. When reviewing:

### Structural checks

- [ ] Stack inherits from `BaseAzureStack` (not `TerraformStack` directly).
- [ ] `project` and `environment` are passed correctly to `super().__init__()`.
- [ ] No hardcoded secrets — passwords and tokens must come from `os.environ`.
- [ ] No raw `TerraformModule` or `TerraformResource` calls — only approved constructs.
- [ ] Stack outputs are descriptive and don't expose sensitive values as plaintext.

### Plan review

The pipeline posts a Terraform plan as a PR comment. Read it carefully:

```
# azurerm_kubernetes_cluster.this will be created
  + resource ...

# azurerm_postgresql_flexible_server.this must be replaced
-/+ resource ...   ← THIS IS DESTRUCTIVE — query the developer before approving
```

Red flags in a plan:

| Signal | Action |
|--------|--------|
| `-/+` (destroy and recreate) on a stateful resource (DB, cluster) | Block and discuss with the team |
| Unexpected new resources not mentioned in the PR description | Ask the developer to explain |
| Changes to `administrator_password` on an existing server | Confirm this is intentional rotation |
| `project` or `environment` values changed | Block — these are in resource names; changing them destroys everything |
| `?ref=` tag in module source doesn't match the declared construct library version | Block — version mismatch means undefined behaviour |

Note: the OPA policy gate runs automatically in the pipeline before this plan is
posted. By the time you see the plan, it has already passed the automated policy
checks. Your review focuses on intent and correctness, not policy compliance.

### Approving

If the plan looks correct, approve in GitHub. The production Environment gate
will still require a separate manual approval before apply runs.

---

## Handling policy violations

### A developer's PR is blocked by the OPA policy gate

The pipeline annotates the specific violation on the PR diff. Direct the developer
to the [developer guide troubleshooting section](developer-guide.md#troubleshooting).
Common patterns:

- **`DENY [deletions-outside-dev]`**: If the deletion is intentional (decommission),
  follow the [supervised decommission](#supervised-decommission-in-stagingprod) process below.
- **`DENY [network-outside-dev]`** or **`DENY [permissions-outside-dev]`**: The developer
  needs to remove the offending resource from their stack. If they have a legitimate need,
  open a Jira ticket and the platform team handles it through a privileged pipeline.
- **`DENY [budget]`**: The developer needs a different SKU, or they need to submit a
  Jira ticket to get a new SKU approved and added to `policy/deny_budget_violations.rego`.

### An apply fails with an Azure Policy denial

This means the OPA gate was bypassed (e.g. someone ran `terraform apply` manually
outside the pipeline) or there's a gap in the OPA policies. In either case:

1. Identify the resource type and property that triggered the Azure Policy denial from the error message.
2. If it's a pipeline bypass: investigate how and remediate access.
3. If it's an OPA gap: add the missing rule to the relevant `.rego` file in `policy/` and open a PR.

---

## Supervised decommission in staging/prod

Deleting resources in staging or prod requires three steps because management locks
protect all non-dev resources from accidental destruction.

**Step 1 — Remove the management lock** (platform team only):

```bash
# Find the lock
az lock list --resource-group <rg-name> --output table

# Remove it
az lock delete --name <lock-name> --resource-group <rg-name>
```

**Step 2 — Remove the resource from the stack and merge**:

The developer removes the resource from their stack file. The PR will now pass the
deletion policy (since the lock removal is a deliberate act documented in the Jira
ticket). Approve and apply.

**Step 3 — Confirm and document**:

After apply succeeds, confirm the resource is gone and close the Jira ticket with
the apply job URL as evidence. The management lock does not need to be re-created
(the resource no longer exists).

---

## Understanding the synthesized output

When debugging a pipeline failure, you may need to inspect the synthesized
Terraform JSON. Download the `cdktf-out-<sha>` artifact from the failed workflow run.

```
cdktf.out/
└── stacks/
    └── portal-stack/
        ├── cdk.tf.json          Main Terraform configuration
        └── .terraform.lock.hcl  Provider lock file (generated by init)
```

`cdk.tf.json` contains the full Terraform configuration. You can inspect module
calls, variable values, and backend configuration:

```bash
# Pretty-print the module section
cat cdktf.out/stacks/portal-stack/cdk.tf.json | jq '.module'
```

To reproduce locally (requires Azure credentials and SSH key for modules):

```bash
cd cdktf.out/stacks/portal-stack
eval $(ssh-agent)
ssh-add /path/to/tf_modules_deploy_key
terraform init
terraform plan
```

---

## Managing remote state

State files live in the platform-managed Blob Storage account:

```
Storage account: platformtfstate
Container:       tfstate
Blobs:
  portal/dev/terraform.tfstate
  portal/staging/terraform.tfstate
  portal/prod/terraform.tfstate
  myapp/dev/terraform.tfstate
  ...
```

The state key is set by `BaseAzureStack` and cannot be changed by developers:

```python
key=f"{project}/{environment}/terraform.tfstate"
```

### Viewing state

```bash
# Must have Storage Blob Data Contributor on the platformtfstate account
az storage blob download \
  --account-name platformtfstate \
  --container-name tfstate \
  --name portal/prod/terraform.tfstate \
  --file portal-prod.tfstate

terraform show -json portal-prod.tfstate | jq '.values.root_module'
```

### State lock

Terraform uses blob lease-based locking. If a pipeline job is cancelled mid-run,
the lock may persist. To release it:

```bash
# Identify the lease on the state blob
az storage blob show \
  --account-name platformtfstate \
  --container-name tfstate \
  --name portal/prod/terraform.tfstate \
  --query "properties.lease"

# Break the lease (requires Storage Account Contributor)
az storage blob lease break \
  --account-name platformtfstate \
  --container-name tfstate \
  --name portal/prod/terraform.tfstate
```

Always confirm with the product team that no pipeline is actually running before
breaking a lease.

### State surgery (advanced)

If state becomes inconsistent — e.g. a resource was deleted in Azure manually but
still exists in state — use `terraform state rm` to remove the stale reference, then
re-import or let the next apply recreate it.

```bash
# Remove a stale resource from state
terraform state rm 'module.networking.azurerm_subnet.this["db"]'

# Import an existing resource into state
terraform import \
  'module.networking.azurerm_subnet.this["db"]' \
  /subscriptions/<id>/resourceGroups/portal-prod-rg/providers/Microsoft.Network/...
```

**State surgery must always be done with the product team informed and on standby.**
Never modify state without a written record of what was changed and why.

---

## Handling a failed apply

### 1. Assess the failure

Pull up the failed GitHub Actions run. The `terraform apply` step output shows
which resource failed and why. Common causes:

| Failure | Likely cause |
|---------|-------------|
| `AuthorizationFailed` | Service principal lacks a required RBAC role |
| `ResourceGroupNotFound` | Networking module hasn't created the RG yet (ordering issue) |
| `QuotaExceeded` | Subscription vCPU quota insufficient for the requested VM size |
| `InvalidParameter` | A variable value violates an Azure constraint (e.g. password complexity) |
| `ResourceAlreadyExists` | A resource with the same name was created outside Terraform |

### 2. Determine what was created

Terraform applies are not atomic. Some resources may have been created before the
failure. Check the state file to see what succeeded:

```bash
terraform show -json portal-prod.tfstate | jq '[.values.root_module.child_modules[].resources[].address]'
```

### 3. Fix and re-run

Fix the root cause (RBAC assignment, quota request, corrected variable). Then
re-trigger the pipeline from the same commit — do not force-push or amend.
The pipeline will re-run `terraform init` and reuse the existing `tfplan` artifact.

> **Important:** If the `tfplan` artifact has expired (default 3-day retention),
> you must re-run from the `synth` job, which generates a new plan. Review the new
> plan before approving apply.

### 4. If partial apply left inconsistent state

Post in **#platform-infra** with the job link and the affected team. Do not
attempt manual remediation without coordinating with the platform team lead.

---

## Emergency (break-glass) deployment

> **Use this only when the pipeline is broken and a production fix cannot wait.**
> Every break-glass deployment must be logged in a Jira incident ticket and
> reviewed post-incident. Two platform team members must be present.

### When to use

- The GitHub Actions runner is offline and a critical production bug must be deployed.
- The reusable workflow has a bug that blocks all deploys and a hotfix is urgent.
- Azure Policy or a management lock is blocking a legitimate emergency change.

### Prerequisites

- Platform team lead authorization (verbal or Slack, captured in the ticket).
- A second platform engineer present as witness.
- Your personal Azure credentials must be configured with Contributor scope on the
  target subscription. The OIDC service principal used by the pipeline does not work
  interactively — use `az login` with your personal identity.

### Steps

**1. Create an incident ticket** in Jira before touching anything:
- Reason for break-glass, environment affected, change being deployed, names of both engineers.

**2. Remove the management locks** (non-dev only). Locks exist on the resource
group, VNet, PostgreSQL server, and AKS cluster. Remove only those needed for this
specific change — leave all others in place.

```bash
az lock list --resource-group <rg-name> --output table
az lock delete --name <lock-name> --resource-group <rg-name>
```

**3. Authenticate and initialize**:

```bash
az login
az account set --subscription <subscription-id>

eval $(ssh-agent) && ssh-add /path/to/tf_modules_deploy_key

terraform -chdir=shared init \
  -backend-config=../<env>/backend.hcl
```

**4. Plan and review**:

```bash
terraform -chdir=shared plan \
  -var-file=../<env>/terraform.tfvars \
  -out=emergency.tfplan
```

Confirm the plan matches exactly what the ticket describes. If it shows anything
unexpected, stop and investigate before applying.

**5. Apply**:

```bash
terraform -chdir=shared apply emergency.tfplan
```

**6. Re-create every management lock you removed**:

```bash
az lock create \
  --name "<prefix>-rg-lock" \
  --resource-group <rg-name> \
  --lock-type CanNotDelete \
  --notes "Restored after break-glass: <JIRA-TICKET>"

az lock create \
  --name "<prefix>-vnet-lock" \
  --resource-id <vnet-resource-id> \
  --lock-type CanNotDelete \
  --notes "Restored after break-glass: <JIRA-TICKET>"
# Repeat for PostgreSQL server and AKS cluster as needed
```

**7. Post-incident** (within 24 hours):
- Close the Jira ticket with the apply output URL and a summary.
- Open a follow-up ticket to fix the underlying pipeline issue.
- Run the drift detection workflow manually to confirm state is consistent.
- Present the incident at the next platform team meeting to prevent recurrence.

---

## Handling unexpected drift

Drift occurs when the real Azure state diverges from Terraform state — typically
because someone created, modified, or deleted a resource outside of the pipeline.

The plan job detects drift: resources that were changed manually will show as
`~` (update) or `-/+` (replace) even though the stack code didn't change.

To resolve:

1. **Identify the drift**: read the plan output carefully.
2. **Decide the source of truth**: is the manual change intentional and correct?
   - If Terraform should win: merge the PR with no stack changes. The apply will
     overwrite the manual change.
   - If the manual change should win: update the stack code to match reality,
     then plan+apply.
3. **Never leave drift unresolved across multiple apply cycles.** It compounds.

---

## Onboarding a new product team

When a product team wants to adopt Nautilus, follow this checklist:

### Platform team tasks

- [ ] Create a service principal for the team's Azure subscription with the
  minimum required roles (Contributor on the target resource group scope, plus
  Storage Blob Data Contributor on the state account).
- [ ] Add the SP credentials as GitHub Actions secrets on the team's infra repo:
  `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID`.
- [ ] Generate an SSH deploy key for `myorg/terraform-modules`. Add the public
  key as a read-only deploy key on the module repo. Add the private key as
  `TF_MODULES_DEPLOY_KEY` in the team's repo.
- [ ] Pre-create the Blob Storage state container path (or confirm the SP has
  permission to create blobs):
  ```
  tfstate/<project>/<environment>/terraform.tfstate
  ```
- [ ] Configure the GitHub `production` Environment on the team's repo with the
  platform team as required reviewer and a 10-minute review window.
- [ ] Share `LOG_WORKSPACE_ID` for the platform-managed Log Analytics workspace.
- [ ] Add the team to #platform-infra Slack channel.

### Developer team tasks (guided by platform team)

- [ ] Set up the repo structure: `cdktf.json`, `requirements.txt`, `stacks/`.
- [ ] Copy `infra.yml` from the reference implementation and update stack name references.
- [ ] Write a minimal stack (network only), synthesize locally, open a PR.
- [ ] Platform team reviews and approves the first PR end-to-end together.

The first PR should be a dev-environment network-only stack to validate the full
pipeline before adding database or compute resources.

---

## Coordinating module upgrades across teams

When the platform team releases a new `myorg-infra` version that contains breaking
changes, the upgrade must be coordinated across all consuming repos.

### Process

1. **Announce** in #platform-infra at least two weeks before the release, with
   the migration guide attached.
2. **Publish** the new `myorg-infra` version to `pkgs.myorg.internal`.
3. **Notify each team** via their repo's GitHub issue with the specific changes
   they need to make to their stack file.
4. **Support teams** during their upgrade PRs — be available for plan review.
5. **Set a hard deadline** (typically end of the sprint after announcement). After
   that, the old module tag may be archived and become unavailable.
6. **Verify** that all teams have merged their upgrades before archiving the old tag.

### Tracking upgrades

Maintain a tracking issue in the platform team's Jira board with a row per
consuming repo and status (pending / PR open / merged).

---

## Routine maintenance

### Monthly

- [ ] Review state file sizes — very large states (> 10 MB) may indicate resource
  sprawl. Review with the relevant product team.
- [ ] Audit deploy key access — confirm no stale keys exist for decommissioned repos.
- [ ] Check for Terraform provider updates and plan a minor version bump if needed.

### Quarterly

- [ ] Review Kubernetes versions in use and identify clusters approaching end-of-support.
  Notify teams with a planned upgrade window.
- [ ] Review PostgreSQL versions in use. Azure ends support on a rolling basis.
- [ ] Run `terraform validate` on all modules against the latest provider version.
- [ ] Rotate deploy keys.

### Ad hoc — pipeline template updates

When updating `infra.yml` (e.g. new action version, new CI step), the template
must be pushed to every consuming repo. Use a script to open identical PRs:

```bash
# Example: open a PR on every product infra repo with the updated infra.yml
for repo in portal-infra myapp-infra billing-infra; do
  gh pr create \
    --repo myorg/$repo \
    --title "chore: update infra pipeline to v2.1" \
    --body "Platform team maintenance — no stack changes required." \
    --base main \
    --head platform/pipeline-v2.1
done
```
