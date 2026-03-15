# constructs/pulumi

Platform-managed Pulumi component libraries for Azure — one per supported language.
Product teams install the library for their language and write Pulumi programs using
the components it exports. The platform team owns all code here.

```
constructs/pulumi/
├── python/      nautilus-infra-pulumi           → internal PyPI
├── typescript/  @nautilus/infra-pulumi          → internal npm
├── csharp/      Nautilus.Infra.Pulumi           → internal NuGet
├── java/        com.nautilus:infra-pulumi       → internal Maven
└── go/          github.com/nautilus/infra-pulumi-go  → internal Go proxy
```

---

## What changed from CDKTF

| Aspect | CDKTF version | Pulumi version |
|--------|---------------|----------------|
| Resource model | Wraps platform Terraform modules via `TerraformModule` | Creates Azure resources **directly** via `azure-native` provider — no Terraform at runtime |
| Base class | `cdktf.TerraformStack` (`BaseAzureStack`) required | `pulumi.ComponentResource` — no base stack needed |
| State backend | Configured in `BaseAzureStack` (Azure Blob Storage) | Configured in each product team's `Pulumi.yaml` |
| Outputs | Plain `string` (resolved at synth time) | `pulumi.Output<T>` — resolved at deploy time |
| Class names | `NetworkConstruct`, `DatabaseConstruct`, `AksConstruct` | `NetworkComponent`, `DatabaseComponent`, `AksComponent` |
| Config types | Same `@dataclass` / `record` / builder shapes | Same shapes — identical field names and defaults |
| Tag `managed_by` value | `"terraform"` | `"pulumi"` |

---

## Component API (all languages)

| Component | Purpose |
|-----------|---------|
| `NetworkComponent` | VNet, subnets (with NSG per subnet), private DNS zones, VNet links |
| `DatabaseComponent` | PostgreSQL Flexible Server (VNET-integrated, HA optional, geo-backup optional) |
| `AksComponent` | AKS cluster (Azure CNI, system-assigned identity, AAD RBAC, Log Analytics) |

`NetworkComponent` is always required. `DatabaseComponent` and `AksComponent` are
optional — instantiate only what the team needs.

### Config types and outputs

All config types carry identical names and defaults across all five language libraries:

#### NetworkComponent

| Constructor argument | Type | Default |
|---------------------|------|---------|
| `project`           | string | required |
| `environment`       | string | required (`dev`/`staging`/`prod`) |
| `resource_group`    | string | required |
| `location`          | string | required |
| `address_space`     | string[] | required |
| `subnets`           | map of `SubnetConfig` | `{}` |
| `private_dns_zones` | string[] | `[]` |
| `extra_tags`        | map | `{}` |

Outputs: `vnet_id`, `vnet_name`, `subnet_ids` (map), `dns_zone_ids` (map)

#### DatabaseComponent

| Constructor argument | Type | Default |
|---------------------|------|---------|
| `project`           | string | required |
| `environment`       | string | required |
| `resource_group`    | string | required |
| `location`          | string | required |
| `subnet_id`         | string | required |
| `dns_zone_id`       | string | required |
| `admin_password`    | string | required |
| `config`            | `PostgresConfig` | defaults below |

`PostgresConfig` defaults: `sku="GP_Standard_D2s_v3"`, `storage_gb=32`,
`pg_version="15"`, `ha_enabled=false`, `geo_redundant=false`.

Outputs: `fqdn`, `server_id`, `server_name`

#### AksComponent

| Constructor argument | Type | Default |
|---------------------|------|---------|
| `project`           | string | required |
| `environment`       | string | required |
| `resource_group`    | string | required |
| `location`          | string | required |
| `subnet_id`         | string | required |
| `log_workspace_id`  | string | required |
| `config`            | `AksConfig` | defaults below |

`AksConfig` defaults: `kubernetes_version="1.29"`, `system_node_vm_size="Standard_D2s_v3"`,
`system_node_count=3`, `service_cidr="10.240.0.0/16"`, `dns_service_ip="10.240.0.10"`.

Outputs: `cluster_id`, `cluster_name`, `kubelet_identity_object_id`,
`cluster_identity_principal_id`

---

## Library quick reference

| Language | Package | Registry | Install |
|----------|---------|---------|---------|
| Python | `nautilus-infra-pulumi` | `https://pkgs.nautilus.internal/simple` | `pip install nautilus-infra-pulumi==<version>` |
| TypeScript | `@nautilus/infra-pulumi` | `https://npm.nautilus.internal` | `npm install @nautilus/infra-pulumi@<version>` |
| C# | `Nautilus.Infra.Pulumi` | `https://nuget.nautilus.internal/v3/index.json` | `dotnet add package Nautilus.Infra.Pulumi --version <version>` |
| Java | `com.nautilus:infra-pulumi` | `https://maven.nautilus.internal/releases` | Add to `pom.xml` — see below |
| Go | `github.com/nautilus/infra-pulumi-go` | `https://goproxy.nautilus.internal` | `go get github.com/nautilus/infra-pulumi-go@v<version>` |

---

## State backend

Pulumi state backend is **not** configured by this library. Product teams configure
their backend in their own `Pulumi.yaml`. To stay consistent with the CDKTF
remote backend (Azure Blob Storage), use:

```yaml
# Pulumi.yaml
name: my-infra-stack
runtime: python  # or nodejs / dotnet / java / go
backend:
  url: azblob://pulumi-state/<team>/<stack>
```

Set `AZURE_STORAGE_ACCOUNT` and `AZURE_STORAGE_KEY` (or use Workload Identity)
so the Pulumi CLI can reach the storage account.

---

## Publishing

Publishing is automated by each library's CI workflow
(`.github/workflows/ci.yml`) and triggers on a semver tag (`v*.*.*`). The
publish job runs only after tests pass and after a reviewer approves the
`registry` GitHub Environment.

The workflow verifies the git tag matches the version declared in the package
manifest before uploading any artifact. A mismatch fails the job.

**Go** is the exception: the publish job warms the internal Athens proxy cache
by requesting the tagged version via HTTP immediately after the tag is pushed.

To release a new version:

1. Bump the package version in each manifest (`pyproject.toml`, `package.json`,
   `pom.xml`, `Nautilus.Infra.Pulumi.csproj`, `go.mod`) to match the new tag.
2. Open a PR, get it merged to `main`.
3. Push the tag: `git tag -s v1.0.1 -m "Release v1.0.1" && git push origin v1.0.1`
4. CI publishes all five libraries automatically after registry approval.

---

## Development / local test commands

```bash
# Python
cd constructs/pulumi/python
pip install -e ".[dev]"
pytest tests/ -v

# TypeScript
cd constructs/pulumi/typescript
npm install && npm test

# C#
cd constructs/pulumi/csharp
dotnet test Nautilus.Infra.Pulumi.Tests/

# Java
cd constructs/pulumi/java
mvn test --batch-mode

# Go
cd constructs/pulumi/go
go test ./... -v
```

These tests use Pulumi mock infrastructure to intercept resource creation and
assert wiring without deploying any real Azure resources.

---

## Adding a new component

When a new Azure resource group needs to be wrapped:

1. Add a component file to each language directory following the existing patterns
   (e.g. `python/nautilus_infra_pulumi/components/storage.py`).
2. Update the export surface:
   - **Python**: add to `components/__init__.py` and `__init__.py`
   - **TypeScript**: add to `src/index.ts`
   - **C#**: add a new class file (no explicit export needed)
   - **Java**: add a new class file (no explicit export needed)
   - **Go**: add a new `.go` file in the `infrapulumi` package
3. Add unit tests using Pulumi mocks.
4. Bump the version in all five manifests and tag a new release.
