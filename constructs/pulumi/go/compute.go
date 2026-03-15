package infrapulumi

import (
	"fmt"

	"github.com/nautilus/infra-pulumi-go/policy"
	tfm "github.com/pulumi/pulumi-terraform-module-sdk/go/terraformmodule"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

const aksSource = moduleRepo + "//modules/compute/aks?ref=" + moduleVersion

// NodePoolConfig holds configuration for an additional AKS node pool.
type NodePoolConfig struct {
	VmSize            *string
	NodeCount         *int
	EnableAutoScaling *bool
	MinCount          *int
	MaxCount          *int
	Labels            *map[string]*string
	Taints            *[]*string
}

// AksConfig holds optional configuration overrides for an AKS cluster.
type AksConfig struct {
	KubernetesVersion    *string
	SystemNodeVmSize     *string
	SystemNodeCount      *int
	AdditionalNodePools  *map[string]*NodePoolConfig
	AdminGroupObjectIds  *[]*string
	ServiceCidr          *string
	DnsServiceIp         *string
	ExtraTags            *map[string]*string
}

// AksComponentArgs holds all inputs for AksComponent.
type AksComponentArgs struct {
	Project         *string
	Environment     *string
	ResourceGroup   *string
	Location        *string
	SubnetId        *string
	LogWorkspaceId  *string
	Config          *AksConfig
}

// AksComponent provisions an AKS cluster with Azure CNI, AAD RBAC, and Log Analytics.
//
// Delegates to the platform modules/compute/aks Terraform module via
// Pulumi-Terraform interop. Terraform creates every Azure resource;
// Pulumi reads the outputs.
type AksComponent struct {
	pulumi.ResourceState

	// ClusterId is the resource ID of the managed cluster.
	ClusterId pulumi.StringOutput
	// ClusterName is the name of the managed cluster.
	ClusterName pulumi.StringOutput
	// KubeletIdentityObjectId is the object ID of the kubelet managed identity.
	KubeletIdentityObjectId pulumi.StringOutput
	// ClusterIdentityPrincipalId is the principal ID of the cluster system-assigned identity.
	ClusterIdentityPrincipalId pulumi.StringOutput
}

// NewAksComponent creates a new AksComponent.
func NewAksComponent(
	ctx *pulumi.Context,
	name string,
	args *AksComponentArgs,
	opts ...pulumi.ResourceOption,
) (*AksComponent, error) {
	env := *args.Environment
	if !validEnvironments[env] {
		return nil, fmt.Errorf("environment must be one of [dev, prod, staging], got %q", env)
	}

	comp := &AksComponent{}
	if err := ctx.RegisterComponentResource("nautilus:containerservice:AksComponent", name, comp, opts...); err != nil {
		return nil, err
	}

	cfg := args.Config
	if cfg == nil {
		cfg = &AksConfig{}
	}

	tags := policy.RequiredTags(args.Project, args.Environment, cfg.ExtraTags)

	k8sVersion := "1.29"
	if cfg.KubernetesVersion != nil {
		k8sVersion = *cfg.KubernetesVersion
	}
	sysVmSize := "Standard_D2s_v3"
	if cfg.SystemNodeVmSize != nil {
		sysVmSize = *cfg.SystemNodeVmSize
	}
	sysNodeCount := 3
	if cfg.SystemNodeCount != nil {
		sysNodeCount = *cfg.SystemNodeCount
	}
	serviceCidr := "10.240.0.0/16"
	if cfg.ServiceCidr != nil {
		serviceCidr = *cfg.ServiceCidr
	}
	dnsServiceIp := "10.240.0.10"
	if cfg.DnsServiceIp != nil {
		dnsServiceIp = *cfg.DnsServiceIp
	}

	adminGroupIds := []string{}
	if cfg.AdminGroupObjectIds != nil {
		for _, id := range *cfg.AdminGroupObjectIds {
			adminGroupIds = append(adminGroupIds, *id)
		}
	}

	nodePools := map[string]interface{}{}
	if cfg.AdditionalNodePools != nil {
		for poolName, p := range *cfg.AdditionalNodePools {
			vmSize := "Standard_D4s_v3"
			if p.VmSize != nil { vmSize = *p.VmSize }
			nodeCount := 2
			if p.NodeCount != nil { nodeCount = *p.NodeCount }
			enableAS := false
			if p.EnableAutoScaling != nil { enableAS = *p.EnableAutoScaling }
			minCount := 1
			if p.MinCount != nil { minCount = *p.MinCount }
			maxCount := 10
			if p.MaxCount != nil { maxCount = *p.MaxCount }

			labels := map[string]string{}
			if p.Labels != nil {
				for k, v := range *p.Labels { labels[k] = *v }
			}
			taints := []string{}
			if p.Taints != nil {
				for _, t := range *p.Taints { taints = append(taints, *t) }
			}

			nodePools[poolName] = map[string]interface{}{
				"vm_size":             vmSize,
				"node_count":          nodeCount,
				"enable_auto_scaling": enableAS,
				"min_count":           minCount,
				"max_count":           maxCount,
				"labels":              labels,
				"taints":              taints,
			}
		}
	}

	mod, err := tfm.NewModule(ctx, name+"-aks", &tfm.ModuleArgs{
		Source: pulumi.String(aksSource),
		Variables: pulumi.Map{
			"project":                    pulumi.String(*args.Project),
			"environment":                pulumi.String(*args.Environment),
			"resource_group_name":        pulumi.String(*args.ResourceGroup),
			"location":                   pulumi.String(*args.Location),
			"subnet_id":                  pulumi.String(*args.SubnetId),
			"log_analytics_workspace_id": pulumi.String(*args.LogWorkspaceId),
			"kubernetes_version":         pulumi.String(k8sVersion),
			"system_node_vm_size":        pulumi.String(sysVmSize),
			"system_node_count":          pulumi.Int(sysNodeCount),
			"additional_node_pools":      pulumi.ToMap(nodePools),
			"admin_group_object_ids":     pulumi.ToStringArray(adminGroupIds),
			"service_cidr":               pulumi.String(serviceCidr),
			"dns_service_ip":             pulumi.String(dnsServiceIp),
			"tags":                       pulumi.ToStringMap(*tags),
		},
	}, pulumi.Parent(comp))
	if err != nil {
		return nil, err
	}

	comp.ClusterId                  = mod.GetOutput("cluster_id").(pulumi.StringOutput)
	comp.ClusterName                = mod.GetOutput("cluster_name").(pulumi.StringOutput)
	comp.KubeletIdentityObjectId    = mod.GetOutput("kubelet_identity_object_id").(pulumi.StringOutput)
	comp.ClusterIdentityPrincipalId = mod.GetOutput("cluster_identity_principal_id").(pulumi.StringOutput)

	if err := ctx.RegisterResourceOutputs(comp, pulumi.Map{
		"clusterId":                  comp.ClusterId,
		"clusterName":                comp.ClusterName,
		"kubeletIdentityObjectId":    comp.KubeletIdentityObjectId,
		"clusterIdentityPrincipalId": comp.ClusterIdentityPrincipalId,
	}); err != nil {
		return nil, err
	}

	return comp, nil
}
