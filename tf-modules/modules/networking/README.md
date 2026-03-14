# modules/networking

Creates a VNet, subnets, NSGs, and private DNS zones for a project environment.
All subnets automatically receive an NSG. Delegations and service endpoints are
optional per-subnet.

## Usage (via CDKTF construct)

Developers do not call this module directly. Use `NetworkConstruct` from `myorg-infra`:

```python
from myorg_infra import NetworkConstruct, SubnetConfig, SubnetDelegation

network = NetworkConstruct(
    self, "network",
    project=self.project,
    environment=self.environment,
    resource_group="myapp-rg",
    location=self.location,
    address_space=["10.10.0.0/16"],
    subnets={
        "aks": SubnetConfig(address_prefix="10.10.0.0/22"),
        "db":  SubnetConfig(
            address_prefix="10.10.8.0/24",
            delegation=SubnetDelegation(
                name="postgres",
                service="Microsoft.DBforPostgreSQL/flexibleServers",
                actions=["Microsoft.Network/virtualNetworks/subnets/join/action"],
            ),
        ),
    },
    private_dns_zones=["privatelink.postgres.database.azure.com"],
)
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | required | Project name for resource naming |
| `environment` | `string` | required | dev / staging / prod |
| `resource_group_name` | `string` | required | Resource group to create |
| `location` | `string` | `"eastus"` | Azure region |
| `address_space` | `list(string)` | required | VNet CIDR blocks |
| `subnets` | `map(object)` | `{}` | Subnet definitions |
| `private_dns_zones` | `list(string)` | `[]` | DNS zone names to create |
| `tags` | `map(string)` | `{}` | Resource tags |

## Outputs

| Name | Description |
|------|-------------|
| `vnet_id` | VNet resource ID |
| `vnet_name` | VNet name |
| `subnet_ids` | Map of subnet name → resource ID |
| `nsg_ids` | Map of subnet name → NSG resource ID |
| `dns_zone_ids` | Map of DNS zone name → resource ID |
