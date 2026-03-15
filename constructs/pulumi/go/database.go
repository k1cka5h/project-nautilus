package infrapulumi

import (
	"fmt"

	"github.com/nautilus/infra-pulumi-go/policy"
	tfm "github.com/pulumi/pulumi-terraform-module-sdk/go/terraformmodule"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

const postgresSource = moduleRepo + "//modules/database/postgres?ref=" + moduleVersion

// PostgresConfig holds optional configuration overrides for a PostgreSQL Flexible Server.
type PostgresConfig struct {
	Databases      *[]*string
	Sku            *string
	StorageMb      *int
	PgVersion      *string
	HaEnabled      *bool
	GeoRedundant   *bool
	ServerConfigs  *map[string]*string
	ExtraTags      *map[string]*string
}

// DatabaseComponentArgs holds all inputs for DatabaseComponent.
type DatabaseComponentArgs struct {
	Project       *string
	Environment   *string
	ResourceGroup *string
	Location      *string
	SubnetId      *string
	DnsZoneId     *string
	AdminPassword *string
	Config        *PostgresConfig
	ExtraTags     *map[string]*string
}

// DatabaseComponent provisions a PostgreSQL Flexible Server with private VNet access.
//
// Delegates to the platform modules/database/postgres Terraform module via
// Pulumi-Terraform interop. Terraform creates every Azure resource;
// Pulumi reads the outputs.
type DatabaseComponent struct {
	pulumi.ResourceState

	// Fqdn is the fully-qualified domain name for client connections.
	Fqdn pulumi.StringOutput
	// ServerId is the resource ID of the flexible server.
	ServerId pulumi.StringOutput
	// ServerName is the name of the flexible server.
	ServerName pulumi.StringOutput
}

// NewDatabaseComponent creates a new DatabaseComponent.
func NewDatabaseComponent(
	ctx *pulumi.Context,
	name string,
	args *DatabaseComponentArgs,
	opts ...pulumi.ResourceOption,
) (*DatabaseComponent, error) {
	env := *args.Environment
	if !validEnvironments[env] {
		return nil, fmt.Errorf("environment must be one of [dev, prod, staging], got %q", env)
	}

	comp := &DatabaseComponent{}
	if err := ctx.RegisterComponentResource("nautilus:database:DatabaseComponent", name, comp, opts...); err != nil {
		return nil, err
	}

	cfg := args.Config
	if cfg == nil {
		cfg = &PostgresConfig{}
	}

	extraTags := args.ExtraTags
	if cfg.ExtraTags != nil {
		extraTags = cfg.ExtraTags
	}
	tags := policy.RequiredTags(args.Project, args.Environment, extraTags)

	sku := "GP_Standard_D2s_v3"
	if cfg.Sku != nil {
		sku = *cfg.Sku
	}
	storageMb := 32768
	if cfg.StorageMb != nil {
		storageMb = *cfg.StorageMb
	}
	pgVersion := "15"
	if cfg.PgVersion != nil {
		pgVersion = *cfg.PgVersion
	}
	haMode := "Disabled"
	if cfg.HaEnabled != nil && *cfg.HaEnabled {
		haMode = "ZoneRedundant"
	}
	geoRedundant := false
	if cfg.GeoRedundant != nil {
		geoRedundant = *cfg.GeoRedundant
	}

	databases := []string{}
	if cfg.Databases != nil {
		for _, d := range *cfg.Databases {
			databases = append(databases, *d)
		}
	}

	serverConfigs := map[string]string{}
	if cfg.ServerConfigs != nil {
		for k, v := range *cfg.ServerConfigs {
			serverConfigs[k] = *v
		}
	}

	mod, err := tfm.NewModule(ctx, name+"-postgres", &tfm.ModuleArgs{
		Source: pulumi.String(postgresSource),
		Variables: pulumi.Map{
			"project":                 pulumi.String(*args.Project),
			"environment":             pulumi.String(*args.Environment),
			"resource_group_name":     pulumi.String(*args.ResourceGroup),
			"location":                pulumi.String(*args.Location),
			"delegated_subnet_id":     pulumi.String(*args.SubnetId),
			"private_dns_zone_id":     pulumi.String(*args.DnsZoneId),
			"administrator_password":  pulumi.String(*args.AdminPassword),
			"databases":               pulumi.ToStringArray(databases),
			"sku_name":                pulumi.String(sku),
			"storage_mb":              pulumi.Int(storageMb),
			"pg_version":              pulumi.String(pgVersion),
			"high_availability_mode":  pulumi.String(haMode),
			"geo_redundant_backup":    pulumi.Bool(geoRedundant),
			"server_configurations":   pulumi.ToStringMap(serverConfigs),
			"tags":                    pulumi.ToStringMap(*tags),
		},
	}, pulumi.Parent(comp))
	if err != nil {
		return nil, err
	}

	comp.Fqdn       = mod.GetOutput("fqdn").(pulumi.StringOutput)
	comp.ServerId   = mod.GetOutput("server_id").(pulumi.StringOutput)
	comp.ServerName = mod.GetOutput("server_name").(pulumi.StringOutput)

	if err := ctx.RegisterResourceOutputs(comp, pulumi.Map{
		"fqdn":       comp.Fqdn,
		"serverId":   comp.ServerId,
		"serverName": comp.ServerName,
	}); err != nil {
		return nil, err
	}

	return comp, nil
}
