# K1cka5h.Infra — C#

Platform-managed CDKTF construct library for Azure. Published to the internal
NuGet feed at `https://nuget.k1cka5h.internal/v3/index.json`.

## Install

```bash
dotnet add package K1cka5h.Infra --version 1.4.0 \
  --source https://nuget.k1cka5h.internal/v3/index.json
```

## Constructs

| Class | Wraps | Key outputs |
|-------|-------|-------------|
| `BaseAzureStack` | Provider + AzureRM state backend | — |
| `NetworkConstruct` | `modules/networking` | `VnetId`, `SubnetIds`, `DnsZoneIds` |
| `DatabaseConstruct` | `modules/database/postgres` | `Fqdn`, `ServerId` |
| `AksConstruct` | `modules/compute/aks` | `ClusterId`, `KubeletIdentityObjectId` |

## Development

```bash
dotnet build
dotnet test
```

## Publishing

```bash
dotnet pack -c Release
dotnet nuget push bin/Release/K1cka5h.Infra.1.4.0.nupkg \
  --source https://nuget.k1cka5h.internal/v3/index.json
```
