# tf-azure — Reference Product Team Infrastructure Repo

This directory is the **reference product team infrastructure repository** for
Nautilus. When onboarding a new product team, copy this layout into their new
repo (replacing `portal` with the team's product name). The product team then
owns and edits only the files described below — everything else is owned by the
platform team.

---

## Purpose

This repo holds the Terraform configuration for one product team's Azure
infrastructure across four environments: `dev`, `qa`, `stage`, and `prod`.

It does not contain raw Terraform module code. All resource logic lives in
`nautilus/terraform-modules`. This repo wires together those platform modules via a
thin root module in `shared/`, then separates environment-specific values into
per-environment directories.

---

## Repository layout

```
tf-azure/
├── .github/workflows/infra.yml   Calling workflow — delegates all CI/CD to reusable-workflows
├── shared/                        Terraform root module (platform-owned)
│   ├── main.tf                   Calls networking, database, and AKS modules
│   ├── variables.tf              All input declarations
│   ├── outputs.tf                VNet, subnet, FQDN, AKS identity outputs
│   ├── providers.tf              azurerm + azuread provider config
│   ├── versions.tf               Provider version pins
│   └── locals.tf                 Derived locals (name prefixes, tag maps)
├── dev/
│   ├── backend.hcl               Remote state config for dev
│   └── terraform.tfvars          Input values for dev
├── qa/
│   ├── backend.hcl
│   └── terraform.tfvars
├── stage/
│   ├── backend.hcl
│   └── terraform.tfvars
└── prod/
    ├── backend.hcl
    └── terraform.tfvars
```

---

## What lives where

### `shared/` — do not edit without a platform team PR

The `shared/` root module is the platform team's surface. It calls three
platform Terraform modules. All are sourced from `nautilus/terraform-modules` via
SSH deploy key:

| Module | Enabled by | Purpose |
|--------|-----------|---------|
| `modules/networking` | Always | VNet, subnets, NSGs, private DNS zones |
| `modules/database/postgres` | `enable_database = true` | PostgreSQL Flexible Server |
| `modules/compute/aks` | `enable_aks = true` | AKS cluster |

The module source pins (`?ref=vX.Y.Z`) in `shared/main.tf` are updated by the
platform team when a new module release is cut. Product team engineers do not
change these.

### `dev/`, `qa/`, `stage/`, `prod/` — product team edits here

Each environment directory contains exactly two files:

**`backend.hcl`** — Terraform remote state configuration. Points to the shared
`platformtfstate` storage account with an OIDC-authenticated backend. The state
key follows the pattern `<product>/<environment>/terraform.tfstate`. Platform
team sets this up during onboarding; product teams do not edit it.

**`terraform.tfvars`** — Input values for this environment. Product teams
configure their infrastructure here: VNet address space, subnet ranges, VM
SKUs, node pool sizes, feature flags (`enable_database`, `enable_aks`), and
tags.

---

## The pipeline

`infra.yml` is a thin calling workflow that delegates all logic to
`nautilus/reusable-workflows`. Product teams do not write pipeline logic — they
only configure secrets and GitHub Environments.

| Trigger | What runs |
|---------|-----------|
| Pull request | `tf-validate` → `tf-changes` → `tf-plan` for affected environments |
| Push to `main` | `tf-validate` → `tf-deploy` sequentially: dev → qa → stage (approval) → prod (approval) |
| Daily schedule (03:00 UTC) | `tf-drift` on all four environments — opens a GitHub issue if drift is detected |

Plan jobs use `cancel-in-progress: true` scoped per environment and PR branch,
so a new commit supersedes a stale plan. Deploy jobs always run to completion
(`cancel-in-progress: false`) to avoid partial applies.

Stage and prod deployments pause at `gate-stage` and `gate-prod` jobs that
reference GitHub Environments with required reviewers configured. Approval
unblocks the deploy job that follows.

---

## Secrets and variables

All secrets are injected by CI — none are stored in `terraform.tfvars`.

| Secret / Variable | Scope | Set by |
|-------------------|-------|--------|
| `DEV_AZURE_CLIENT_ID` | Actions secret | Platform team (bootstrap output) |
| `QA_AZURE_CLIENT_ID` | Actions secret | Platform team (bootstrap output) |
| `STAGE_AZURE_CLIENT_ID` | Actions secret | Platform team (bootstrap output) |
| `PROD_AZURE_CLIENT_ID` | Actions secret | Platform team (bootstrap output) |
| `DEV_AZURE_SUBSCRIPTION_ID` | Actions secret | Platform team (bootstrap output) |
| `QA_AZURE_SUBSCRIPTION_ID` | Actions secret | Platform team (bootstrap output) |
| `STAGE_AZURE_SUBSCRIPTION_ID` | Actions secret | Platform team (bootstrap output) |
| `PROD_AZURE_SUBSCRIPTION_ID` | Actions secret | Platform team (bootstrap output) |
| `AZURE_TENANT_ID` | Actions variable | Platform team (bootstrap output) |
| `TF_MODULES_DEPLOY_KEY` | Actions secret | Platform team (SSH key provisioning) |
| `DB_ADMIN_PASSWORD` | Actions secret | Platform team (`openssl rand -base64 32`) |
| `LOG_WORKSPACE_ID` | Actions secret | Platform team (Log Analytics resource ID) |

Authentication is OIDC throughout. No static credentials are stored. Each
environment uses a dedicated service principal whose federated credential is
scoped to `repo:<org>/<repo>:environment:<env>`.

---

## Adapting this repo for a new product team

When onboarding a new team, copy this repo and make the following changes:

### What to change

| Location | Change |
|----------|--------|
| `dev/backend.hcl` — `key` | Replace `portal` with the new product name |
| `qa/backend.hcl` — `key` | Same |
| `stage/backend.hcl` — `key` | Same |
| `prod/backend.hcl` — `key` | Same |
| All `terraform.tfvars` | Replace Portal team values with the new team's values |
| `infra.yml` — `secrets.*` | Secrets names stay the same; set values via `gh secret set` |

### What not to change

- `shared/main.tf` — module sources and module version pins are platform-owned
- `shared/variables.tf`, `shared/outputs.tf` — platform-owned
- `infra.yml` workflow structure — update only the `@v1.x.x` pin when the platform team releases a new reusable-workflows version

### Critical: `project` and `environment` are permanent identifiers

The `project` variable in `terraform.tfvars` (e.g. `"portal"`) and the
`environment` variable (e.g. `"dev"`) are embedded in every Azure resource
name, the Terraform state key, and management lock names. **Changing either
after initial deployment destroys all resources in that environment and
recreates them from scratch.** Choose these values carefully during onboarding
and treat them as immutable.

---

## Local development (platform team only)

Product teams do not run Terraform locally — the pipeline is the only
deployment path. Platform engineers who need to inspect state or run a targeted
plan locally can do so with:

```bash
# Authenticate via OIDC (requires az cli with matching service principal)
az login --service-principal \
  --username $ARM_CLIENT_ID \
  --tenant $ARM_TENANT_ID \
  --federated-token "$(az account get-access-token --query accessToken -o tsv)"

# Initialise for a specific environment
terraform -chdir=shared init \
  -backend-config=../dev/backend.hcl

# Plan against dev
terraform -chdir=shared plan \
  -var-file=../dev/terraform.tfvars \
  -var="administrator_password=$DB_ADMIN_PASSWORD" \
  -var="log_analytics_workspace_id=$LOG_WORKSPACE_ID"
```

Never run `terraform apply` locally against staging or production. All
non-dev applies must go through the pipeline so that the OPA policy check
and approval gate are enforced.

---

## Further reading

| Document | Where |
|----------|-------|
| Full onboarding checklist | [wiki/platform-product-maintenance.md](../wiki/platform-product-maintenance.md#onboarding-a-new-product-team) |
| Bootstrap (OIDC service principals) | [wiki/bootstrap.md](../wiki/bootstrap.md) |
| Module variables reference | [wiki/developer-guide.md](../wiki/developer-guide.md) |
| Pipeline reference | [reusable-workflows/](../reusable-workflows/) |
