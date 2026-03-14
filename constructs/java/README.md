# com.nautilus:infra — Java

Platform-managed CDKTF construct library for Azure. Published to the internal
Maven registry at `https://maven.nautilus.internal/releases`.

## Install

Add to `pom.xml`:

```xml
<dependency>
  <groupId>com.nautilus</groupId>
  <artifactId>infra</artifactId>
  <version>1.4.0</version>
</dependency>
```

Add the internal repository:

```xml
<repository>
  <id>nautilus-internal</id>
  <url>https://maven.nautilus.internal/releases</url>
</repository>
```

## Constructs

| Class | Wraps | Key outputs |
|-------|-------|-------------|
| `BaseAzureStack` | Provider + AzureRM state backend | — |
| `NetworkConstruct` | `modules/networking` | `getVnetId()`, `getSubnetIds()`, `getDnsZoneIds()` |
| `DatabaseConstruct` | `modules/database/postgres` | `getFqdn()`, `getServerId()` |
| `AksConstruct` | `modules/compute/aks` | `getClusterId()`, `getKubeletIdentityObjectId()` |

## Development

```bash
mvn compile
mvn test
```

## Publishing

```bash
mvn deploy
```
