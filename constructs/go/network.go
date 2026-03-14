package infra

import (
	"github.com/aws/constructs-go/constructs/v10"
	"github.com/aws/jsii-runtime-go"
	"github.com/hashicorp/terraform-cdk-go/cdktf"
	"github.com/k1cka5h/infra-go/policy"
)

const networkModuleSource = "git::ssh://git@github.com/k1cka5h/terraform-modules.git" +
	"//modules/networking?ref=v1.4.0"

// SubnetDelegation represents a service delegation on a subnet.
type SubnetDelegation struct {
	Name    *string
	Service *string
	Actions *[]*string
}

// SubnetConfig defines a single subnet within the VNet.
type SubnetConfig struct {
	AddressPrefix    *string
	ServiceEndpoints *[]*string
	Delegation       *SubnetDelegation
	NsgRules         *[]interface{}
}

// NetworkConstructProps configures a NetworkConstruct.
type NetworkConstructProps struct {
	Project         *string
	Environment     *string
	ResourceGroup   *string
	Location        *string
	AddressSpace    *[]*string
	Subnets         *map[string]*SubnetConfig
	PrivateDnsZones *[]*string
	ExtraTags       *map[string]*string
}

// NetworkConstruct provisions a VNet with subnets, NSGs, and private DNS zones.
// Wraps modules/networking from the platform Terraform module repo.
type NetworkConstruct struct {
	constructs.Construct
	module cdktf.TerraformModule
}

// NewNetworkConstruct creates and returns a NetworkConstruct.
func NewNetworkConstruct(scope constructs.Construct, id *string, props *NetworkConstructProps) *NetworkConstruct {
	c := &NetworkConstruct{Construct: constructs.NewConstruct(scope, id)}

	subnets := map[string]interface{}{}
	if props.Subnets != nil {
		for name, cfg := range *props.Subnets {
			s := map[string]interface{}{
				"address_prefix":    cfg.AddressPrefix,
				"service_endpoints": cfg.ServiceEndpoints,
			}
			if cfg.Delegation != nil {
				s["delegation"] = map[string]interface{}{
					"name":    cfg.Delegation.Name,
					"service": cfg.Delegation.Service,
					"actions": cfg.Delegation.Actions,
				}
			}
			if cfg.NsgRules != nil {
				s["nsg_rules"] = cfg.NsgRules
			}
			subnets[name] = s
		}
	}

	privateDnsZones := &[]*string{}
	if props.PrivateDnsZones != nil {
		privateDnsZones = props.PrivateDnsZones
	}

	c.module = cdktf.NewTerraformModule(c, jsii.String("networking"), &cdktf.TerraformModuleConfig{
		Source: jsii.String(networkModuleSource),
		Variables: &map[string]interface{}{
			"project":             props.Project,
			"environment":         props.Environment,
			"resource_group_name": props.ResourceGroup,
			"location":            props.Location,
			"address_space":       props.AddressSpace,
			"subnets":             subnets,
			"private_dns_zones":   privateDnsZones,
			"tags":                policy.RequiredTags(props.Project, props.Environment, props.ExtraTags),
		},
	})

	return c
}

func (n *NetworkConstruct) VnetId()   *string { return n.module.GetString(jsii.String("vnet_id")) }
func (n *NetworkConstruct) VnetName() *string { return n.module.GetString(jsii.String("vnet_name")) }

// SubnetIds returns a map of subnet name → subnet resource ID.
func (n *NetworkConstruct) SubnetIds() *map[string]*string {
	return n.module.Get(jsii.String("subnet_ids")).(*map[string]*string)
}

// DnsZoneIds returns a map of DNS zone name → resource ID.
func (n *NetworkConstruct) DnsZoneIds() *map[string]*string {
	return n.module.Get(jsii.String("dns_zone_ids")).(*map[string]*string)
}
