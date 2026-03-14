# Developer Interface Reference

This document describes the interface Nautilus exposes to product teams. It covers
what they can build, what the platform enforces, and how to support them when
things go wrong. Share this document with product teams during onboarding.

---

## What product teams control

Product teams write a single CDKTF stack file in their language of choice. They
control:

- Which constructs to use and how to configure them
- Resource sizes, within the platform-approved SKU list
- Environment-specific values (via tfvars)
- Stack outputs

Everything beneath the construct API — the Terraform modules, the pipeline, the
state backend, the credentials, the OPA and Azure policies — is owned by the
platform team and not visible to product teams.

---

## Supported languages

| Language | Package | Registry |
|----------|---------|---------|
| Python | `myorg-infra` | Internal PyPI |
| TypeScript | `@myorg/infra` | Internal npm |
| C# | `MyOrg.Infra` | Internal NuGet |
| Java | `com.myorg:infra` | Internal Maven |
| Go | `github.com/myorg/infra-go` | Internal Go proxy |

All five produce identical Terraform JSON. The synthesized output is what the
pipeline operates on.

---

## What the platform enforces

### Blocked in all environments

| What | Policy |
|------|--------|
| Public IPs (`azurerm_public_ip`) | `deny_public_resources` |
| `public_network_access_enabled = true` on any resource | `deny_public_resources` |
| Public blob storage (`allow_blob_public_access = true`) | `deny_public_resources` |
| VM or PostgreSQL SKUs outside the approved list | `deny_budget_violations` |
| Missing required tags (`managed_by`, `project`, `environment`) | `deny_missing_required_tags` |

### Blocked in staging and prod

| What | Policy |
|------|--------|
| Creating network resources (VNets, subnets, NSGs, DNS zones, private endpoints) | `deny_network_outside_dev` |
| Creating or modifying RBAC (role assignments, role definitions, managed identities) | `deny_permission_changes_outside_dev` |
| Deleting or replacing any resource | `deny_deletions_outside_dev` |

Network infrastructure in staging and prod is managed centrally. Product teams
reference existing subnet and DNS zone IDs from the platform team via stack inputs
rather than provisioning their own.

### Approved SKU lists

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

To add a SKU to the allowlist, update `policy/deny_budget_violations.rego`.

---

## Stack structure

All stacks inherit from `BaseAzureStack`. This base class wires up the AzureRM
provider, configures the remote state backend, and injects the required tags on
every resource. Product teams must not configure the provider or backend themselves.

```python
class MyStack(BaseAzureStack):
    def __init__(self, scope: Construct, id_: str):
        super().__init__(
            scope, id_,
            project="myproduct",           # lowercase, no spaces
            environment=os.environ["ENVIRONMENT"],  # dev | staging | prod
            location="eastus",             # optional, defaults to eastus
        )
```

The `project` and `environment` values are embedded in every resource name and in
the state key. Changing them after initial deployment destroys and recreates every
resource — treat them as permanent identifiers.

The stack raises `ValueError` at synthesis time if `environment` is not one of
`dev`, `staging`, or `prod`.

---

## Available constructs

### NetworkConstruct

Provisions a virtual network with subnets, NSGs, and optional private DNS zones.

**Key inputs**

| Input | Type | Notes |
|-------|------|-------|
| `address_space` | `list[str]` | e.g. `["10.10.0.0/16"]` |
| `subnets` | `dict[str, SubnetConfig]` | Named subnets with address prefix and optional delegation |
| `private_dns_zones` | `list[str]` | Zone FQDNs, e.g. `privatelink.postgres.database.azure.com` |

Every subnet automatically gets a Network Security Group. Custom inbound or
outbound rules use `SubnetConfig(nsg_rules=[...])`.

**Key outputs**

| Output | Notes |
|--------|-------|
| `vnet_id` | |
| `subnet_ids` | `dict[str, str]` — keyed by subnet name |
| `nsg_ids` | `dict[str, str]` — keyed by subnet name |
| `dns_zone_ids` | `dict[str, str]` — keyed by zone FQDN |

**Address space planning reference**

| Use | Recommended prefix | Notes |
|-----|--------------------|-------|
| AKS nodes | `/22` | ~1000 IPs with Azure CNI |
| PostgreSQL | `/24` | Must carry the delegation |
| App Gateway | `/27` | Minimum for WAF_v2 |
| Private endpoints | `/28` | One per target |

---

### DatabaseConstruct

Provisions a PostgreSQL Flexible Server with private VNet integration.

**Key inputs — PostgresConfig**

| Parameter | Type | Default | Notes |
|-----------|------|---------|-------|
| `databases` | `list[str]` | `[]` | Database names to create |
| `sku` | `str` | `GP_Standard_D2s_v3` | Must be on the approved list |
| `storage_mb` | `int` | `32768` | Min 32 GiB |
| `pg_version` | `str` | `"15"` | 14, 15, or 16 |
| `ha_enabled` | `bool` | `False` | Required `True` in prod |
| `geo_redundant` | `bool` | `False` | Enables geo-redundant backups |
| `server_configs` | `dict[str, str]` | `{}` | PostgreSQL parameter overrides |

The admin password must come from `os.environ["DB_ADMIN_PASSWORD"]`, which the
pipeline injects from the `DB_ADMIN_PASSWORD` GitHub secret. It must never be
hardcoded in the stack.

**Key outputs**

| Output | Notes |
|--------|-------|
| `fqdn` | Use as the application connection host |
| `server_id` | Use for downstream RBAC |
| `server_name` | |

---

### AksConstruct

Provisions an AKS cluster with Azure CNI, AAD RBAC, and Log Analytics monitoring.

**Key inputs — AksConfig**

| Parameter | Type | Default | Notes |
|-----------|------|---------|-------|
| `kubernetes_version` | `str` | `"1.29"` | Platform-approved versions only |
| `system_node_vm_size` | `str` | `Standard_D2s_v3` | |
| `system_node_count` | `int` | `3` | Use 3 for zone redundancy in prod |
| `additional_node_pools` | `dict` | `{}` | Pool name max 12 chars |
| `admin_group_object_ids` | `list[str]` | `[]` | AAD groups for cluster-admin |
| `service_cidr` | `str` | `10.240.0.0/16` | Must not overlap VNet |
| `dns_service_ip` | `str` | `10.240.0.10` | Within `service_cidr` |

The system node pool is tainted `CriticalAddonsOnly=true:NoSchedule`. Product
teams should always add at least one additional pool for application workloads.

**Key inputs — NodePoolConfig**

| Parameter | Type | Default | Notes |
|-----------|------|---------|-------|
| `vm_size` | `str` | `Standard_D4s_v3` | |
| `node_count` | `int` | `2` | Used when auto-scaling is off |
| `enable_auto_scaling` | `bool` | `False` | |
| `min_count` | `int` | `1` | Requires `enable_auto_scaling=True` |
| `max_count` | `int` | `10` | |
| `labels` | `dict` | `{}` | Kubernetes node labels |
| `taints` | `list[str]` | `[]` | e.g. `["dedicated=gpu:NoSchedule"]` |

**Key outputs**

| Output | Notes |
|--------|-------|
| `cluster_id` | Resource ID |
| `kubelet_identity_object_id` | Assign ACR pull, Key Vault read |
| `cluster_identity_principal_id` | Assign Network Contributor |

---

## Secrets and environment variables

No secrets are hardcoded in stack files. All sensitive values come from environment
variables, injected by the pipeline from GitHub Actions secrets.

| Secret | Injected as | Used for |
|--------|-------------|---------|
| `DB_ADMIN_PASSWORD` | `DB_ADMIN_PASSWORD` env var | PostgreSQL admin password |
| `LOG_WORKSPACE_ID` | `LOG_WORKSPACE_ID` env var | Log Analytics workspace resource ID |

For local synthesis, product teams export these manually from a secure source
(e.g. a key vault) before running `cdktf synth`. Synthesis is a dry-run — no
Azure resources are created.

---

## The pipeline

Product teams copy `infra.yml` from the reference implementation (`tf-azure/`) into
their repo. They update the stack name references and do not otherwise modify it.

**PR behaviour**
1. `validate` — fmt-check + validate, runs on every PR
2. `changes` — detects which environment folders changed
3. `plan-<env>` — runs for each affected environment in parallel; posts a plan
   comment; blocks the PR if any OPA policy is violated

**Merge to main**
1. `deploy-dev` → `deploy-qa` — automatic, sequential
2. `gate-stage` — requires manual approval from the platform team
3. `deploy-stage`
4. `gate-prod` — requires manual approval from the platform team
5. `deploy-prod`

Production applies require the platform team as required reviewer on the GitHub
`production` Environment. Configure this in the product team's repo settings.

---

## Stack outputs

Outputs appear in the CI/CD job summary and in the remote state for cross-stack
references. Product teams should expose all values their application configuration
needs (e.g. database FQDN, cluster ID).

---

## Upgrading the construct library

The platform team announces breaking changes with a migration guide at least two
weeks before release. Product teams upgrade by updating their pinned version in
their dependency file and running a local `cdktf synth` to verify compatibility.

Version ranges must not be used — product teams must always pin an exact version.

---

## Troubleshooting reference

This section covers the errors product teams will encounter. Use it to diagnose
issues quickly when supporting them.

### Synthesis fails — import or module not found

The construct library is not installed or was installed from the wrong registry.
Confirm the product team is using the correct internal registry URL and the pinned
version exists there.

### `ValueError: environment must be dev, staging, or prod`

The `ENVIRONMENT` environment variable is missing or has an unexpected value. Only
`dev`, `staging`, and `prod` are accepted. Check how the pipeline injects it.

### `terraform init` fails — `ssh: connect to host github.com port 22`

The `TF_MODULES_DEPLOY_KEY` secret is missing or invalid in the product team's
repo. Verify the secret exists. If it was recently rotated on the module repo,
ensure the updated private key was also added to the product repo.

### Policy check fails — `DENY [public-resources]`

The plan includes a public IP or enables public network access. This is always
blocked. Review the stack for `public_network_access_enabled` or any
`azurerm_public_ip` resource.

### Policy check fails — `DENY [network-outside-dev]`

A `NetworkConstruct` is present in a staging or prod stack. Network in those
environments is platform-managed. The product team should remove the construct
and use platform-provided subnet and DNS zone IDs as stack inputs instead.

### Policy check fails — `DENY [permissions-outside-dev]`

The stack creates or modifies a role assignment, role definition, or managed
identity in staging or prod. Remove it from the stack. If the permission is
legitimate, the platform team provisions it directly.

### Policy check fails — `DENY [deletions-outside-dev]`

The plan includes a destruction or replacement in staging or prod. Common causes:

- The `project` or `environment` value changed — these are in resource names and
  cause full replacement. Treat them as immutable identifiers.
- A construct library upgrade changed a resource attribute that forces replacement.
- The product team intentionally removed a resource.

For intentional decommissions, follow the
[supervised decommission process](platform-product-maintenance.md#supervised-decommission-in-stagingprod).

### Policy check fails — `DENY [budget]`

The chosen SKU is not on the approved list for the target environment. Review the
SKU tables above. To add a SKU, update `policy/deny_budget_violations.rego`.

### Policy check fails — `DENY [required-tags]`

A resource is missing one or more of the required tags (`managed_by`, `project`,
`environment`). Required tags are injected automatically by `BaseAzureStack` onto
all taggable resources. If a resource type is exempt (locks, role assignments, node
pools, etc.) it is listed in `deny_missing_required_tags.rego`. If a new resource
type needs exempting, update that file.

### The plan shows unexpected resource destruction

Common causes: `project` or `environment` changed, or a construct library upgrade
changed a resource attribute. Review the plan carefully before approving. Block
the PR and investigate with the product team if the destruction is unexpected.

### Apply failed mid-way — partial state

Do not let the product team retry immediately. Download the state file and identify
what was created before the failure. Fix the root cause, then re-trigger the
pipeline from the same commit. See
[Product Team Maintenance — Handling a failed apply](platform-product-maintenance.md#handling-a-failed-apply)
for the full procedure.
