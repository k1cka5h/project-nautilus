# @myorg/infra — TypeScript

Platform-managed CDKTF construct library for Azure. Published to the internal
npm registry at `https://npm.myorg.internal`.

## Install

```bash
npm install @myorg/infra@1.4.0 --registry https://npm.myorg.internal
```

## Constructs

| Class | Wraps | Key outputs |
|-------|-------|-------------|
| `BaseAzureStack` | Provider + AzureRM state backend | — |
| `NetworkConstruct` | `modules/networking` | `vnetId`, `subnetIds`, `dnsZoneIds` |
| `DatabaseConstruct` | `modules/database/postgres` | `fqdn`, `serverId` |
| `AksConstruct` | `modules/compute/aks` | `clusterId`, `kubeletIdentityObjectId` |

## Development

```bash
npm install
npm run build
npm test
```

## Publishing

```bash
npm run build
npm publish --registry https://npm.myorg.internal
```
