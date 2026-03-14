package infra_test

import (
	"encoding/json"
	"testing"

	infra "github.com/k1cka5h/infra-go"
	"github.com/aws/constructs-go/constructs/v10"
	"github.com/aws/jsii-runtime-go"
	"github.com/hashicorp/terraform-cdk-go/cdktf"
)

// synth synthesizes a stack to JSON and returns the parsed map.
func synth(t *testing.T, fn func(scope constructs.Construct)) map[string]interface{} {
	t.Helper()
	app := cdktf.NewApp(nil)
	stack := cdktf.NewTerraformStack(app, jsii.String("test"))
	fn(stack)
	out := cdktf.Testing_SynthScope(stack)
	var result map[string]interface{}
	if err := json.Unmarshal([]byte(*out), &result); err != nil {
		t.Fatalf("failed to parse synth output: %v", err)
	}
	return result
}

func TestBaseAzureStack_DefaultEnvironment(t *testing.T) {
	app := cdktf.NewApp(nil)
	stack := infra.NewBaseAzureStack(app, jsii.String("test"), &infra.BaseAzureStackProps{
		Project: jsii.String("myapp"),
	})
	if *stack.Environment() != "dev" {
		t.Errorf("expected default environment 'dev', got %q", *stack.Environment())
	}
	if *stack.Location() != "eastus" {
		t.Errorf("expected default location 'eastus', got %q", *stack.Location())
	}
}

func TestBaseAzureStack_InvalidEnvironment(t *testing.T) {
	defer func() {
		if r := recover(); r == nil {
			t.Error("expected panic for invalid environment")
		}
	}()
	app := cdktf.NewApp(nil)
	infra.NewBaseAzureStack(app, jsii.String("test"), &infra.BaseAzureStackProps{
		Project:     jsii.String("myapp"),
		Environment: jsii.String("badenv"),
	})
}

func TestNetworkConstruct_ModuleSource(t *testing.T) {
	result := synth(t, func(scope constructs.Construct) {
		infra.NewNetworkConstruct(scope, jsii.String("net"), &infra.NetworkConstructProps{
			Project:      jsii.String("myapp"),
			Environment:  jsii.String("dev"),
			ResourceGroup: jsii.String("myapp-dev-rg"),
			Location:     jsii.String("eastus"),
			AddressSpace: &[]*string{jsii.String("10.0.0.0/16")},
		})
	})

	modules, ok := result["module"].(map[string]interface{})
	if !ok {
		t.Fatal("no 'module' key in synth output")
	}
	net, ok := modules["networking"].(map[string]interface{})
	if !ok {
		t.Fatal("no 'networking' module in synth output")
	}
	src, _ := net["source"].(string)
	const wantSrc = "git::ssh://git@github.com/k1cka5h/terraform-modules.git//modules/networking?ref=v1.4.0"
	if src != wantSrc {
		t.Errorf("module source = %q, want %q", src, wantSrc)
	}
}

func TestNetworkConstruct_RequiredTags(t *testing.T) {
	result := synth(t, func(scope constructs.Construct) {
		infra.NewNetworkConstruct(scope, jsii.String("net"), &infra.NetworkConstructProps{
			Project:      jsii.String("myapp"),
			Environment:  jsii.String("staging"),
			ResourceGroup: jsii.String("myapp-staging-rg"),
			Location:     jsii.String("eastus"),
			AddressSpace: &[]*string{jsii.String("10.0.0.0/16")},
		})
	})

	modules := result["module"].(map[string]interface{})
	vars := modules["networking"].(map[string]interface{})
	tags := vars["tags"].(map[string]interface{})

	if tags["managed_by"] != "terraform" {
		t.Errorf("expected managed_by=terraform, got %v", tags["managed_by"])
	}
	if tags["project"] != "myapp" {
		t.Errorf("expected project=myapp, got %v", tags["project"])
	}
	if tags["environment"] != "staging" {
		t.Errorf("expected environment=staging, got %v", tags["environment"])
	}
}

func TestDatabaseConstruct_ModuleSource(t *testing.T) {
	result := synth(t, func(scope constructs.Construct) {
		infra.NewDatabaseConstruct(scope, jsii.String("db"), &infra.DatabaseConstructProps{
			Project:       jsii.String("myapp"),
			Environment:   jsii.String("prod"),
			ResourceGroup: jsii.String("myapp-prod-rg"),
			Location:      jsii.String("eastus"),
			SubnetId:      jsii.String("/subscriptions/.../subnets/db"),
			DnsZoneId:     jsii.String("/subscriptions/.../privateDnsZones/postgres.database.azure.com"),
		})
	})

	modules := result["module"].(map[string]interface{})
	db := modules["database"].(map[string]interface{})
	src, _ := db["source"].(string)
	const wantSrc = "git::ssh://git@github.com/k1cka5h/terraform-modules.git//modules/database/postgres?ref=v1.4.0"
	if src != wantSrc {
		t.Errorf("module source = %q, want %q", src, wantSrc)
	}
}

func TestDatabaseConstruct_HaEnabled(t *testing.T) {
	result := synth(t, func(scope constructs.Construct) {
		infra.NewDatabaseConstruct(scope, jsii.String("db"), &infra.DatabaseConstructProps{
			Project:       jsii.String("myapp"),
			Environment:   jsii.String("prod"),
			ResourceGroup: jsii.String("myapp-prod-rg"),
			Location:      jsii.String("eastus"),
			SubnetId:      jsii.String("/subscriptions/.../subnets/db"),
			DnsZoneId:     jsii.String("/subscriptions/.../privateDnsZones/postgres.database.azure.com"),
			Postgres: &infra.PostgresConfig{
				HaEnabled: jsii.Bool(true),
			},
		})
	})

	modules := result["module"].(map[string]interface{})
	db := modules["database"].(map[string]interface{})
	if db["high_availability_mode"] != "ZoneRedundant" {
		t.Errorf("expected high_availability_mode=ZoneRedundant, got %v", db["high_availability_mode"])
	}
}

func TestAksConstruct_ModuleSource(t *testing.T) {
	result := synth(t, func(scope constructs.Construct) {
		infra.NewAksConstruct(scope, jsii.String("aks"), &infra.AksConstructProps{
			Project:       jsii.String("myapp"),
			Environment:   jsii.String("dev"),
			ResourceGroup: jsii.String("myapp-dev-rg"),
			Location:      jsii.String("eastus"),
			SubnetId:      jsii.String("/subscriptions/.../subnets/aks"),
		})
	})

	modules := result["module"].(map[string]interface{})
	aks := modules["aks"].(map[string]interface{})
	src, _ := aks["source"].(string)
	const wantSrc = "git::ssh://git@github.com/k1cka5h/terraform-modules.git//modules/compute/aks?ref=v1.4.0"
	if src != wantSrc {
		t.Errorf("module source = %q, want %q", src, wantSrc)
	}
}

func TestRequiredTags_ExtraCannotOverrideReserved(t *testing.T) {
	extra := map[string]*string{
		"managed_by": jsii.String("manual"), // must be overridden
		"team":       jsii.String("platform"),
	}
	tags := *infra.RequiredTags(jsii.String("myapp"), jsii.String("prod"), &extra)

	if *tags["managed_by"] != "terraform" {
		t.Errorf("extra key 'managed_by' should not override required tag, got %q", *tags["managed_by"])
	}
	if *tags["team"] != "platform" {
		t.Errorf("expected extra tag 'team'='platform', got %q", *tags["team"])
	}
}
