# constructs

Platform-managed IaC component libraries — one set per IaC framework, five languages each.
Product teams install the library for their language and framework and write stacks using
the components it exports. The platform team owns all code here.

```text
constructs/
├── cdktf/     CDKTF construct libraries (Terraform-backed)
│   ├── python/       nautilus-infra           → internal PyPI
│   ├── typescript/   @nautilus/infra          → internal npm
│   ├── csharp/       Nautilus.Infra           → internal NuGet
│   ├── java/         com.nautilus:infra       → internal Maven
│   └── go/           github.com/nautilus/infra-go  → internal Go proxy
│
└── pulumi/    Pulumi component libraries (Terraform-backed via pulumi-terraform-module)
    ├── python/       nautilus-infra-pulumi    → internal PyPI
    ├── typescript/   @nautilus/infra-pulumi   → internal npm
    ├── csharp/       Nautilus.Infra.Pulumi    → internal NuGet
    ├── java/         com.nautilus:infra-pulumi → internal Maven
    └── go/           github.com/nautilus/infra-pulumi-go → internal Go proxy
```

---

## Component API (all languages, both frameworks)

| Component | Purpose |
| --------- | ------- |
| `NetworkComponent` / `NetworkConstruct` | VNet, subnets, NSGs, private DNS zones |
| `DatabaseComponent` / `DatabaseConstruct` | PostgreSQL Flexible Server |
| `AksComponent` / `AksConstruct` | AKS cluster |

`NetworkComponent` is always required. `DatabaseComponent` and `AksComponent`
are optional — instantiate only what the team needs.

The CDKTF libraries also export `BaseAzureStack`, which wires the AzureRM provider
and remote state backend. Pulumi stacks configure their backend via `Pulumi.yaml`
and `pulumi login azblob://...`.

---

## CDKTF vs Pulumi

Both frameworks delegate all resource creation to Terraform — neither uses azure-native
directly. The difference is the programming model used to call the modules.

| | CDKTF (`cdktf/`) | Pulumi (`pulumi/`) |
| -- | ---------------- | ------------------ |
| **Backing** | `TerraformModule` wraps platform TF modules | `pulumi-terraform-module` wraps the same TF modules |
| **Resource creation** | Terraform (always) | Terraform (always) |
| **State** | Azure Blob Storage via `BaseAzureStack` | Pulumi backend — `pulumi login azblob://platformpulumi` |
| **Versioning** | Construct version = Terraform module tag | Pin via `moduleVersion` constant in each component file |
| **Auth** | AzureRM provider OIDC via GitHub Actions | Same — OIDC flows through Terraform |
| **Base class** | `BaseAzureStack extends TerraformStack` | No base class — configure backend in `Pulumi.yaml` |
| **Outputs** | Plain strings from `get_output()` | `pulumi.Output[T]` from `Module.GetOutput()` |
| **`managed_by` tag** | `"terraform"` | `"terraform"` |

---

## Library quick reference

### CDKTF

| Language | Package | Registry | Install |
| -------- | ------- | -------- | ------- |
| Python | `nautilus-infra` | `https://pkgs.nautilus.internal/simple` | `pip install nautilus-infra==<version>` |
| TypeScript | `@nautilus/infra` | `https://npm.nautilus.internal` | `npm install @nautilus/infra@<version>` |
| C# | `Nautilus.Infra` | `https://nuget.nautilus.internal/v3/index.json` | `dotnet add package Nautilus.Infra --version <version>` |
| Java | `com.nautilus:infra` | `https://maven.nautilus.internal` | Add to `pom.xml` |
| Go | `github.com/nautilus/infra-go` | `https://goproxy.nautilus.internal` | `go get github.com/nautilus/infra-go@v<version>` |

### Pulumi

| Language | Package | Registry | Install |
| -------- | ------- | -------- | ------- |
| Python | `nautilus-infra-pulumi` | `https://pkgs.nautilus.internal/simple` | `pip install nautilus-infra-pulumi==<version>` |
| TypeScript | `@nautilus/infra-pulumi` | `https://npm.nautilus.internal` | `npm install @nautilus/infra-pulumi@<version>` |
| C# | `Nautilus.Infra.Pulumi` | `https://nuget.nautilus.internal/v3/index.json` | `dotnet add package Nautilus.Infra.Pulumi --version <version>` |
| Java | `com.nautilus:infra-pulumi` | `https://maven.nautilus.internal` | Add to `pom.xml` |
| Go | `github.com/nautilus/infra-pulumi-go` | `https://goproxy.nautilus.internal` | `go get github.com/nautilus/infra-pulumi-go@v<version>` |

---

## Publishing

Publishing is automated by each library's CI workflow (`.github/workflows/ci.yml`)
and triggers on a semver tag (`v*.*.*`). The publish job runs only after tests pass
and after a reviewer approves the `registry` GitHub Environment.

The workflow verifies the git tag matches the version declared in the package
manifest before uploading any artifact. A mismatch fails the job.

**Go** is the exception: Go modules are versioned by git tag. The publish job warms
the internal Athens proxy cache by requesting the tagged version via HTTP.

To release a new version of the **CDKTF** libraries:

1. Update the `?ref=vX.Y.Z` pin in each construct file across all five libraries.
2. Bump the package version in each manifest to match.
3. Open a PR, get it merged to `main`.
4. Push the tag: `git tag -s vX.Y.Z -m "Release vX.Y.Z" && git push origin vX.Y.Z`
5. CI publishes all five libraries automatically after registry approval.

For the **Pulumi** libraries, step 1 is omitted (the TF module pin lives in the
`moduleVersion` constant inside each component file, not in the package version).
Steps 2–5 are identical.

---

## Development

### CDKTF

```bash
# Python
cd constructs/cdktf/python && pip install -e ".[dev]" && pytest tests/ -v

# TypeScript
cd constructs/cdktf/typescript && npm install && npm test

# C#
cd constructs/cdktf/csharp && dotnet test Nautilus.Infra.Tests/

# Java
cd constructs/cdktf/java && mvn test --batch-mode

# Go
cd constructs/cdktf/go && go test ./...
```

### Pulumi

```bash
# Python
cd constructs/pulumi/python && pip install -e ".[dev]" && pytest tests/ -v

# TypeScript
cd constructs/pulumi/typescript && npm install && npm test

# C#
cd constructs/pulumi/csharp && dotnet test Nautilus.Infra.Pulumi.Tests/

# Java
cd constructs/pulumi/java && mvn test --batch-mode

# Go
cd constructs/pulumi/go && go test ./...
```

---

## Adding a new component

When a new Terraform module is added to `tf-modules/`, add matching components to
both `cdktf/` and `pulumi/` libraries before tagging a release:

1. Add the component file to each language under both frameworks.
2. Update the export surface:
   - **Python**: `*/components/__init__.py` and `*/__init__.py`
   - **TypeScript**: `src/index.ts`
   - **C#/Java**: add a new class file (no explicit export needed)
   - **Go**: add a new `.go` file in the package
3. Add unit tests that assert the module source URL and variable wiring.
4. Update each library's README.

See [wiki/platform-module-maintenance.md — Adding a new module](../wiki/platform-module-maintenance.md#adding-a-new-module) for the full process.
