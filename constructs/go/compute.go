package infra

import (
	"github.com/aws/constructs-go/constructs/v10"
	"github.com/aws/jsii-runtime-go"
	"github.com/hashicorp/terraform-cdk-go/cdktf"
	"github.com/k1cka5h/infra-go/policy"
)

const aksModuleSource = "git::ssh://git@github.com/k1cka5h/terraform-modules.git" +
	"//modules/compute/aks?ref=v1.4.0"

// NodePoolConfig defines an additional AKS node pool.
type NodePoolConfig struct {
	VMSize     *string
	NodeCount  *float64
	MinCount   *float64
	MaxCount   *float64
	Taints     *[]*string
	Labels     *map[string]*string
}

// AksConfig configures the AKS cluster.
type AksConfig struct {
	KubernetesVersion   *string
	SystemNodeCount     *float64
	SystemVMSize        *string
	AdditionalNodePools *map[string]*NodePoolConfig
}

// AksConstructProps configures an AksConstruct.
type AksConstructProps struct {
	Project       *string
	Environment   *string
	ResourceGroup *string
	Location      *string
	SubnetId      *string
	LogWorkspaceId *string
	Aks           *AksConfig
	ExtraTags     *map[string]*string
}

// AksConstruct provisions an AKS cluster with Azure CNI and AAD RBAC.
// Wraps modules/compute/aks from the platform Terraform module repo.
type AksConstruct struct {
	constructs.Construct
	module cdktf.TerraformModule
}

// NewAksConstruct creates and returns an AksConstruct.
func NewAksConstruct(scope constructs.Construct, id *string, props *AksConstructProps) *AksConstruct {
	c := &AksConstruct{Construct: constructs.NewConstruct(scope, id)}

	aks := props.Aks
	if aks == nil {
		aks = &AksConfig{}
	}

	k8sVersion := jsii.String("1.29")
	if aks.KubernetesVersion != nil {
		k8sVersion = aks.KubernetesVersion
	}

	systemCount := jsii.Number(3)
	if aks.SystemNodeCount != nil {
		systemCount = aks.SystemNodeCount
	}

	systemVMSize := jsii.String("Standard_D4s_v3")
	if aks.SystemVMSize != nil {
		systemVMSize = aks.SystemVMSize
	}

	additionalPools := map[string]interface{}{}
	if aks.AdditionalNodePools != nil {
		for name, pool := range *aks.AdditionalNodePools {
			p := map[string]interface{}{
				"vm_size":    pool.VMSize,
				"node_count": pool.NodeCount,
				"min_count":  pool.MinCount,
				"max_count":  pool.MaxCount,
			}
			if pool.Taints != nil {
				p["node_taints"] = pool.Taints
			}
			if pool.Labels != nil {
				p["node_labels"] = pool.Labels
			}
			additionalPools[name] = p
		}
	}

	c.module = cdktf.NewTerraformModule(c, jsii.String("aks"), &cdktf.TerraformModuleConfig{
		Source: jsii.String(aksModuleSource),
		Variables: &map[string]interface{}{
			"project":               props.Project,
			"environment":          props.Environment,
			"resource_group_name":  props.ResourceGroup,
			"location":             props.Location,
			"subnet_id":            props.SubnetId,
			"log_analytics_workspace_id": props.LogWorkspaceId,
			"kubernetes_version":   k8sVersion,
			"system_node_count":    systemCount,
			"system_vm_size":       systemVMSize,
			"additional_node_pools": additionalPools,
			"tags":                 policy.RequiredTags(props.Project, props.Environment, props.ExtraTags),
		},
	})

	return c
}

func (a *AksConstruct) ClusterId()                *string { return a.module.GetString(jsii.String("cluster_id")) }
func (a *AksConstruct) KubeletIdentityObjectId()  *string { return a.module.GetString(jsii.String("kubelet_identity_object_id")) }
