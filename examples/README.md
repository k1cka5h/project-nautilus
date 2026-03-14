# Nautilus CDKTF examples — multi-language

Each subdirectory contains the same `myapp` infrastructure stack implemented in a
different CDKTF-supported language. All examples produce identical Terraform JSON
and provision the same Azure resources.

| Language | Directory | Package manager | Internal registry |
|----------|-----------|-----------------|-------------------|
| Python | [`python/`](python/) | pip | `https://pkgs.k1cka5h.internal/simple` |
| TypeScript | [`typescript/`](typescript/) | npm | `https://npm.k1cka5h.internal` |
| C# | [`csharp/`](csharp/) | NuGet | `https://nuget.k1cka5h.internal/v3/index.json` |
| Java | [`java/`](java/) | Maven | `https://maven.k1cka5h.internal/releases` |
| Go | [`go/`](go/) | Go modules | `https://goproxy.k1cka5h.internal` |

---

## Which language should I use?

Use the language your team already writes. CDKTF synthesizes identical Terraform
JSON regardless of language — the choice has no effect on what gets deployed.

Python is the reference implementation. The platform team validates new construct
releases against Python first, then publishes language bindings for the others.

---

## Construct library packages by language

| Language | Package | Install |
|----------|---------|---------|
| Python | `k1cka5h-infra` | `pip install k1cka5h-infra==1.4.0 --index-url https://pkgs.k1cka5h.internal/simple` |
| TypeScript | `@k1cka5h/infra` | `npm install @k1cka5h/infra@1.4.0 --registry https://npm.k1cka5h.internal` |
| C# | `K1cka5h.Infra` | `dotnet add package K1cka5h.Infra --version 1.4.0` |
| Java | `com.k1cka5h:infra` | See `pom.xml` — `<version>1.4.0</version>` |
| Go | `github.com/k1cka5h/infra-go` | `go get github.com/k1cka5h/infra-go@v1.4.0` |

All packages are generated from the same JSII source. APIs are structurally
identical across languages — only naming conventions differ (see table below).

---

## Naming convention differences

CDKTF uses [JSII](https://aws.github.io/jsii/) to generate language bindings from
TypeScript. Each language follows its own idiomatic conventions automatically.

| Concept | Python | TypeScript | C# | Java | Go |
|---------|--------|------------|-----|------|-----|
| Class instantiation | `NetworkConstruct(self, "id", ...)` | `new NetworkConstruct(this, "id", {...})` | `new NetworkConstruct(this, "id", new NetworkConstructProps {...})` | `new NetworkConstruct(this, "id", NetworkConstructProps.builder()...build())` | `infra.NewNetworkConstruct(stack, jsii.String("id"), &infra.NetworkConstructProps{...})` |
| Property access | `network.vnet_id` | `network.vnetId` | `network.VnetId` | `network.getVnetId()` | `network.VnetId()` |
| Boolean in config | `ha_enabled=True` | `haEnabled: true` | `HaEnabled = true` | `.haEnabled(true)` | `HaEnabled: jsii.Bool(true)` |
| Dict / map | `{"key": "val"}` | `{ key: "val" }` | `new Dictionary<string,string> { ["key"] = "val" }` | `Map.of("key", "val")` | `&map[string]*string{"key": jsii.String("val")}` |
| String literal (Go only) | n/a | n/a | n/a | n/a | `jsii.String("value")` |
| Number literal (Go only) | n/a | n/a | n/a | n/a | `jsii.Number(3)` |

> **Go note:** All scalar values passed to CDKTF in Go must be wrapped in `jsii.String()`,
> `jsii.Bool()`, or `jsii.Number()`. This is a JSII runtime requirement, not a Nautilus
> convention.

---

## Local synthesis (all languages)

The synthesize command is the same for every language — only the prerequisites differ.

```bash
# Common
export ENVIRONMENT=dev
export DB_ADMIN_PASSWORD=placeholder

# TypeScript
cd typescript && npm install && cdktf synth

# C#
cd csharp && dotnet restore && cdktf synth

# Java
cd java && mvn compile && cdktf synth

# Go
cd go && go mod tidy && cdktf synth
```

---

## CI/CD pipeline

The `infra.yml` pipeline template works for all languages. The only job that
changes is the **synth** step — swap the language-specific install and build
commands:

### TypeScript
```yaml
- uses: actions/setup-node@v4
  with:
    node-version: "20"
- run: npm ci
- run: cdktf synth
```

### C#
```yaml
- uses: actions/setup-dotnet@v4
  with:
    dotnet-version: "8.0"
- run: dotnet restore
- run: cdktf synth
```

### Java
```yaml
- uses: actions/setup-java@v4
  with:
    java-version: "17"
    distribution: "temurin"
- run: mvn -e -q compile
- run: cdktf synth
```

### Go
```yaml
- uses: actions/setup-go@v5
  with:
    go-version: "1.22"
- run: go mod tidy
- run: cdktf synth
```

The plan and apply jobs are language-agnostic and do not need to change — they
operate on the synthesized Terraform JSON artifact.
