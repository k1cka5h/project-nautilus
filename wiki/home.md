# Nautilus — Platform Team Wiki

This wiki is the operational reference for platform engineers who build and run
Nautilus. It covers the full system: Terraform modules, construct libraries,
CI/CD pipelines, OPA policies, state backend, and product team support.

If you are a product team developer, see the
[developer interface reference](developer-guide.md) — the document the platform
team maintains and shares with product teams.

---

## Navigation

| I need to... | Go to |
|---|---|
| Understand how the whole system fits together | [Architecture Overview](architecture-overview.md) |
| Provision Azure prerequisites and OIDC service principals | [Bootstrap](bootstrap.md) |
| Set up a new GitHub repo with branch protection, environments, and templates | [Repository Setup](repository-setup.md) |
| Add, change, or release a Terraform module or construct | [Module Maintenance](platform-module-maintenance.md) |
| Review a product team's PR, handle an incident, or onboard a new team | [Product Team Maintenance](platform-product-maintenance.md) |
| Know what the developer API looks like | [Developer Interface Reference](developer-guide.md) |

---

## Repository map

```
project-nautilus/
│
├── tf-modules/                     Private Terraform module library
│   ├── modules/
│   │   ├── networking/             VNet, subnets, NSGs, private DNS zones
│   │   ├── database/postgres/      PostgreSQL Flexible Server
│   │   └── compute/aks/            AKS cluster
│   ├── governance/                 Azure Policy definitions and assignments
│   ├── tests/                      Per-module .tftest.hcl suites (terraform test)
│   └── .github/workflows/ci.yml   Validate + fmt-check + test on every PR
│
├── reusable-workflows/             Shared GitHub Actions workflows
│   ├── .github/workflows/
│   │   ├── tf-validate.yml         fmt-check + init + validate
│   │   ├── tf-changes.yml          Detect which environments a PR affects
│   │   ├── tf-plan.yml             Plan + OPA check + post PR comment
│   │   ├── tf-deploy.yml           Plan + OPA check + apply + artifact upload
│   │   └── tf-drift.yml            Daily drift detection; opens issue on change
│   └── tests/                      Pytest suite validating all workflow YAML
│
├── constructs/                     Construct libraries, one per language
│   ├── python/                     nautilus-infra → internal PyPI
│   ├── typescript/                 @nautilus/infra → internal npm
│   ├── csharp/                     Nautilus.Infra → internal NuGet
│   ├── java/                       com.nautilus:infra → internal Maven
│   └── go/                         github.com/nautilus/infra-go → internal Go proxy
│
├── policy/                         OPA/conftest policies
│   ├── deny_public_resources.rego
│   ├── deny_network_outside_dev.rego
│   ├── deny_permission_changes_outside_dev.rego
│   ├── deny_deletions_outside_dev.rego
│   ├── deny_budget_violations.rego
│   ├── deny_missing_required_tags.rego
│   └── *_test.rego                 OPA test suite (one per policy)
│
├── tf-azure/                       Reference product-team repo (Portal)
│   ├── shared/                     Terraform root module
│   ├── dev/ qa/ stage/ prod/       Per-environment backend config and tfvars
│   └── .github/workflows/infra.yml Thin calling workflow
│
├── examples/                       Consumer stacks in all five languages
│
└── wiki/                           This documentation
```

---

## Platform team responsibilities at a glance

| Area | Details |
|------|---------|
| Terraform modules | All changes, CI, versioning, breaking-change coordination |
| Construct libraries | All five languages; publish to internal registries |
| Reusable workflows | Pipeline template; push updates to every product repo |
| OPA policies | Add rules; triage policy violations with product teams |
| Azure Policy | Definitions + assignments across all subscriptions |
| State backend | Storage account, RBAC, blob lease management |
| Service principals | One per product team per environment; OIDC federated credentials |
| Module deploy keys | Read-only SSH key per product repo |
| Production approval gate | Required reviewer on GitHub Environments |
| Incident response | Failed applies, state corruption, unexpected drift |
| Module upgrade coordination | Announce breaking changes; track migration across all consuming repos |
