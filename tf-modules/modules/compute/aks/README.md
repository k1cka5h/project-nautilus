# modules/compute/aks

Provisions an AKS cluster with:
- Azure CNI networking
- System-assigned managed identity
- AAD RBAC integration
- Log Analytics monitoring (OMS agent)
- Optional additional node pools with auto-scaling

The system node pool is tainted `CriticalAddonsOnly=true:NoSchedule` so application
workloads cannot schedule on it. Add a dedicated node pool for application pods.

## Usage (via CDKTF construct)

```python
from k1cka5h_infra import AksConstruct, AksConfig, NodePoolConfig

cluster = AksConstruct(
    self, "aks",
    project=self.project,
    environment=self.environment,
    resource_group="myapp-rg",
    location=self.location,
    subnet_id=network.subnet_ids["aks"],
    log_workspace_id=os.environ["LOG_WORKSPACE_ID"],
    config=AksConfig(
        system_node_count=3 if self.environment == "prod" else 1,
        additional_node_pools={
            "workers": NodePoolConfig(
                vm_size="Standard_D8s_v3",
                enable_auto_scaling=True,
                min_count=2,
                max_count=10,
            )
        },
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
| `subnet_id` | `string` | required | Subnet for node pool VMs |
| `log_analytics_workspace_id` | `string` | required | Log Analytics workspace ID |
| `kubernetes_version` | `string` | `"1.29"` | Kubernetes version |
| `system_node_vm_size` | `string` | `Standard_D2s_v3` | System pool VM size |
| `system_node_count` | `number` | `3` | System pool node count |
| `additional_node_pools` | `map(object)` | `{}` | Extra node pools |
| `admin_group_object_ids` | `list(string)` | `[]` | AAD cluster-admin group IDs |
| `service_cidr` | `string` | `10.240.0.0/16` | Kubernetes service CIDR |
| `dns_service_ip` | `string` | `10.240.0.10` | kube-dns IP |
| `tags` | `map(string)` | `{}` | Resource tags |

## Outputs

| Name | Description |
|------|-------------|
| `cluster_id` | AKS cluster resource ID |
| `cluster_name` | Cluster name |
| `kube_config_raw` | kubeconfig (sensitive) |
| `kubelet_identity_object_id` | Assign ACR pull / Key Vault read here |
| `cluster_identity_principal_id` | Assign Network Contributor here |
| `node_resource_group` | MC_ resource group for node VMs |
