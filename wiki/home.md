# Project Nautilus — Wiki

Nautilus is the organization's infrastructure-as-code platform. It lets developer
teams provision Azure resources by writing CDKTF stacks in Python, TypeScript, C#,
Java, or Go, while the platform team maintains compliance, security, and operational
standards through managed Terraform modules and construct libraries.

---

## How it works — one paragraph

A developer writes a stack class in their language of choice that describes what
their product needs: a network, a database, a Kubernetes cluster. They open a pull
request. The CI/CD pipeline converts that code to Terraform JSON, posts a plan as a
PR comment, and applies the changes to Azure on merge. The Terraform modules backing
every resource are owned and maintained by the platform team — developers never see
or write Terraform.

---

## Who this wiki is for

| Audience | Start here |
|----------|-----------|
| Developer onboarding to Nautilus for the first time | [Developer Guide](developer-guide.md) |
| Developer troubleshooting a stack or pipeline issue | [Developer Guide → Troubleshooting](developer-guide.md#troubleshooting) |
| Platform engineer adding or changing a Terraform module | [Module Maintenance](platform-module-maintenance.md) |
| Platform engineer reviewing a product team's PR or managing state | [Product Team Maintenance](platform-product-maintenance.md) |
| Anyone wanting the full architectural picture | [Architecture Overview](architecture-overview.md) |

---

## Repository map

```
project-nautilus/
├── tf-modules/                   Private Terraform module repo (myorg/terraform-modules)
│   └── modules/
│       ├── networking/           VNet, subnets, NSGs, private DNS
│       ├── database/postgres/    PostgreSQL Flexible Server
│       └── compute/aks/          AKS cluster
│
├── tf-Azure/                     Example product team repo (Portal product)
│   ├── stacks/portal_stack.py    Developer-authored stack
│   └── .github/workflows/        Synth → plan → apply pipeline
│
├── reusable-workflows/           Shared GitHub Actions workflows (myorg/reusable-workflows)
│   └── .github/workflows/
│       ├── tf-validate.yml       fmt-check + init + validate
│       ├── tf-changes.yml        PR change detection (which envs are affected)
│       ├── tf-plan.yml           plan + policy check + PR comment
│       └── tf-deploy.yml        plan + policy check + apply + artifact
│
├── constructs/                   Platform construct libraries (one per language)
│   ├── python/                   myorg-infra — internal PyPI
│   ├── typescript/               @myorg/infra — internal npm
│   ├── csharp/                   MyOrg.Infra — internal NuGet
│   ├── java/                     com.myorg:infra — internal Maven
│   └── go/                       github.com/myorg/infra-go — internal Go proxy
│
└── examples/                     Consumer stack in all five CDKTF languages
    ├── python/                   pip  — myorg-infra
    ├── typescript/               npm  — @myorg/infra
    ├── csharp/                   NuGet — MyOrg.Infra
    ├── java/                     Maven — com.myorg:infra
    └── go/                       Go modules — github.com/myorg/infra-go
```

---

## Quick links

- [myorg/terraform-modules](https://github.com/myorg/terraform-modules) — private, platform team
- [myorg/reusable-workflows](https://github.com/myorg/reusable-workflows) — shared GitHub Actions workflows
- Construct libraries: `constructs/` in this repo (published to internal registries)
- Internal PyPI: `https://pkgs.myorg.internal/simple`
- Internal npm: `https://npm.myorg.internal`
- Internal NuGet: `https://nuget.myorg.internal/v3/index.json`
- Internal Maven: `https://maven.myorg.internal/releases`
- Internal Go proxy: `https://goproxy.myorg.internal`
- #platform-infra (Slack) — questions, incidents, announcements
- Platform team Jira board — module requests, new product onboarding
