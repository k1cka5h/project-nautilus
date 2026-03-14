using Constructs;
using HashiCorp.Cdktf;
using MyOrg.Infra.Policy;

namespace MyOrg.Infra;

public record NodePoolConfig(
    string VmSize = "Standard_D4s_v3",
    int NodeCount = 2,
    bool EnableAutoScaling = false,
    int MinCount = 1,
    int MaxCount = 10,
    Dictionary<string, string>? Labels = null,
    string[]? Taints = null);

public record AksConfig(
    string KubernetesVersion = "1.29",
    string SystemNodeVmSize = "Standard_D2s_v3",
    int SystemNodeCount = 3,
    Dictionary<string, NodePoolConfig>? AdditionalNodePools = null,
    string[]? AdminGroupObjectIds = null,
    string ServiceCidr = "10.240.0.0/16",
    string DnsServiceIp = "10.240.0.10",
    Dictionary<string, string>? ExtraTags = null);

public record AksConstructProps(
    string Project,
    string Environment,
    string ResourceGroup,
    string Location,
    string SubnetId,
    string LogWorkspaceId,
    AksConfig? Config = null);

/// <summary>
/// Provisions an AKS cluster with Azure CNI, AAD RBAC, and Log Analytics.
/// Wraps modules/compute/aks from the platform Terraform module repo.
/// </summary>
public class AksConstruct : Construct
{
    private readonly TerraformModule _module;

    public AksConstruct(Construct scope, string id, AksConstructProps props)
        : base(scope, id)
    {
        var cfg = props.Config ?? new AksConfig();

        var additionalNodePools = new Dictionary<string, object>();
        foreach (var (name, pool) in cfg.AdditionalNodePools ?? [])
        {
            additionalNodePools[name] = new Dictionary<string, object>
            {
                ["vm_size"]             = pool.VmSize,
                ["node_count"]          = pool.NodeCount,
                ["enable_auto_scaling"] = pool.EnableAutoScaling,
                ["min_count"]           = pool.MinCount,
                ["max_count"]           = pool.MaxCount,
                ["labels"]              = pool.Labels  ?? new Dictionary<string, string>(),
                ["taints"]              = pool.Taints  ?? [],
            };
        }

        _module = new TerraformModule(this, "aks", new TerraformModuleConfig
        {
            Source = "git::ssh://git@github.com/myorg/terraform-modules.git" +
                     "//modules/compute/aks?ref=v1.4.0",
            Variables = new Dictionary<string, object>
            {
                ["project"]                    = props.Project,
                ["environment"]                = props.Environment,
                ["resource_group_name"]        = props.ResourceGroup,
                ["location"]                   = props.Location,
                ["subnet_id"]                  = props.SubnetId,
                ["log_analytics_workspace_id"] = props.LogWorkspaceId,
                ["kubernetes_version"]         = cfg.KubernetesVersion,
                ["system_node_vm_size"]        = cfg.SystemNodeVmSize,
                ["system_node_count"]          = cfg.SystemNodeCount,
                ["additional_node_pools"]      = additionalNodePools,
                ["admin_group_object_ids"]     = cfg.AdminGroupObjectIds ?? [],
                ["service_cidr"]               = cfg.ServiceCidr,
                ["dns_service_ip"]             = cfg.DnsServiceIp,
                ["tags"] = Tagging.RequiredTags(props.Project, props.Environment, cfg.ExtraTags),
            },
        });
    }

    public string ClusterId                  => _module.GetString("cluster_id");
    public string ClusterName                => _module.GetString("cluster_name");
    /// <summary>Assign ACR pull and Key Vault read to this identity.</summary>
    public string KubeletIdentityObjectId    => _module.GetString("kubelet_identity_object_id");
    /// <summary>Assign Network Contributor to this identity.</summary>
    public string ClusterIdentityPrincipalId => _module.GetString("cluster_identity_principal_id");
}
