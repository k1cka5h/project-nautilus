package infra

import (
	"github.com/aws/constructs-go/constructs/v10"
	"github.com/aws/jsii-runtime-go"
	"github.com/hashicorp/terraform-cdk-go/cdktf"
	"github.com/k1cka5h/infra-go/policy"
)

const databaseModuleSource = "git::ssh://git@github.com/k1cka5h/terraform-modules.git" +
	"//modules/database/postgres?ref=v1.4.0"

// PostgresConfig configures the PostgreSQL Flexible Server.
type PostgresConfig struct {
	SkuName            *string
	StorageGb          *float64
	PostgresVersion    *string
	HaEnabled          *bool
	GeoRedundantBackup *bool
	Databases          *[]*string
}

// DatabaseConstructProps configures a DatabaseConstruct.
type DatabaseConstructProps struct {
	Project       *string
	Environment   *string
	ResourceGroup *string
	Location      *string
	SubnetId      *string
	DnsZoneId     *string
	Postgres      *PostgresConfig
	ExtraTags     *map[string]*string
}

// DatabaseConstruct provisions a PostgreSQL Flexible Server.
// Wraps modules/database/postgres from the platform Terraform module repo.
type DatabaseConstruct struct {
	constructs.Construct
	module cdktf.TerraformModule
}

// NewDatabaseConstruct creates and returns a DatabaseConstruct.
func NewDatabaseConstruct(scope constructs.Construct, id *string, props *DatabaseConstructProps) *DatabaseConstruct {
	c := &DatabaseConstruct{Construct: constructs.NewConstruct(scope, id)}

	pg := props.Postgres
	if pg == nil {
		pg = &PostgresConfig{}
	}

	skuName := jsii.String("GP_Standard_D2s_v3")
	if pg.SkuName != nil {
		skuName = pg.SkuName
	}

	storageGb := jsii.Number(32)
	if pg.StorageGb != nil {
		storageGb = pg.StorageGb
	}

	pgVersion := jsii.String("15")
	if pg.PostgresVersion != nil {
		pgVersion = pg.PostgresVersion
	}

	haMode := jsii.String("Disabled")
	if pg.HaEnabled != nil && *pg.HaEnabled {
		haMode = jsii.String("ZoneRedundant")
	}

	geoBackup := jsii.Bool(false)
	if pg.GeoRedundantBackup != nil {
		geoBackup = pg.GeoRedundantBackup
	}

	databases := &[]*string{}
	if pg.Databases != nil {
		databases = pg.Databases
	}

	c.module = cdktf.NewTerraformModule(c, jsii.String("database"), &cdktf.TerraformModuleConfig{
		Source: jsii.String(databaseModuleSource),
		Variables: &map[string]interface{}{
			"project":              props.Project,
			"environment":         props.Environment,
			"resource_group_name": props.ResourceGroup,
			"location":            props.Location,
			"subnet_id":           props.SubnetId,
			"private_dns_zone_id": props.DnsZoneId,
			"sku_name":            skuName,
			"storage_mb":          storageGb,
			"postgres_version":    pgVersion,
			"high_availability_mode": haMode,
			"geo_redundant_backup": geoBackup,
			"databases":           databases,
			"tags":                policy.RequiredTags(props.Project, props.Environment, props.ExtraTags),
		},
	})

	return c
}

func (d *DatabaseConstruct) Fqdn()     *string { return d.module.GetString(jsii.String("fqdn")) }
func (d *DatabaseConstruct) ServerId() *string { return d.module.GetString(jsii.String("server_id")) }
