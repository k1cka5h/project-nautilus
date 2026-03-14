# constructs

Platform-managed CDKTF construct libraries — one per supported language.
Product teams install the library for their language and write stacks using the
constructs it exports. The platform team owns all code here.

```
constructs/
├── python/       nautilus-infra          → internal PyPI
├── typescript/   @nautilus/infra         → internal npm
├── csharp/       Nautilus.Infra          → internal NuGet
├── java/         com.nautilus:infra      → internal Maven
└── go/           github.com/nautilus/infra-go  → internal Go proxy
```

Each library wraps the same three platform Terraform modules
(`modules/networking`, `modules/database/postgres`, `modules/compute/aks`) and
exposes them through language-idiomatic CDKTF constructs. Construct library
version always matches the Terraform module tag it references — they are bumped
together on every release.

---

## Construct API (all languages)

| Construct | Wraps | Purpose |
|-----------|-------|---------|
| `BaseAzureStack` | Provider + AzureRM remote backend | Required base for every product team stack |
| `NetworkConstruct` | `modules/networking` | VNet, subnets, NSGs, private DNS zones |
| `DatabaseConstruct` | `modules/database/postgres` | PostgreSQL Flexible Server |
| `AksConstruct` | `modules/compute/aks` | AKS cluster |

`BaseAzureStack` configures the AzureRM provider (OIDC authentication) and wires
the remote state backend. Every product team stack must extend it.

`NetworkConstruct` is always required. `DatabaseConstruct` and `AksConstruct`
are optional — instantiate only what the team needs.

---

## Library quick reference

| Language | Package | Registry | Install |
|----------|---------|---------|---------|
| Python | `nautilus-infra` | `https://pkgs.nautilus.internal/simple` | `pip install nautilus-infra==<version>` |
| TypeScript | `@nautilus/infra` | `https://npm.nautilus.internal` | `npm install @nautilus/infra@<version>` |
| C# | `Nautilus.Infra` | `https://nuget.nautilus.internal/v3/index.json` | `dotnet add package Nautilus.Infra --version <version>` |
| Java | `com.nautilus:infra` | `https://maven.nautilus.internal` | Add to `pom.xml` — see library README |
| Go | `github.com/nautilus/infra-go` | `https://goproxy.nautilus.internal` | `go get github.com/nautilus/infra-go@v<version>` |

See each library's `README.md` for language-specific install and usage examples.

---

## Publishing

Publishing is automated by each library's CI workflow
(`.github/workflows/ci.yml`) and triggers on a semver tag (`v*.*.*`). The
publish job runs only after tests pass and after a reviewer approves the
`registry` GitHub Environment.

The workflow verifies the git tag matches the version declared in the package
manifest before uploading any artifact. A mismatch fails the job.

**Go** is the exception: Go modules are versioned by git tag, not a package
manifest. The publish job warms the internal Athens proxy cache by requesting
the tagged version via HTTP immediately after the tag is pushed.

To release a new version:

1. Update the `_MODULE_SOURCE` / `NETWORK_MODULE_SOURCE` / equivalent constant
   in each affected construct file across all five libraries to point at the new
   `?ref=vX.Y.Z` tag.
2. Bump the package version in each manifest (`pyproject.toml`, `package.json`,
   `pom.xml`, `*.csproj`, `go.mod`) to match.
3. Open a PR, get it merged to `main`.
4. Push the tag: `git tag -s vX.Y.Z -m "Release vX.Y.Z" && git push origin vX.Y.Z`
5. CI publishes all five libraries automatically after registry approval.

Full release checklist: [wiki/platform-module-maintenance.md — Release checklist](../wiki/platform-module-maintenance.md#release-checklist)

---

## Development

Run tests locally before pushing:

```bash
# Python
cd constructs/python
pip install -e ".[dev]"
pytest tests/ -v

# TypeScript
cd constructs/typescript
npm install && npm test

# C#
cd constructs/csharp
dotnet test Nautilus.Infra.Tests/

# Java
cd constructs/java
mvn test --batch-mode

# Go
cd constructs/go
go test ./...
```

These tests synthesize constructs to JSON and assert the module call is wired
correctly. Run them whenever changing module variable or output names — they
catch mismatches between the construct (e.g. `subnet_id`) and the module
variable name (e.g. `delegated_subnet_id`).

---

## Adding a new construct

When a new Terraform module is added to `tf-modules/`, a matching construct must
be added to all five libraries before the release is tagged. Steps:

1. Add the construct file to each library following existing patterns.
2. Update the language-specific export surface:
   - **Python**: `nautilus_infra/constructs/__init__.py` and `nautilus_infra/__init__.py`
   - **TypeScript**: `src/index.ts`
   - **C#**: add a new class file (no explicit export needed)
   - **Java**: add a new class file (no explicit export needed)
   - **Go**: add a new `.go` file in the `infra` package
3. Add unit tests that synthesize the construct and assert the module call
   wiring.
4. Update each library's README with the new construct entry.

See [wiki/platform-module-maintenance.md — Adding a new module](../wiki/platform-module-maintenance.md#adding-a-new-module) for the full process.
