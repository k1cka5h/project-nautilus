# Developer Guide

This guide covers everything a developer needs to provision Azure infrastructure
through Nautilus. You write a CDKTF stack in your language of choice. The platform
team handles everything else.

---

## Language support

Nautilus supports all five CDKTF languages. Pick the one your team already writes —
the synthesized Terraform JSON is identical regardless.

| Language | Example | Construct package |
|----------|---------|-------------------|
| Python | [`examples/python/`](../examples/python/) | `myorg-infra` (pip) |
| TypeScript | [`examples/typescript/`](../examples/typescript/) | `@myorg/infra` (npm) |
| C# | [`examples/csharp/`](../examples/csharp/) | `MyOrg.Infra` (NuGet) |
| Java | [`examples/java/`](../examples/java/) | `com.myorg:infra` (Maven) |
| Go | [`examples/go/`](../examples/go/) | `github.com/myorg/infra-go` (Go modules) |

See [`examples/README.md`](../examples/README.md) for naming convention differences
across languages and language-specific CI/CD pipeline snippets.

---

## What you can and cannot do

The platform enforces these rules automatically. Violations block your PR before
`terraform apply` ever runs — you will see an annotation on the plan step.

### Allowed in all environments

- Create resources using the approved constructs (`NetworkConstruct`, `DatabaseConstruct`, `AksConstruct`)
- Configure resource sizes within the [approved SKU list](#approved-sku-list)
- Set `ha_enabled`, `geo_redundant_backup`, `databases`, node pool counts, and other construct-exposed options
- Create and destroy resources freely in **dev**

### Blocked in all environments

| What | Why |
|------|-----|
| Public IPs (`azurerm_public_ip`) | All resources must be private |
| `public_network_access_enabled = true` on any resource | All resources must be private |
| Public blob storage (`allow_blob_public_access = true`) | All resources must be private |
| SKUs outside the approved list | Budget and quota control |

### Blocked in staging and prod

| What | Why |
|------|-----|
| Creating network resources (VNets, NSGs, subnets, DNS zones, private endpoints) | Network infrastructure is centrally managed by the platform team |
| Creating or modifying RBAC (role assignments, role definitions, managed identities) | All permissions in staging/prod are owned by the platform team |
| Deleting or replacing any resource | Requires a supervised platform team decommission |

If you need something that falls into a blocked category, open a ticket on the
platform team's Jira board or ask in **#platform-infra**.

### Approved SKU list

The pipeline enforces this. To request a new SKU, open a platform team Jira ticket.

**Virtual machines (AKS node pools)**

| Environment | Allowed SKUs |
|-------------|-------------|
| dev | `Standard_B2s`, `Standard_B4ms`, `Standard_D2s_v3`, `Standard_D4s_v3` |
| staging | dev SKUs + `Standard_D8s_v3`, `Standard_D16s_v3`, `Standard_E4s_v3`, `Standard_E8s_v3` |
| prod | `Standard_D4s_v3` through `Standard_D32s_v3`, `Standard_E4s_v3` through `Standard_E32s_v3`, `Standard_F8s_v2`, `Standard_F16s_v2` |

**PostgreSQL**

| Environment | Allowed SKUs |
|-------------|-------------|
| dev | `B_Standard_B1ms`, `B_Standard_B2ms`, `GP_Standard_D2s_v3` |
| staging | `GP_Standard_D2s_v3`, `GP_Standard_D4s_v3`, `GP_Standard_D8s_v3` |
| prod | `GP_Standard_D4s_v3` through `GP_Standard_D32s_v3`, `MO_Standard_E4ds_v4`, `MO_Standard_E8ds_v4` |

---

## Prerequisites

```bash
# Python 3.11 or later
python --version

# Node.js 20 or later (required by the CDKTF CLI)
node --version

# CDKTF CLI
npm install -g cdktf-cli@0.20

# Construct library — install for your language:
# Python
pip install myorg-infra==1.4.0 --index-url https://pkgs.myorg.internal/simple

# TypeScript
npm install @myorg/infra@1.4.0 --registry https://npm.myorg.internal

# C#
dotnet add package MyOrg.Infra --version 1.4.0 \
  --source https://nuget.myorg.internal/v3/index.json

# Java — add to pom.xml (see examples/java/pom.xml)

# Go
GOPROXY=https://goproxy.myorg.internal,direct go get github.com/myorg/infra-go@v1.4.0
```

If any internal registry is unreachable from your machine, open a ticket with
the platform team to get network access or a temporary token.

The construct libraries live in `constructs/` in this repo and are published to
their respective internal registries by the platform team.

---

## Setting up a new project

### 1. Create the project directory

```
my-product-infra/
├── cdktf.json
├── requirements.txt
└── stacks/
    └── myproduct_stack.py
```

### 2. Copy `cdktf.json`

```json
{
  "language": "python",
  "app": "python stacks/myproduct_stack.py",
  "projectId": "myproduct-cdktf",
  "sendCrashReports": "false",
  "terraformProviders": [],
  "terraformModules": [],
  "context": {
    "excludeStackIdFromLogicalIds": "true",
    "allowSepCharsInLogicalIds": "true"
  }
}
```

Update `app` and `projectId` with your product name. Do not modify any other field.

### 3. Create `requirements.txt`

```
myorg-infra==1.4.0
```

Always pin to an exact version. See [Upgrading](#upgrading-the-construct-library).

### 4. Copy the CI/CD pipeline

Copy `.github/workflows/infra.yml` from the
[tf-Azure reference implementation](../tf-Azure/.github/workflows/infra.yml)
into your repo. Update the stack name in the `working-directory` paths from
`portal-stack` to your stack's identifier (the second argument to your stack
class, e.g. `myproduct-stack`).

### 5. Request secrets from the platform team

Open a Jira ticket requesting the following GitHub Actions secrets for your repo.
The platform team provisions them:

| Secret | Description |
|--------|-------------|
| `ARM_CLIENT_ID` | Service principal for your product's subscription |
| `ARM_CLIENT_SECRET` | |
| `ARM_SUBSCRIPTION_ID` | |
| `ARM_TENANT_ID` | |
| `DB_ADMIN_PASSWORD` | PostgreSQL admin password (if using a database) |
| `LOG_WORKSPACE_ID` | Log Analytics workspace resource ID |
| `TF_MODULES_DEPLOY_KEY` | Read-only SSH deploy key for `myorg/terraform-modules` |

---

## Writing your stack

All stacks inherit from `BaseAzureStack`. This wires up:

- The AzureRM provider (pre-configured, do not touch)
- Remote state backend (do not touch)
- Required tags on every resource (automatic)

### Minimal stack

```python
import os
from constructs import Construct
from cdktf import App
from myorg_infra import BaseAzureStack

class MyProductStack(BaseAzureStack):
    def __init__(self, scope: Construct, id_: str):
        super().__init__(
            scope, id_,
            project="myproduct",          # lowercase, no spaces, short
            environment=os.environ["ENVIRONMENT"],
            location="eastus",            # omit to use the default
        )
        # Add constructs below

app = App()
MyProductStack(app, "myproduct-stack")
app.synth()
```

`ENVIRONMENT` must be `dev`, `staging`, or `prod`. The stack will raise a
`ValueError` at synthesis time if you pass anything else.

---

## Available constructs

### NetworkConstruct

Provisions a virtual network with subnets, NSGs, and private DNS zones.

```python
from myorg_infra import NetworkConstruct, SubnetConfig, SubnetDelegation

network = NetworkConstruct(
    self, "network",
    project=self.project,
    environment=self.environment,
    resource_group="myproduct-rg",
    location=self.location,
    address_space=["10.10.0.0/16"],
    subnets={
        "aks": SubnetConfig(
            address_prefix="10.10.0.0/22",
            service_endpoints=["Microsoft.ContainerRegistry"],
        ),
        "db": SubnetConfig(
            address_prefix="10.10.8.0/24",
            delegation=SubnetDelegation(
                name="postgres",
                service="Microsoft.DBforPostgreSQL/flexibleServers",
                actions=["Microsoft.Network/virtualNetworks/subnets/join/action"],
            ),
        ),
    },
    private_dns_zones=["privatelink.postgres.database.azure.com"],
)

# Outputs — pass to other constructs:
network.vnet_id
network.subnet_ids["aks"]    # subnet resource ID
network.subnet_ids["db"]
network.dns_zone_ids["privatelink.postgres.database.azure.com"]
```

**Address space planning**

| Subnet use | Recommended prefix | Notes |
|------------|--------------------|-------|
| AKS nodes | `/22` | ~1000 node IPs with Azure CNI |
| PostgreSQL | `/24` | Must carry delegation |
| App Gateway | `/27` | Minimum for WAF_v2 |
| Private endpoints | `/28` | One per endpoint target |

Every subnet automatically gets a Network Security Group. To add custom inbound
or outbound rules, use `SubnetConfig(nsg_rules=[...])`.

---

### DatabaseConstruct

Provisions a PostgreSQL Flexible Server with private VNet access.

```python
from myorg_infra import DatabaseConstruct, PostgresConfig

db = DatabaseConstruct(
    self, "postgres",
    project=self.project,
    environment=self.environment,
    resource_group="myproduct-rg",
    location=self.location,
    subnet_id=network.subnet_ids["db"],
    dns_zone_id=network.dns_zone_ids[
        "privatelink.postgres.database.azure.com"
    ],
    admin_password=os.environ["DB_ADMIN_PASSWORD"],   # never hardcode
    config=PostgresConfig(
        databases=["appdb", "analyticsdb"],
        sku="B_Standard_B1ms" if self.environment == "dev" else "GP_Standard_D2s_v3",
        ha_enabled=self.environment == "prod",
        server_configs={"max_connections": "400"},
    ),
)

# Outputs:
db.fqdn         # use as the connection host
db.server_id    # use for RBAC assignments
db.server_name
```

**PostgresConfig reference**

| Parameter | Type | Default | Notes |
|-----------|------|---------|-------|
| `databases` | `list[str]` | `[]` | Database names to create |
| `sku` | `str` | `GP_Standard_D2s_v3` | See SKU table below |
| `storage_mb` | `int` | `32768` | Min 32 GiB |
| `pg_version` | `str` | `"15"` | 14, 15, or 16 |
| `ha_enabled` | `bool` | `False` | **Required `True` in prod** |
| `geo_redundant` | `bool` | `False` | Enables geo-redundant backups |
| `server_configs` | `dict[str, str]` | `{}` | PostgreSQL parameter overrides |

**SKU reference**

| SKU | vCores | RAM | Use case |
|-----|--------|-----|----------|
| `B_Standard_B1ms` | 1 | 2 GiB | Dev only |
| `GP_Standard_D2s_v3` | 2 | 8 GiB | Staging / small prod |
| `GP_Standard_D4s_v3` | 4 | 16 GiB | Standard prod |
| `MO_Standard_E4s_v3` | 4 | 32 GiB | Memory-intensive workloads |

For SKUs not in this table, contact the platform team before using them.

---

### AksConstruct

Provisions an AKS cluster with Azure CNI, AAD RBAC, and Log Analytics monitoring.

```python
from myorg_infra import AksConstruct, AksConfig, NodePoolConfig

cluster = AksConstruct(
    self, "aks",
    project=self.project,
    environment=self.environment,
    resource_group="myproduct-rg",
    location=self.location,
    subnet_id=network.subnet_ids["aks"],
    log_workspace_id=os.environ["LOG_WORKSPACE_ID"],
    config=AksConfig(
        system_node_count=3 if self.environment == "prod" else 1,
        additional_node_pools={
            "workers": NodePoolConfig(
                vm_size="Standard_D4s_v3",
                enable_auto_scaling=True,
                min_count=2,
                max_count=10,
                labels={"workload": "app"},
            ),
        },
    ),
)

# Outputs:
cluster.cluster_id                      # resource ID
cluster.kubelet_identity_object_id      # assign ACR pull, Key Vault read
cluster.cluster_identity_principal_id   # assign Network Contributor
```

**AksConfig reference**

| Parameter | Type | Default | Notes |
|-----------|------|---------|-------|
| `kubernetes_version` | `str` | `"1.29"` | Platform-approved list only |
| `system_node_vm_size` | `str` | `Standard_D2s_v3` | |
| `system_node_count` | `int` | `3` | Use 3 for zone redundancy in prod |
| `additional_node_pools` | `dict` | `{}` | Pool name max 12 chars |
| `admin_group_object_ids` | `list[str]` | `[]` | AAD groups for cluster-admin |
| `service_cidr` | `str` | `10.240.0.0/16` | Must not overlap VNet |
| `dns_service_ip` | `str` | `10.240.0.10` | Within service_cidr |

**NodePoolConfig reference**

| Parameter | Type | Default | Notes |
|-----------|------|---------|-------|
| `vm_size` | `str` | `Standard_D4s_v3` | |
| `node_count` | `int` | `2` | Used when auto-scaling is off |
| `enable_auto_scaling` | `bool` | `False` | |
| `min_count` | `int` | `1` | Requires `enable_auto_scaling=True` |
| `max_count` | `int` | `10` | |
| `labels` | `dict` | `{}` | Kubernetes node labels |
| `taints` | `list[str]` | `[]` | e.g. `["dedicated=gpu:NoSchedule"]` |

The **system node pool is tainted** `CriticalAddonsOnly=true:NoSchedule` — your
application pods will not schedule on it. Always add at least one additional pool
for application workloads.

---

## Handling secrets

Never put secrets in your stack file. All sensitive values come from environment
variables, which are injected from GitHub Actions secrets by the CI/CD pipeline.

```python
# Correct
admin_password=os.environ["DB_ADMIN_PASSWORD"]

# Wrong — never do this
admin_password="Hunter2!"
```

For local synthesis (dry-run only — no Azure resources created), export them
in your shell:

```bash
export ENVIRONMENT=dev
export DB_ADMIN_PASSWORD="$(az keyvault secret show \
  --vault-name platform-kv \
  --name db-admin-password \
  --query value -o tsv)"
```

---

## Stack outputs

Use `TerraformOutput` to surface values after apply. Outputs appear in the
CI/CD job summary and in the remote state for cross-stack references.

```python
from cdktf import TerraformOutput

TerraformOutput(self, "db_fqdn",
    value=db.fqdn,
    description="PostgreSQL connection host for application config")

TerraformOutput(self, "cluster_id",
    value=cluster.cluster_id,
    description="AKS cluster resource ID")
```

Output values are written to `outputs.json` and uploaded as a pipeline artifact
after each successful apply.

---

## Synthesizing locally

Synthesis converts Python to Terraform JSON. It is a dry-run — no Azure resources
are created. Use it to verify your stack compiles cleanly before opening a PR.

```bash
cd my-product-infra

export ENVIRONMENT=dev
export DB_ADMIN_PASSWORD=placeholder   # any value works for synth

cdktf synth
```

If synthesis succeeds, `cdktf.out/` is populated with Terraform JSON. You can
inspect it, but you don't need to — the pipeline handles it.

To see what would change in Azure (requires Azure credentials):

```bash
cdktf diff
```

---

## Opening a pull request

1. Push your branch and open a PR against `main`.
2. The pipeline synthesizes your stack and posts a Terraform plan as a PR comment.
3. Review the plan — look for unexpected additions, changes, or destructions.
4. Get approval from the platform team (**required for prod environment changes**).
5. Merge to `main` — the pipeline applies automatically.

Production applies require a manual approval gate configured in the GitHub
`production` Environment. The platform team is a required reviewer.

---

## Common patterns

### Prod vs non-prod configuration

```python
is_prod = self.environment == "prod"

config = PostgresConfig(
    sku="GP_Standard_D4s_v3" if is_prod else "B_Standard_B1ms",
    ha_enabled=is_prod,
    geo_redundant=is_prod,
)
```

### Multiple databases on one server

```python
PostgresConfig(
    databases=["appdb", "analyticsdb", "auditdb"],
)
```

### Node pool per workload type

```python
AksConfig(
    additional_node_pools={
        "workers": NodePoolConfig(
            vm_size="Standard_D4s_v3",
            enable_auto_scaling=True,
            min_count=2, max_count=20,
            labels={"workload": "app"},
        ),
        "gpu": NodePoolConfig(
            vm_size="Standard_NC6s_v3",
            node_count=1,
            labels={"workload": "gpu"},
            taints=["dedicated=gpu:NoSchedule"],
        ),
    }
)
```

---

## Upgrading the construct library

The construct library follows semantic versioning. Breaking changes are announced
in **#platform-infra** (Slack) with a migration guide at least two weeks before release.

To upgrade:

1. Update `requirements.txt`: `myorg-infra==<new version>`
2. Run `cdktf synth` locally to verify your stack still synthesizes cleanly.
3. Open a PR — review the plan carefully, as upgrades may add or modify resources.

**Do not use version ranges** (e.g. `myorg-infra>=1.4`). Always pin exactly.

---

## Troubleshooting

### Synthesis fails with import errors (`ModuleNotFoundError`, `Cannot find module`, etc.)

You haven't installed the construct library for your language. Install it from the
internal registry (see [Prerequisites → Install](#prerequisites)):

```bash
# Python
pip install myorg-infra==1.4.0 --index-url https://pkgs.myorg.internal/simple

# TypeScript
npm install @myorg/infra@1.4.0 --registry https://npm.myorg.internal

# Go
GOPROXY=https://goproxy.myorg.internal,direct go get github.com/myorg/infra-go@v1.4.0
```

If the registry is unreachable, contact the platform team.

### Synthesis fails with `ValueError: environment must be dev, staging, or prod`

You're passing an unsupported environment value. Check that `ENVIRONMENT` is
exported and set to one of `dev`, `staging`, or `prod`.

### `terraform init` fails in CI with `ssh: connect to host github.com port 22`

The `TF_MODULES_DEPLOY_KEY` secret is missing or invalid. Verify it exists in your
repo's GitHub secrets. If it's missing, request it from the platform team.

### Policy check fails — `DENY [public-resources]`

Your plan is trying to create a public IP or enable public network access. All
resources must be private. Check that you haven't set `public_network_access_enabled`
or referenced an `azurerm_public_ip` resource anywhere in your stack.

### Policy check fails — `DENY [network-outside-dev]`

You're trying to create network infrastructure (VNet, NSG, subnet, private DNS zone,
or private endpoint) in staging or prod. Network in those environments is managed
centrally by the platform team. Remove the `NetworkConstruct` from your staging/prod
stack and reference the existing subnet and DNS zone IDs instead — the platform team
will provide them as stack inputs.

### Policy check fails — `DENY [permissions-outside-dev]`

Your stack is creating or modifying a role assignment, role definition, or managed
identity in staging or prod. All RBAC in those environments is owned by the platform
team. Remove the resource from your stack and open a **#platform-infra** ticket
describing the permission you need.

### Policy check fails — `DENY [deletions-outside-dev]`

Your plan includes a resource deletion or replacement in staging or prod. Common causes:

- You changed `project` or `environment` — these are in resource names and cause full replacement.
- You upgraded the construct library and the new module version changed a resource attribute.
- You intentionally removed a resource from your stack.

For intentional decommissions in staging/prod, open a **#platform-infra** ticket.
The platform team will remove the management lock and supervise the deletion.

### Policy check fails — `DENY [budget]`

The VM or PostgreSQL SKU you chose is not on the approved list for this environment.
See the [Approved SKU list](#approved-sku-list) above. To request a new SKU, open a
platform team Jira ticket.

### The plan shows resource destruction I didn't expect

Read the plan carefully before raising it with the platform team. Common causes:

- You changed `project` or `environment` — these are part of resource names.
  Changing them replaces every resource.
- You upgraded the construct library and the new module version changed a resource attribute.

If in doubt, tag `@platform-team` on the PR before merging.

### Apply failed mid-way — some resources were created and some were not

Do not retry immediately. Post in **#platform-infra** with the job link. The
platform team will inspect the state and guide the recovery. Do not run
`terraform apply` manually.

---

## Getting help

| Question | Where |
|----------|-------|
| Stack fails to synthesize | #platform-infra (Slack) |
| Need a resource type not in the library | Open a GitHub issue on `myorg/terraform-modules` |
| Something looks wrong in the plan | Tag `@platform-team` on the PR |
| Need a new SKU approved | Platform team Jira board |
| Production apply approval | Tag `@platform-team` on the PR |
