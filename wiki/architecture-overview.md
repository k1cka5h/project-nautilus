# Architecture Overview

## Layers

```
┌─────────────────────────────────────────────────────────────────┐
│  Developer                                                       │
│  writes a CDKTF stack (Python / TS / C# / Java / Go)           │
│  using the platform construct library                           │
└─────────────────────────┬───────────────────────────────────────┘
                           │  git push → pull request
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  infra.yml  (thin calling workflow in each product repo)        │
│  delegates to myorg/reusable-workflows:                         │
│                                                                  │
│  tf-validate  →  fmt-check + init -backend=false + validate     │
│  tf-changes   →  detect which env folders changed (PR only)     │
│  tf-plan      →  init + plan + OPA check + PR comment           │
│                  (runs only for affected environments)          │
│  [gate job]   →  environment: stage/prod  (approval gate)       │
│  tf-deploy    →  init + plan + OPA check + apply + artifact     │
│                  dev → qa → stage → prod  (sequential)          │
└─────────────────────────┬───────────────────────────────────────┘
                           │  module source references
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  terraform-modules  (myorg/terraform-modules — private repo)    │
│                                                                  │
│  modules/networking          modules/database/postgres           │
│  modules/compute/aks         governance/                        │
│                                                                  │
│  Owned by the platform team. Enforces security, tagging,        │
│  naming conventions, and compliance policy.                      │
│  Management locks on every resource in staging/prod.   ◄── NEW │
└─────────────────────────┬───────────────────────────────────────┘
                           │  provisions resources
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  Azure                                                           │
│  Remote state: Azure Blob Storage (platform-managed)            │
│  Resources: VNet, AKS, PostgreSQL, etc.                         │
│  Azure Policy: deny public resources / network writes /         │
│    RBAC changes in staging+prod              ◄── NEW           │
│  Management locks: CanNotDelete on all non-dev resources        │
└─────────────────────────────────────────────────────────────────┘
```

---

## Responsibilities

| Concern | Developer | Platform team |
|---------|-----------|---------------|
| Which resources to create | ✅ | |
| Resource sizing (within approved SKU list) | ✅ | |
| Environment configuration | ✅ | |
| Terraform module implementation | | ✅ |
| Security and compliance policy | | ✅ |
| Required resource tagging | | ✅ (injected automatically) |
| Remote state backend | | ✅ |
| Azure provider configuration | | ✅ |
| CI/CD pipeline template | | ✅ |
| Construct libraries (all languages) | | ✅ |
| OPA/conftest policy rules (`policy/`) | | ✅ |
| Azure Policy definitions and assignments | | ✅ |
| Reusable GitHub Actions workflows (`myorg/reusable-workflows`) | | ✅ |
| Management lock removal for decommissions | | ✅ |
| Running `terraform apply` | | ✅ (pipeline only) |

Developers are deliberately shielded from Terraform and from cloud-level access
controls. The platform team owns every enforcement layer below the construct API.

---

## Enforcement layers

Three independent layers enforce policy. Each catches violations at a different point
so no single bypass defeats all enforcement.

| Layer | Where | When caught | Who sees it |
|-------|-------|-------------|-------------|
| OPA/conftest (`policy/`) | CI/CD pipeline | After `terraform plan`, before `terraform apply` | Developer — PR annotation |
| Azure Policy (`tf-modules/governance/`) | Azure ARM API | At `terraform apply` time | Developer — apply failure |
| Management locks (in each TF module) | Azure ARM API | When deletion is attempted | Anyone — portal/CLI/Terraform |

### What is enforced

| Rule | Environments |
|------|--------------|
| No public IPs or `public_network_access_enabled = true` | All |
| No network resource creation (VNets, NSGs, subnets, DNS zones, private endpoints) | Staging, prod |
| No RBAC changes (role assignments, role definitions, managed identities) | Staging, prod |
| No resource deletion or replacement | Staging, prod |
| VM and PostgreSQL SKUs must be on the platform-approved allowlist | All |

Network infrastructure in staging and prod is centrally managed by the platform
team and referenced by developer stacks via data sources — not provisioned by them.

---

## Authentication flow

```
GitHub Actions runner
│
├── ARM_CLIENT_ID / ARM_CLIENT_SECRET / ARM_TENANT_ID / ARM_SUBSCRIPTION_ID
│   → authenticates the Terraform AzureRM provider to Azure
│
├── TF_MODULES_DEPLOY_KEY  (SSH deploy key, repo-scoped, read-only)
│   → loaded by webfactory/ssh-agent before `terraform init`
│   → allows Terraform to clone git::ssh://git@github.com/myorg/terraform-modules.git
│
└── INTERNAL_PYPI_TOKEN  (if registry requires auth)
    → pip install myorg-infra --index-url https://pkgs.myorg.internal/simple
```

---

## State isolation

Every project+environment combination gets its own Terraform state file:

```
Azure Blob Storage
  container: tfstate
    portal/dev/terraform.tfstate
    portal/staging/terraform.tfstate
    portal/prod/terraform.tfstate
    myapp/dev/terraform.tfstate
    ...
```

State key is set automatically by `BaseAzureStack` from the `project` and
`environment` arguments. Developers cannot change it.

---

## Module versioning contract

All three constructs in `myorg-infra` pin an explicit Git tag when referencing
the Terraform module repo:

```
git::ssh://git@github.com/myorg/terraform-modules.git//modules/networking?ref=v1.4.0
```

- The `myorg-infra` package version and the `terraform-modules` tag it references
  are always in sync (both at `v1.4.0`).
- Upgrading `myorg-infra` upgrades the module pin automatically.
- Developers only ever change one line: the version in `requirements.txt`.

---

## Data flow for a PR

All pipeline logic lives in `myorg/reusable-workflows`. Product repo `infra.yml`
files are thin callers that pass inputs and secrets.

```
Developer pushes branch
        │
        ▼
[validate job]  ← tf-validate.yml
  terraform fmt -check -recursive
  terraform init -backend=false
  terraform validate
        │
        ▼
[changes job]   ← tf-changes.yml
  dorny/paths-filter → which of shared/dev/qa/stage/prod changed?
  outputs: shared=true, dev=false, qa=true, ...
        │
        ├─ shared=true OR dev=true  ──►  [plan-dev]   ─┐
        ├─ shared=true OR qa=true   ──►  [plan-qa]    ─┤  tf-plan.yml
        ├─ shared=true OR stage=true ─►  [plan-stage] ─┤  (parallel)
        └─ shared=true OR prod=true  ─►  [plan-prod]  ─┘
                                              │
                              each plan job:
                              terraform init -backend-config=../<env>/backend.hcl
                              terraform plan -var-file=../<env>/terraform.tfvars
                              conftest test → policy gate (blocks PR if violated)
                              → plan posted as PR comment
        │
        ▼  (merge to main only)
[deploy-dev]    ← tf-deploy.yml  (auto)
[deploy-qa]     ← tf-deploy.yml  (auto, after dev)
[gate-stage]    ← inline gate job with environment: stage  (approval required)
[deploy-stage]  ← tf-deploy.yml  (after approval)
[gate-prod]     ← inline gate job with environment: prod   (approval required)
[deploy-prod]   ← tf-deploy.yml  (after approval)
        │
        ▼
Azure Policy enforcement at ARM API level (second gate if pipeline bypassed)
Management locks prevent deletion of non-dev resources
```

**Approval gates** (`gate-stage`, `gate-prod`) are lightweight jobs in the calling
workflow that hold the `environment:` key. This is necessary because GitHub evaluates
environment protection rules against the repo where the workflow is *defined* — so
approval gates cannot live inside the reusable workflows themselves.
