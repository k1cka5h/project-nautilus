# Project Nautilus

Nautilus is a self-service IaC platform for Azure. Platform teams adopt it to give
product teams a safe, opinionated path to provisioning their own infrastructure — without
exposing raw Terraform, state, or credentials to application developers.

Product teams write a CDKTF stack in any of five languages (Python, TypeScript,
C#, Java, Go). The platform team owns everything beneath that abstraction: the
Terraform modules, construct libraries, CI/CD pipelines, OPA policies, Azure Policy
governance, state backend, and service principals.

This repository is the reference implementation. Fork it and adapt it to your
organization.

---

## What problem this solves

Product teams need infrastructure — and they need it when they need it, not weeks
later after a ticketing process. Nautilus gives developers a self-service path to
provision their own resources just-in-time, without waiting on the platform team
for every change.

The risk of self-service is drift, misconfiguration, and accidental destruction in
production. Nautilus addresses this through layered enforcement: OPA policies gate
every plan before apply, Azure Policy enforces constraints at the ARM API level, and
management locks protect stateful resources from deletion outside a supervised
process. Developers move fast inside a well-defined boundary; the platform team
defines and maintains that boundary rather than manually approving every change.

---

## Repository layout

```
project-nautilus/
│
├── tf-modules/                     Terraform module library (private to platform team)
│   ├── modules/
│   │   ├── networking/             VNet, subnets, NSGs, private DNS zones
│   │   ├── database/postgres/      PostgreSQL Flexible Server
│   │   └── compute/aks/            AKS cluster
│   ├── governance/                 Azure Policy definitions and assignments
│   └── .github/workflows/ci.yml   Validate, fmt-check, and test on every PR
│
├── reusable-workflows/             Shared GitHub Actions workflows
│   ├── .github/workflows/
│   │   ├── tf-validate.yml         fmt-check + init + validate
│   │   ├── tf-changes.yml          Detect which environments a PR affects
│   │   ├── tf-plan.yml             Plan + OPA policy check + PR comment
│   │   ├── tf-deploy.yml           Plan + policy check + apply + artifact upload
│   │   └── tf-drift.yml            Daily drift detection + GitHub issue on change
│   └── tests/                      Pytest suite — validates all workflow structure
│
├── constructs/                     Construct libraries, one per language
│   ├── python/                     myorg-infra — published to internal PyPI
│   ├── typescript/                 @myorg/infra — published to internal npm
│   ├── csharp/                     MyOrg.Infra — published to internal NuGet
│   ├── java/                       com.myorg:infra — published to internal Maven
│   └── go/                         github.com/myorg/infra-go — internal Go proxy
│
├── policy/                         OPA/conftest policies (gate every terraform plan)
│   ├── deny_public_resources.rego
│   ├── deny_network_outside_dev.rego
│   ├── deny_permission_changes_outside_dev.rego
│   ├── deny_deletions_outside_dev.rego
│   ├── deny_budget_violations.rego
│   ├── deny_missing_required_tags.rego
│   └── *_test.rego                 OPA test suite for every policy
│
├── tf-azure/                       Reference product-team repo (Portal team)
│   ├── shared/                     Terraform root module
│   ├── dev/ qa/ stage/ prod/       Per-environment backend config and tfvars
│   └── .github/workflows/infra.yml Thin calling workflow — delegates to reusable-workflows
│
├── examples/                       Example CDKTF consumer stacks (all five languages)
│
├── wiki/                           Full operational documentation
│   ├── home.md
│   ├── architecture-overview.md
│   ├── developer-guide.md
│   ├── platform-module-maintenance.md
│   └── platform-product-maintenance.md
│
└── .github/
    ├── dependabot.yml              Weekly dependency updates for all construct libraries
    └── workflows/wiki-sync.yml    Mirrors wiki/ to the GitHub wiki on push
```

---

## How the system works

```
Product team pushes a CDKTF stack change
        │
        │  pull request / push to main
        ▼
infra.yml  (thin calling workflow in the product repo — copied from tf-azure/)
  │
  ├── tf-validate   fmt-check + terraform validate              (every trigger)
  ├── tf-changes    detect which env folders changed            (PR only)
  ├── tf-plan       synthesize → plan → OPA check → PR comment  (affected envs, PR only)
  └── tf-deploy     plan → OPA check → apply                   (push to main)
        │               dev (auto) → qa (auto) → stage (approval) → prod (approval)
        │
        │  module source references via SSH deploy key
        ▼
tf-modules/  (private, platform-owned)
  modules/networking, modules/database/postgres, modules/compute/aks
        │
        ▼
Azure
  Resources created under management locks (CanNotDelete, all non-dev)
  Azure Policy: deny public resources, restrict network/RBAC in staging+prod
  State: Azure Blob Storage → {project}/{environment}/terraform.tfstate
```

Authentication is OIDC throughout — no static credentials are stored anywhere.
Each product team gets a service principal scoped to their Azure subscription.

---

## Prerequisites

Before implementing Nautilus, your organization needs:

**GitHub**
- A GitHub organization with Actions enabled
- At least three repositories: one for `terraform-modules`, one for
  `reusable-workflows`, and one per product team (the `tf-azure/` layout is the
  template)
- GitHub Environments configured with required reviewers for `stage` and `prod`

**Azure**
- An Azure subscription per environment (dev, staging, prod) per product team, or
  a shared subscription with separate resource groups — your choice
- A dedicated storage account (`platformtfstate`) for Terraform state, with a
  container per product team
- Management group or subscription-level access to assign Azure Policy

**Internal package registries**
- One registry per construct language (PyPI, npm, NuGet, Maven, Go proxy), or a
  single Artifactory/Nexus instance with virtual repos for each ecosystem
- The construct libraries in `constructs/` are published here; product teams
  install from here

**Tooling (platform team machines)**
- Terraform ≥ 1.7 (for `mock_provider` in `.tftest.hcl` tests)
- CDKTF CLI 0.20+
- OPA / conftest CLI (for running policy tests locally)
- Azure CLI (`az`)

---

## Implementation sequence

### 1. Fork and rename

Fork this repository. Replace `myorg` throughout with your organization slug.
Key locations to update:

| File | What to change |
|------|----------------|
| `constructs/*/` source files | Package names, import paths |
| `constructs/*/pyproject.toml`, `package.json`, `pom.xml`, etc. | Package name, registry URL |
| `tf-modules/modules/*/main.tf` | Any org-specific defaults |
| `reusable-workflows/.github/workflows/*.yml` | `myorg/terraform-modules` source refs |
| `tf-azure/.github/workflows/infra.yml` | `myorg/reusable-workflows` refs |
| `wiki/` | All references to `myorg`, `pkgs.myorg.internal`, `#platform-infra` |

### 2. Run the platform bootstrap

The `bootstrap/platform/` Terraform module creates the state backend, the platform
service principal, and its OIDC federated credential in one apply:

```bash
cd bootstrap/platform
terraform init
terraform apply \
  -var="platform_subscription_id=<platform-sub-id>" \
  -var="github_org=myorg" \
  -var="github_repo=project-nautilus"
```

Read the outputs — they print the exact GitHub Actions secrets and variables to set
on the Nautilus repo. See [wiki/bootstrap.md](wiki/bootstrap.md) for full details,
including how to optionally migrate the bootstrap state to the remote backend it creates.

### 3. Provision OIDC credentials for the first product team

The `bootstrap/product-team/` module creates four service principals (one per
environment), their OIDC federated credentials, and the required RBAC assignments:

```bash
cd bootstrap/product-team
terraform init \
  -backend-config="storage_account_name=platformtfstate" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=bootstrap/portal/terraform.tfstate" \
  -backend-config="use_oidc=true"
terraform apply \
  -var="product_name=portal" \
  -var="github_org=myorg" \
  -var="github_repo=portal-infra" \
  -var='subscription_ids={"dev":"<id>","qa":"<id>","stage":"<id>","prod":"<id>"}' \
  -var="state_storage_account_id=<from platform output>" \
  -var="platform_subscription_id=<platform-sub-id>"
```

`terraform output github_secrets` prints the complete set of secrets to copy into
the product team's repo. Repeat for each subsequent team.

### 4. Publish the construct libraries

Each library in `constructs/` needs to be published to your internal registry
before product teams can install it. The `constructs/*/README.md` files document
the publish step for each language.

Tag releases as `v<MAJOR>.<MINOR>.<PATCH>`. The reusable workflows reference
module versions via `?ref=<tag>` — construct library version and module tag must
stay in sync (both are bumped together).

### 5. Deploy governance (Azure Policy)

Apply the Azure Policy definitions in `tf-modules/governance/` to your management
group or target subscriptions. These are a second line of defence — the OPA
policies in `policy/` catch violations before `terraform apply`, and Azure Policy
catches anything that bypasses the pipeline:

```bash
cd tf-modules/governance
terraform init
terraform apply -var="management_group_id=<your-mg-id>"
```

### 6. Configure management locks

The Terraform modules automatically create `CanNotDelete` management locks on all
resources in staging and prod. No additional setup is required — but the platform
team must be aware that decommissioning any protected resource requires manually
removing the lock first. See
[wiki/platform-product-maintenance.md — Supervised decommission](wiki/platform-product-maintenance.md#supervised-decommission-in-stagingprod).

### 7. Onboard the first product team

Follow the checklist in
[wiki/platform-product-maintenance.md — Onboarding](wiki/platform-product-maintenance.md#onboarding-a-new-product-team).
The first team's initial PR should be a dev-environment network-only stack to
validate the full pipeline end-to-end before adding database or compute resources.

---

## What the platform team owns permanently

Once Nautilus is running, the platform team is responsible for:

| Area | Details |
|------|---------|
| Terraform modules (`tf-modules/`) | All changes, versioning, and breaking-change coordination |
| Construct libraries (`constructs/`) | Publishing new versions; coordinating upgrades across product teams |
| Reusable workflows (`reusable-workflows/`) | Pipeline template; pushing updates to every consuming repo |
| OPA policies (`policy/`) | Adding rules; reviewing violations with product teams |
| Azure Policy (`tf-modules/governance/`) | Definitions and assignments across all subscriptions |
| State backend | Storage account, RBAC, and lock management |
| Service principals | One per product team per environment; OIDC federated credentials |
| Module SSH deploy keys | Read-only deploy keys on `terraform-modules`; one per product repo |
| Incident response | Failed applies, state corruption, unexpected drift |
| Production approval gate | Required reviewer on GitHub Environments |

---

## Key design decisions

**OPA policies run before apply, Azure Policy runs after.** The `policy/` directory
holds conftest rules that gate `terraform plan` output inside the CI pipeline. Azure
Policy is a backstop for out-of-band changes. Both layers are intentional.

**Management locks prevent accidental deletion.** All non-dev resources carry a
`CanNotDelete` lock. The deletion OPA policy and the lock together mean that
removing a staging or prod resource requires two deliberate acts: a lock removal by
the platform team and a policy-compliant plan merge.

**No static credentials anywhere.** All Azure authentication uses OIDC workload
identity federation. The GitHub Actions `id-token: write` permission is set on
every workflow that talks to Azure.

**Construct version = module version.** The construct libraries pin a specific
`?ref=` tag on the module source URL. A construct library release and a module tag
are always cut together, so the mapping is always unambiguous.

**`cancel-in-progress: true` on plan jobs only.** A new commit to a PR cancels
stale plan jobs for that PR branch. Deploy jobs always run to completion
(`cancel-in-progress: false`) to avoid partial applies.

---

## Documentation

| Document | Audience |
|----------|---------|
| [wiki/architecture-overview.md](wiki/architecture-overview.md) | Anyone wanting the full system picture |
| [wiki/developer-guide.md](wiki/developer-guide.md) | Product team developers writing CDKTF stacks |
| [wiki/platform-module-maintenance.md](wiki/platform-module-maintenance.md) | Platform engineers maintaining `tf-modules/` |
| [wiki/platform-product-maintenance.md](wiki/platform-product-maintenance.md) | Platform engineers supporting product teams and handling incidents |
