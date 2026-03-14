# Project Nautilus

Nautilus is an infrastructure-as-code platform that lets developer teams provision
Azure resources by writing CDKTF stacks in any of five supported languages (Python,
TypeScript, C#, Java, Go), while the platform team enforces compliance, security,
and operational standards through managed Terraform modules and construct libraries.

Developers write a single stack class. A CI/CD pipeline turns it into Terraform,
posts a plan for review, and applies on merge. No one outside the platform team
touches Terraform directly.

---

## Repository layout

```
project-nautilus/
│
├── tf-modules/                     Private Terraform module repo (myorg/terraform-modules)
│   ├── modules/
│   │   ├── networking/             VNet, subnets, NSGs, private DNS zones
│   │   ├── database/postgres/      PostgreSQL Flexible Server
│   │   └── compute/aks/            AKS cluster
│   ├── CHANGELOG.md
│   └── .github/workflows/ci.yml   Validate + fmt-check on every PR
│
├── tf-azure/                       Example product team Terraform repo (Portal)
│   ├── shared/                     Terraform root module (module calls, variables, outputs)
│   ├── dev/ qa/ stage/ prod/       Per-environment backend config and tfvars
│   └── .github/workflows/infra.yml Thin calling workflow — delegates to reusable-workflows/
│
├── reusable-workflows/             Shared GitHub Actions workflows (myorg/reusable-workflows)
│   └── .github/workflows/
│       ├── tf-validate.yml         fmt-check + init + validate
│       ├── tf-changes.yml          PR change detection (which envs are affected)
│       ├── tf-plan.yml             plan + policy check + PR comment
│       └── tf-deploy.yml          plan + policy check + apply + artifact
│
├── constructs/                     Platform construct libraries (one per language)
│   ├── python/                     myorg-infra — published to internal PyPI
│   ├── typescript/                 @myorg/infra — published to internal npm
│   ├── csharp/                     MyOrg.Infra — published to internal NuGet
│   ├── java/                       com.myorg:infra — published to internal Maven
│   └── go/                         github.com/myorg/infra-go — internal Go proxy
│
├── examples/                       CDKTF consumer stack in all five supported languages
│   ├── README.md                   Language comparison, naming conventions, CI snippets
│   ├── python/                     Python — myorg-infra (pip)
│   ├── typescript/                 TypeScript — @myorg/infra (npm)
│   ├── csharp/                     C# — MyOrg.Infra (NuGet)
│   ├── java/                       Java — com.myorg:infra (Maven)
│   └── go/                         Go — github.com/myorg/infra-go
│
└── wiki/                           Full documentation
    ├── home.md                     Start here — audience guide and repo map
    ├── architecture-overview.md    System diagram, auth flow, state isolation
    ├── developer-guide.md          How developers build and deploy stacks
    ├── platform-module-maintenance.md  How the platform team manages tf-modules/
    └── platform-product-maintenance.md How the platform team supports product teams
```

---

## How it works

```
Developer writes a CDKTF stack (or edits Terraform tfvars)
         │
         │  git push → pull request
         ▼
infra.yml  (thin calling workflow in the product repo)
  │  calls reusable workflows from myorg/reusable-workflows
  ├── tf-validate   →  fmt-check + validate (every PR and push)
  ├── tf-changes    →  detect which environments are affected (PR only)
  ├── tf-plan       →  plan + OPA policy check + PR comment (affected envs only)
  └── tf-deploy     →  plan + policy check + apply, sequentially per env
         │                dev (auto) → qa (auto) → stage (approval) → prod (approval)
         │  module source references
         ▼
myorg/terraform-modules  (private, platform-owned)
  modules/networking
  modules/database/postgres
  modules/compute/aks
  governance/                Azure Policy + budget alerts
         │
         ▼
Azure
  Policy: deny public resources, deny network/RBAC writes in staging+prod
  Resources + management locks (CanNotDelete on all non-dev resources)
  State: Azure Blob Storage  →  {project}/{environment}/terraform.tfstate
```

**Developers** write one stack file or edit tfvars. They never run `terraform apply`
or interact with the state backend.

**The platform team** owns the Terraform modules, construct libraries, reusable
workflows, OPA policies, Azure Policy governance, state backend, and service principals.

---

## Who should read what

| I am... | Start with |
|---------|-----------|
| A developer onboarding to Nautilus | [wiki/developer-guide.md](wiki/developer-guide.md) |
| A developer troubleshooting a failure | [wiki/developer-guide.md → Troubleshooting](wiki/developer-guide.md#troubleshooting) |
| A platform engineer maintaining TF modules | [wiki/platform-module-maintenance.md](wiki/platform-module-maintenance.md) |
| A platform engineer supporting a product team | [wiki/platform-product-maintenance.md](wiki/platform-product-maintenance.md) |
| Anyone wanting the full picture | [wiki/architecture-overview.md](wiki/architecture-overview.md) |

---

## Language support

All five CDKTF languages are supported. The synthesized Terraform JSON is identical
regardless of language — choose what your team already writes.

| Language | Example | Install |
|----------|---------|---------|
| Python | [`examples/python/`](examples/python/) | `pip install myorg-infra==1.4.0 --index-url https://pkgs.myorg.internal/simple` |
| TypeScript | [`examples/typescript/`](examples/typescript/) | `npm install @myorg/infra@1.4.0 --registry https://npm.myorg.internal` |
| C# | [`examples/csharp/`](examples/csharp/) | `dotnet add package MyOrg.Infra --version 1.4.0` |
| Java | [`examples/java/`](examples/java/) | Maven — see `pom.xml` |
| Go | [`examples/go/`](examples/go/) | `go get github.com/myorg/infra-go@v1.4.0` |

See [`examples/README.md`](examples/README.md) for naming convention differences
across languages and per-language CI/CD pipeline snippets.

---

## Quick start (developers)

### 1. Install prerequisites

```bash
npm install -g cdktf-cli@0.20
pip install myorg-infra==1.4.0 --index-url https://pkgs.myorg.internal/simple
```

### 2. Create your project

```
my-product-infra/
├── cdktf.json        ← copy from tf-Azure/cdktf.json, update app and projectId
├── requirements.txt  ← myorg-infra==1.4.0
└── stacks/
    └── mystack.py
```

### 3. Write a stack

```python
import os
from constructs import Construct
from cdktf import App
from myorg_infra import BaseAzureStack, NetworkConstruct, SubnetConfig

class MyStack(BaseAzureStack):
    def __init__(self, scope: Construct, id_: str):
        super().__init__(scope, id_,
            project="myproduct",
            environment=os.environ["ENVIRONMENT"],
        )

        NetworkConstruct(self, "network",
            project=self.project,
            environment=self.environment,
            resource_group="myproduct-rg",
            location=self.location,
            address_space=["10.10.0.0/16"],
            subnets={"app": SubnetConfig(address_prefix="10.10.0.0/22")},
        )

app = App()
MyStack(app, "myproduct-stack")
app.synth()
```

### 4. Synthesize locally (dry-run)

```bash
export ENVIRONMENT=dev
cdktf synth          # produces cdktf.out/ — no Azure resources created
```

### 5. Open a PR

The pipeline posts a Terraform plan as a comment. Review it, get platform team
approval for prod changes, and merge. Apply is automatic.

See [wiki/developer-guide.md](wiki/developer-guide.md) for the full reference.

---

## Available constructs

| Construct | Provisions | Key outputs |
|-----------|-----------|-------------|
| `NetworkConstruct` | VNet, subnets, NSGs, private DNS zones | `vnet_id`, `subnet_ids`, `dns_zone_ids` |
| `DatabaseConstruct` | PostgreSQL Flexible Server (private access) | `fqdn`, `server_id` |
| `AksConstruct` | AKS cluster (Azure CNI, AAD RBAC, monitoring) | `cluster_id`, `kubelet_identity_object_id` |

All constructs automatically inject required tags (`managed_by`, `project`,
`environment`) on every Azure resource.

---

## Terraform modules (platform team)

The Terraform modules in `tf-modules/` are the source of truth for how every
Azure resource is configured. They enforce:

- Naming conventions (`{project}-{environment}-{resource}`)
- Required tagging policy
- Security defaults (private endpoints, AAD RBAC, encryption at rest)
- HA requirements (zone redundancy in prod)

Developers never reference modules directly. The construct libraries (one per
language) pin a specific module version via SSH Git source:

```
git::ssh://git@github.com/myorg/terraform-modules.git//modules/networking?ref=v1.4.0
```

See [wiki/platform-module-maintenance.md](wiki/platform-module-maintenance.md)
for how modules are versioned, tested, and released.

---

## Secrets and access

| Secret | Scope | Owned by | Description |
|--------|-------|----------|-------------|
| `{ENV}_AZURE_CLIENT_ID` | Repository | Platform team | OIDC service principal client ID per environment |
| `{ENV}_AZURE_SUBSCRIPTION_ID` | Repository | Platform team | Azure subscription ID per environment |
| `AZURE_TENANT_ID` | Repository variable | Platform team | Azure AD tenant (shared across envs) |
| `TF_MODULES_DEPLOY_KEY` | Repository | Platform team | Read-only SSH deploy key for `myorg/terraform-modules` |
| `DB_ADMIN_PASSWORD` | Repository | Product team | PostgreSQL admin password |
| `LOG_WORKSPACE_ID` | Repository | Platform team | Shared Log Analytics workspace resource ID |

No static Azure credentials are stored — all authentication uses OIDC (workload
identity federation). The platform team provisions service principals and configures
federated credentials when onboarding a new product team. See
[wiki/platform-product-maintenance.md → Onboarding](wiki/platform-product-maintenance.md#onboarding-a-new-product-team).

---

## Getting help

| Question | Where |
|----------|-------|
| Stack fails to synthesize | #platform-infra (Slack) |
| Need a construct or resource type that doesn't exist | GitHub issue on `myorg/terraform-modules` |
| Something unexpected in the Terraform plan | Tag `@platform-team` on the PR |
| Need a new VM SKU or PostgreSQL SKU approved | Platform team Jira board |
| Production apply approval | Tag `@platform-team` on the PR |
| New team onboarding | Platform team Jira board |
