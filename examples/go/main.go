// myapp infrastructure stack — Go
// =================================
// Equivalent to cdktf/stacks/myapp_stack.py.
//
// To synthesize:
//
//	go mod tidy
//	ENVIRONMENT=dev DB_ADMIN_PASSWORD=... cdktf synth

package main

import (
	"os"

	"github.com/aws/constructs-go/constructs/v10"
	"github.com/aws/jsii-runtime-go"
	"github.com/hashicorp/terraform-cdk-go/cdktf"
	infra "github.com/k1cka5h/infra-go"
)

func newMyAppStack(scope constructs.Construct, id string) cdktf.TerraformStack {
	environment := os.Getenv("ENVIRONMENT")
	if environment == "" {
		environment = "dev"
	}

	logWorkspaceID := os.Getenv("LOG_WORKSPACE_ID")
	if logWorkspaceID == "" {
		logWorkspaceID = "/subscriptions/00000000-0000-0000-0000-000000000000" +
			"/resourceGroups/platform-monitoring-rg" +
			"/providers/Microsoft.OperationalInsights/workspaces/platform-logs"
	}

	isProd := environment == "prod"

	// ── Base stack ────────────────────────────────────────────────────────────
	// Configures the AzureRM provider and remote state backend automatically.

	stack := infra.NewBaseAzureStack(scope, jsii.String(id), &infra.BaseAzureStackProps{
		Project:     jsii.String("myapp"),
		Environment: jsii.String(environment),
		Location:    jsii.String("eastus"),
	})

	// ── 1. Networking ─────────────────────────────────────────────────────────

	network := infra.NewNetworkConstruct(stack, jsii.String("network"), &infra.NetworkConstructProps{
		Project:       stack.Project(),
		Environment:   stack.Environment(),
		ResourceGroup: jsii.String("myapp-rg"),
		Location:      stack.Location(),
		AddressSpace:  jsii.Strings("10.10.0.0/16"),
		Subnets: &map[string]*infra.SubnetConfig{
			"aks": {
				AddressPrefix:    jsii.String("10.10.0.0/22"),
				ServiceEndpoints: jsii.Strings("Microsoft.ContainerRegistry"),
			},
			"db": {
				AddressPrefix: jsii.String("10.10.8.0/24"),
				Delegation: &infra.SubnetDelegation{
					Name:    jsii.String("postgres"),
					Service: jsii.String("Microsoft.DBforPostgreSQL/flexibleServers"),
					Actions: jsii.Strings(
						"Microsoft.Network/virtualNetworks/subnets/join/action",
					),
				},
			},
		},
		PrivateDnsZones: jsii.Strings("privatelink.postgres.database.azure.com"),
	})

	// ── 2. Database ───────────────────────────────────────────────────────────

	pgSku := jsii.String("GP_Standard_D2s_v3")
	if !isProd {
		pgSku = jsii.String("B_Standard_B1ms")
	}

	db := infra.NewDatabaseConstruct(stack, jsii.String("postgres"), &infra.DatabaseConstructProps{
		Project:       stack.Project(),
		Environment:   stack.Environment(),
		ResourceGroup: jsii.String("myapp-rg"),
		Location:      stack.Location(),
		SubnetId:      (*network.SubnetIds())["db"],
		DnsZoneId:     (*network.DnsZoneIds())["privatelink.postgres.database.azure.com"],
		AdminPassword: jsii.String(os.Getenv("DB_ADMIN_PASSWORD")),
		Config: &infra.PostgresConfig{
			Databases:     jsii.Strings("appdb", "analyticsdb"),
			Sku:           pgSku,
			HaEnabled:     jsii.Bool(isProd),
			ServerConfigs: &map[string]*string{"max_connections": jsii.String("400")},
		},
	})

	// ── 3. Compute ────────────────────────────────────────────────────────────

	systemNodeCount := jsii.Number(1)
	if isProd {
		systemNodeCount = jsii.Number(3)
	}

	cluster := infra.NewAksConstruct(stack, jsii.String("aks"), &infra.AksConstructProps{
		Project:        stack.Project(),
		Environment:    stack.Environment(),
		ResourceGroup:  jsii.String("myapp-rg"),
		Location:       stack.Location(),
		SubnetId:       (*network.SubnetIds())["aks"],
		LogWorkspaceId: jsii.String(logWorkspaceID),
		Config: &infra.AksConfig{
			SystemNodeCount: systemNodeCount,
			AdditionalNodePools: &map[string]*infra.NodePoolConfig{
				"workers": {
					VmSize:            jsii.String("Standard_D8s_v3"),
					EnableAutoScaling: jsii.Bool(true),
					MinCount:          jsii.Number(2),
					MaxCount:          jsii.Number(10),
					Labels:            &map[string]*string{"workload": jsii.String("app")},
				},
			},
		},
	})

	// ── Outputs ───────────────────────────────────────────────────────────────

	cdktf.NewTerraformOutput(stack, jsii.String("db_fqdn"),
		&cdktf.TerraformOutputConfig{Value: db.Fqdn()})

	cdktf.NewTerraformOutput(stack, jsii.String("cluster_id"),
		&cdktf.TerraformOutputConfig{Value: cluster.ClusterId()})

	cdktf.NewTerraformOutput(stack, jsii.String("kubelet_identity_oid"),
		&cdktf.TerraformOutputConfig{Value: cluster.KubeletIdentityObjectId()})

	cdktf.NewTerraformOutput(stack, jsii.String("vnet_id"),
		&cdktf.TerraformOutputConfig{Value: network.VnetId()})

	return stack
}

func main() {
	app := cdktf.NewApp(nil)
	newMyAppStack(app, "myapp-stack")
	app.Synth()
}
