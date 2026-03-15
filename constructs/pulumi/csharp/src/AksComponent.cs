using System.Collections.Generic;
using System.Linq;
using Pulumi;
using Pulumi.TerraformModule;
using Nautilus.Infra.Pulumi.Policy;

namespace Nautilus.Infra.Pulumi;

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

public record AksComponentArgs(
    string Project,
    string Environment,
    string ResourceGroup,
    string Location,
    string SubnetId,
    string LogWorkspaceId,
    AksConfig? Config = null);

/// <summary>
/// Provisions an AKS cluster with Azure CNI, AAD RBAC, and Log Analytics.
///
/// Delegates to the platform <c>modules/compute/aks</c> Terraform module via
/// Pulumi-Terraform interop. Terraform creates every Azure resource;
/// Pulumi reads the outputs.
/// </summary>
public class AksComponent : ComponentResource
{
    private const string ModuleRepo    = "git::ssh://git@github.com/nautilus/terraform-modules.git";
    private const string ModuleVersion = "v1.0.0";
    private const string AksSource     = $"{ModuleRepo}//modules/compute/aks?ref={ModuleVersion}";

    private static readonly HashSet<string> ValidEnvironments = ["dev", "staging", "prod"];

    /// <summary>Resource ID of the managed cluster.</summary>
    public Output<string> ClusterId { get; }
    /// <summary>Name of the managed cluster.</summary>
    public Output<string> ClusterName { get; }
    /// <summary>Object ID of the kubelet managed identity.</summary>
    public Output<string> KubeletIdentityObjectId { get; }
    /// <summary>Principal ID of the cluster system-assigned identity.</summary>
    public Output<string> ClusterIdentityPrincipalId { get; }

    public AksComponent(string name, AksComponentArgs args, ComponentResourceOptions? opts = null)
        : base("nautilus:containerservice:AksComponent", name, opts)
    {
        if (!ValidEnvironments.Contains(args.Environment))
            throw new System.ArgumentException(
                $"environment must be one of [{string.Join(", ", ValidEnvironments.OrderBy(e => e))}], got \"{args.Environment}\"");

        var cfg  = args.Config ?? new AksConfig();
        var tags = Tagging.RequiredTags(args.Project, args.Environment, cfg.ExtraTags);

        var nodePools = new Dictionary<string, object>();
        foreach (var (poolName, pool) in cfg.AdditionalNodePools ?? new())
        {
            nodePools[poolName] = new Dictionary<string, object>
            {
                ["vm_size"]             = pool.VmSize,
                ["node_count"]          = pool.NodeCount,
                ["enable_auto_scaling"] = pool.EnableAutoScaling,
                ["min_count"]           = pool.MinCount,
                ["max_count"]           = pool.MaxCount,
                ["labels"]              = pool.Labels ?? new(),
                ["taints"]              = pool.Taints ?? [],
            };
        }

        var mod = new Module($"{name}-aks", new ModuleArgs
        {
            Source = AksSource,
            Variables =
            {
                ["project"]                     = args.Project,
                ["environment"]                 = args.Environment,
                ["resource_group_name"]         = args.ResourceGroup,
                ["location"]                    = args.Location,
                ["subnet_id"]                   = args.SubnetId,
                ["log_analytics_workspace_id"]  = args.LogWorkspaceId,
                ["kubernetes_version"]          = cfg.KubernetesVersion,
                ["system_node_vm_size"]         = cfg.SystemNodeVmSize,
                ["system_node_count"]           = cfg.SystemNodeCount,
                ["additional_node_pools"]       = nodePools,
                ["admin_group_object_ids"]      = cfg.AdminGroupObjectIds ?? [],
                ["service_cidr"]                = cfg.ServiceCidr,
                ["dns_service_ip"]              = cfg.DnsServiceIp,
                ["tags"]                        = tags,
            },
        }, new CustomResourceOptions { Parent = this });

        ClusterId                  = mod.GetOutput("cluster_id");
        ClusterName                = mod.GetOutput("cluster_name");
        KubeletIdentityObjectId    = mod.GetOutput("kubelet_identity_object_id");
        ClusterIdentityPrincipalId = mod.GetOutput("cluster_identity_principal_id");

        RegisterOutputs(new Dictionary<string, object?>
        {
            ["clusterId"]                  = ClusterId,
            ["clusterName"]                = ClusterName,
            ["kubeletIdentityObjectId"]    = KubeletIdentityObjectId,
            ["clusterIdentityPrincipalId"] = ClusterIdentityPrincipalId,
        });
    }
}
