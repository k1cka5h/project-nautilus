# Platform Guide — Module Maintenance

This guide covers how the platform team manages `myorg/terraform-modules` —
the private Terraform module repository that backs every Nautilus construct.

---

## Repository conventions

### Directory layout

```
terraform-modules/
├── modules/
│   ├── networking/               One module per directory
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── database/
│   │   └── postgres/             Sub-category for resource families
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       └── README.md
│   └── compute/
│       └── aks/
│           ├── main.tf
│           ├── variables.tf
│           ├── outputs.tf
│           └── README.md
├── tests/                        Validation and integration tests
├── CHANGELOG.md
└── .github/workflows/ci.yml
```

Each module is a self-contained directory with no dependencies on other modules.
Modules do not call each other — that composition happens in the CDKTF constructs.

### File responsibilities

| File | Purpose |
|------|---------|
| `variables.tf` | All input declarations with descriptions and validations |
| `main.tf` | All resources. No `variable` or `output` blocks. |
| `outputs.tf` | All outputs, with descriptions. |
| `README.md` | Usage example, inputs table, outputs table |

Never split resources across multiple `.tf` files within a module — keep all
resource logic in `main.tf`. This makes code review and grep straightforward.

---

## Variable conventions

Every module **must** declare these variables:

```hcl
variable "project" {
  description = "Short project name. Used in resource naming and tags."
  type        = string
}

variable "environment" {
  description = "Deployment environment: dev, staging, or prod."
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "resource_group_name" {
  description = "..."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus"
}

variable "tags" {
  description = "Azure resource tags. Required tags are injected by the construct library."
  type        = map(string)
  default     = {}
}
```

Rules:
- Every variable must have a `description`.
- Enumerations must have a `validation` block — fail fast at plan time, not apply.
- Sensitive values (passwords, keys) must be marked `sensitive = true`.
- Optional variables must have a `default`. Required variables must not.
- Use `optional(type, default)` inside `object()` types to avoid forcing callers
  to specify every field.

### Naming resources

Use a consistent `local` prefix:

```hcl
locals {
  name_prefix = "${var.project}-${var.environment}"
}

resource "azurerm_virtual_network" "this" {
  name = "${local.name_prefix}-vnet"
  ...
}
```

The `this` alias for the primary resource of a module keeps output references
readable (`azurerm_virtual_network.this.id`).

---

## Output conventions

Every output **must** have a `description`. Sensitive outputs must be marked
`sensitive = true`.

```hcl
output "server_id" {
  description = "Resource ID of the PostgreSQL Flexible Server."
  value       = azurerm_postgresql_flexible_server.this.id
}

output "administrator_password" {
  description = "Admin password. Use to bootstrap connection strings."
  value       = azurerm_postgresql_flexible_server.this.administrator_password
  sensitive   = true
}
```

Output names must exactly match the `get_string()` calls in the corresponding
CDKTF construct. If you rename an output, you must update the construct in the
same release and bump the major version.

---

## Adding a new module

### 1. Open a design issue first

Before writing any code, open a GitHub issue describing:
- What resource(s) the module will manage
- What variables it will expose
- What outputs it will produce
- Why an existing module can't cover the use case

Get at least one other platform engineer to review the design.

### 2. Create the module directory

```bash
mkdir -p modules/<category>/<resource-name>
touch modules/<category>/<resource-name>/{main.tf,variables.tf,outputs.tf,README.md}
```

### 3. Write variables first

Define inputs before resources. This forces clarity about the module's contract
before implementation details.

### 4. Implement main.tf

Follow the resource conventions above. Add `lifecycle` blocks where appropriate:

```hcl
lifecycle {
  # Passwords are rotated outside Terraform.
  ignore_changes = [administrator_password]
}
```

### 5. Write outputs

Include all values a downstream construct might reasonably need (resource IDs,
FQDNs, managed identity principal IDs, etc.). Outputs are cheap — omitting one
later is a breaking change.

### 6. Add the construct to the language libraries

A new module is not useful until it has a corresponding CDKTF construct.
Create a new construct file in each language library under `constructs/` following
the existing patterns (`compute`, `database`, `network`). Update the exports for
each language:

- **Python**: add to `myorg_infra/constructs/__init__.py` and `myorg_infra/__init__.py`
- **TypeScript**: add to `src/index.ts`
- **C#**: add a new class file; no explicit export needed
- **Java**: add a new class file; no explicit export needed
- **Go**: add a new `.go` file in the `infra` package

### 7. Write a README

Every module needs a README with:
- One-paragraph description
- Usage example (CDKTF construct, not raw Terraform)
- Inputs table
- Outputs table

### 8. Validate locally

```bash
cd modules/<category>/<resource-name>
terraform init -backend=false
terraform validate
terraform fmt -check
```

### 9. Open a PR

The CI workflow runs `fmt -check` and `validate` on every module automatically.
A passing CI is required before merge.

---

## Modifying an existing module

### Backwards-compatible changes (minor or patch version)

These changes are safe and do not require a migration guide:
- Adding a new **optional** variable (with a default that preserves current behaviour)
- Adding a new output
- Adding a new resource that does not replace an existing one
- Fixing a bug that makes the module behave as documented

### Breaking changes (major version)

These require a major version bump, a migration guide, and a two-week announcement
in **#platform-infra** before release:

- Removing or renaming a variable
- Changing the type of a variable
- Removing or renaming an output
- Changing a resource's name or type (causes destroy + recreate)
- Adding a required variable (no default)
- Changing a `lifecycle.ignore_changes` list in a way that causes unexpected updates

When in doubt, treat it as breaking.

### How to make a breaking change safely

1. Add the new variable/output alongside the old one (both present).
2. Deprecate the old one in the README and via a `validation` warning if possible.
3. Release as a minor version with both present.
4. Give teams one full sprint to upgrade.
5. Remove the old one in the next major version.

---

## Testing

### Mandatory: `terraform validate`

The CI workflow runs `terraform validate` on every module on every PR. This
catches type errors, undefined references, and provider schema mismatches.

### Mandatory: `terraform fmt -check`

All `.tf` files must be formatted with `terraform fmt`. The CI enforces this.
Run `terraform fmt -recursive modules/` before pushing.

### Recommended: CDKTF construct unit tests

Each language library in `constructs/` has unit tests that synthesize each construct
to JSON and assert the module call is wired correctly. Run them per language:

```bash
# Python
cd constructs/python && pip install -e ".[dev]" && pytest tests/ -v

# TypeScript
cd constructs/typescript && npm install && npm test

# C#
cd constructs/csharp && dotnet test

# Java
cd constructs/java && mvn test

# Go
cd constructs/go && go test ./...
```

These tests catch cases where the construct passes the wrong variable name to the
module (e.g. `subnet_id` vs `delegated_subnet_id`).

### Optional: Terratest (integration)

For modules with complex conditional logic, consider a Terratest in `tests/`.
Terratest provisions real Azure resources and tears them down — use sparingly and
only in non-production subscriptions.

---

## Versioning and release process

The module repo uses Git tags that follow **Semantic Versioning** (`vMAJOR.MINOR.PATCH`).
All construct library package versions always match the module tag they reference.

### Release checklist

- [ ] All CI checks pass on `main`
- [ ] `CHANGELOG.md` updated under the new version heading
- [ ] README updated if any inputs/outputs changed
- [ ] For breaking changes: migration guide written and posted to #platform-infra
- [ ] For breaking changes: two-week notice period elapsed
- [ ] Construct updated in all five language libraries under `constructs/` and tested
- [ ] All five packages built and published to their respective internal registries

### Tagging a release

```bash
git checkout main
git pull
git tag -s v1.5.0 -m "Release v1.5.0"
git push origin v1.5.0
```

Use signed tags (`-s`). The CI `tag-check` job validates the tag format.

### Updating the construct library pins

After tagging, update the module source constant in each affected construct file
across all five language libraries. Example for the networking module:

```python
# Python — constructs/python/myorg_infra/constructs/network.py
_MODULE_SOURCE = (
    "git::ssh://git@github.com/myorg/terraform-modules.git"
    "//modules/networking?ref=v1.5.0"  # was v1.4.0
)
```

```typescript
// TypeScript — constructs/typescript/src/network.ts
const NETWORK_MODULE_SOURCE =
  "git::ssh://git@github.com/myorg/terraform-modules.git" +
  "//modules/networking?ref=v1.5.0";
```

The same pattern applies to the C#, Java, and Go libraries. After updating all
source strings, bump package versions to match and publish to all internal
registries.

---

## Access control

The `myorg/terraform-modules` repo is private. Access is controlled by GitHub team
membership:

| GitHub team | Access |
|-------------|--------|
| `platform-infra` | Write (can merge PRs, create tags) |
| `developers` | No direct access |
| CI runners | Read-only via deploy key (`TF_MODULES_DEPLOY_KEY`) |

The deploy key is a **repository-scoped, read-only SSH key**. Each consuming
product repo has its own deploy key secret — they are not shared. To provision
a new deploy key for a product team:

```bash
# Generate a key pair (do not add a passphrase)
ssh-keygen -t ed25519 -C "github-actions@myorg/portal-infra" -f /tmp/tf_modules_key

# Add the public key as a deploy key in the terraform-modules repo settings:
#   Settings → Deploy keys → Add deploy key (read-only)

# Add the private key as a secret in the product repo:
#   Settings → Secrets and variables → Actions → TF_MODULES_DEPLOY_KEY
```

Rotate deploy keys annually or immediately on suspected compromise.

---

## Maintaining enforcement policies

### OPA/conftest policies (`policy/`)

The OPA policies live in `policy/` at the root of this repo. They are checked into
version control and reviewed like any other code change — a PR is required.

**When to update OPA policies:**
- A new resource type needs to be blocked (add it to the relevant type set)
- A new SKU is approved by the platform team (add it to `deny_budget_violations.rego`)
- A new environment restriction is needed
- An existing policy is too broad and blocking legitimate use cases

**Testing a policy change locally:**

```bash
# Install conftest
brew install conftest   # or download from GitHub releases

# Get a real plan JSON to test against
terraform show -json tfplan > tfplan.json

# Run all policies (pass environment as data)
conftest test tfplan.json --policy policy/ --data <(printf '{"environment":"prod"}')

# Run a single policy file
conftest test tfplan.json --policy policy/deny_budget_violations.rego \
  --data <(printf '{"environment":"prod"}')
```

Always test both the case that should be denied and the case that should pass before
merging a policy change.

### Azure Policy (`tf-modules/governance/`)

Azure Policy is the cloud-level enforcement backstop. Changes to Azure Policy
definitions are Terraform changes in `tf-modules/governance/` and go through the
normal module PR + tag process.

**When to update Azure Policy:**
- A new resource type should be blocked at the ARM API level
- Policy scope needs to change (e.g. a new subscription is added for a new environment)
- A budget cap needs adjusting (`variables.tf` → `monthly_budget_amounts`)

The governance module is applied by the platform team from a privileged workspace
(not by product team pipelines). After merging a governance change:

```bash
cd tf-modules/governance
terraform init
terraform plan   # review carefully — this affects all subscriptions
terraform apply
```

### Management locks

Management locks are defined inside each Terraform module (`modules/networking`,
`modules/database/postgres`, `modules/compute/aks`) with:

```hcl
resource "azurerm_management_lock" "..." {
  count      = var.environment != "dev" ? 1 : 0
  lock_level = "CanNotDelete"
  ...
}
```

Locks are created automatically when a product team's stack is applied in
staging or prod. They do not need to be managed separately.

To remove a lock for a supervised decommission, see
[platform-product-maintenance.md → Supervised decommission](platform-product-maintenance.md#supervised-decommission-in-stagingprod).
