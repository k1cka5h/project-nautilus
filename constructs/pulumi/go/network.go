// Package infrapulumi provides Pulumi component wrappers for the Nautilus
// platform Terraform modules. Resource creation is delegated entirely to
// Terraform via Pulumi-Terraform module interop; no Azure resources are
// created directly by this package.
package infrapulumi

import (
	"fmt"

	"github.com/nautilus/infra-pulumi-go/policy"
	tfm "github.com/pulumi/pulumi-terraform-module-sdk/go/terraformmodule"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

const (
	moduleRepo    = "git::ssh://git@github.com/nautilus/terraform-modules.git"
	moduleVersion = "v1.0.0"
	networkSource = moduleRepo + "//modules/networking?ref=" + moduleVersion
)

var validEnvironments = map[string]bool{"dev": true, "staging": true, "prod": true}

// SubnetDelegation holds service delegation configuration for a subnet.
type SubnetDelegation struct {
	Name    *string
	Service *string
	Actions *[]*string
}

// SubnetConfig holds configuration for a single subnet within the VNet.
type SubnetConfig struct {
	AddressPrefix    *string
	ServiceEndpoints *[]*string
	Delegation       *SubnetDelegation
	NsgRules         *[]map[string]interface{}
}

// NetworkComponentArgs holds all inputs for NetworkComponent.
type NetworkComponentArgs struct {
	Project         *string
	Environment     *string
	ResourceGroup   *string
	Location        *string
	AddressSpace    *[]*string
	Subnets         *map[string]*SubnetConfig
	PrivateDnsZones *[]*string
	ExtraTags       *map[string]*string
}

// NetworkComponent provisions a VNet with subnets, NSGs, and private DNS zones.
//
// Delegates to the platform modules/networking Terraform module via
// Pulumi-Terraform interop. Terraform creates every Azure resource;
// Pulumi reads the outputs.
type NetworkComponent struct {
	pulumi.ResourceState

	// VnetId is the resource ID of the VNet.
	VnetId pulumi.StringOutput
	// VnetName is the name of the VNet.
	VnetName pulumi.StringOutput
	// SubnetIds is a map of subnet name → resource ID.
	SubnetIds pulumi.Output
	// DnsZoneIds is a map of DNS zone name → resource ID.
	DnsZoneIds pulumi.Output
}

// NewNetworkComponent creates a new NetworkComponent.
func NewNetworkComponent(
	ctx *pulumi.Context,
	name string,
	args *NetworkComponentArgs,
	opts ...pulumi.ResourceOption,
) (*NetworkComponent, error) {
	env := *args.Environment
	if !validEnvironments[env] {
		return nil, fmt.Errorf("environment must be one of [dev, prod, staging], got %q", env)
	}

	comp := &NetworkComponent{}
	if err := ctx.RegisterComponentResource("nautilus:network:NetworkComponent", name, comp, opts...); err != nil {
		return nil, err
	}

	tags := policy.RequiredTags(args.Project, args.Environment, args.ExtraTags)

	// Serialise subnets to map[string]interface{} for the TF module
	subnetsVar := map[string]interface{}{}
	if args.Subnets != nil {
		for subnetName, cfg := range *args.Subnets {
			entry := map[string]interface{}{"address_prefix": *cfg.AddressPrefix}
			if cfg.ServiceEndpoints != nil {
				entry["service_endpoints"] = *cfg.ServiceEndpoints
			}
			if cfg.Delegation != nil {
				entry["delegation"] = map[string]interface{}{
					"name":    *cfg.Delegation.Name,
					"service": *cfg.Delegation.Service,
					"actions": *cfg.Delegation.Actions,
				}
			}
			if cfg.NsgRules != nil {
				entry["nsg_rules"] = *cfg.NsgRules
			}
			subnetsVar[subnetName] = entry
		}
	}

	privateDnsZones := []string{}
	if args.PrivateDnsZones != nil {
		for _, z := range *args.PrivateDnsZones {
			privateDnsZones = append(privateDnsZones, *z)
		}
	}

	mod, err := tfm.NewModule(ctx, name+"-networking", &tfm.ModuleArgs{
		Source: pulumi.String(networkSource),
		Variables: pulumi.Map{
			"project":             pulumi.String(*args.Project),
			"environment":         pulumi.String(*args.Environment),
			"resource_group_name": pulumi.String(*args.ResourceGroup),
			"location":            pulumi.String(*args.Location),
			"address_space":       pulumi.ToStringArray(*args.AddressSpace),
			"subnets":             pulumi.ToMap(subnetsVar),
			"private_dns_zones":   pulumi.ToStringArray(privateDnsZones),
			"tags":                pulumi.ToStringMap(*tags),
		},
	}, pulumi.Parent(comp))
	if err != nil {
		return nil, err
	}

	comp.VnetId     = mod.GetOutput("vnet_id").(pulumi.StringOutput)
	comp.VnetName   = mod.GetOutput("vnet_name").(pulumi.StringOutput)
	comp.SubnetIds  = mod.GetOutput("subnet_ids")
	comp.DnsZoneIds = mod.GetOutput("dns_zone_ids")

	if err := ctx.RegisterResourceOutputs(comp, pulumi.Map{
		"vnetId":     comp.VnetId,
		"vnetName":   comp.VnetName,
		"subnetIds":  comp.SubnetIds,
		"dnsZoneIds": comp.DnsZoneIds,
	}); err != nil {
		return nil, err
	}

	return comp, nil
}
