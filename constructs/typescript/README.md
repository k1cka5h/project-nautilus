# @k1cka5h/infra — TypeScript

Platform-managed CDKTF construct library for Azure. Published to the internal
npm registry at `https://npm.k1cka5h.internal`.

## Install

```bash
npm install @k1cka5h/infra@1.4.0 --registry https://npm.k1cka5h.internal
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
npm publish --registry https://npm.k1cka5h.internal
```
