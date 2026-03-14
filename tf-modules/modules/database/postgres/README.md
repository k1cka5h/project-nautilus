# modules/database/postgres

Provisions an Azure PostgreSQL Flexible Server with private VNet access,
optional zone-redundant HA, and configurable server parameters.

The server admin password is marked `sensitive` and never appears in logs.
Password rotation is handled outside Terraform — see the platform runbook.

## Usage (via CDKTF construct)

```python
from k1cka5h_infra import DatabaseConstruct, PostgresConfig

db = DatabaseConstruct(
    self, "postgres",
    project=self.project,
    environment=self.environment,
    resource_group="myapp-rg",
    location=self.location,
    subnet_id=network.subnet_ids["db"],
    dns_zone_id=network.dns_zone_ids["privatelink.postgres.database.azure.com"],
    admin_password=os.environ["DB_ADMIN_PASSWORD"],
    config=PostgresConfig(
        databases=["appdb"],
        sku="GP_Standard_D2s_v3",
        ha_enabled=self.environment == "prod",
    ),
)
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | required | Project name |
| `environment` | `string` | required | dev / staging / prod |
| `resource_group_name` | `string` | required | Existing resource group |
| `location` | `string` | `"eastus"` | Azure region |
| `delegated_subnet_id` | `string` | required | Delegated subnet for Postgres |
| `private_dns_zone_id` | `string` | required | Private DNS zone resource ID |
| `administrator_password` | `string` | required | Server admin password (sensitive) |
| `databases` | `list(string)` | `[]` | Database names to create |
| `sku_name` | `string` | `GP_Standard_D2s_v3` | Compute SKU |
| `storage_mb` | `number` | `32768` | Storage in MB (min 32768) |
| `pg_version` | `string` | `"15"` | PostgreSQL major version |
| `high_availability_mode` | `string` | `"Disabled"` | Disabled or ZoneRedundant |
| `geo_redundant_backup` | `bool` | `false` | Enable geo-redundant backups |
| `server_configurations` | `map(string)` | `{}` | PostgreSQL parameter overrides |
| `tags` | `map(string)` | `{}` | Resource tags |

## Outputs

| Name | Description |
|------|-------------|
| `server_id` | Server resource ID |
| `server_name` | Server name |
| `fqdn` | Connection host FQDN |
| `administrator_login` | Admin username |
| `database_ids` | Map of database name → resource ID |
