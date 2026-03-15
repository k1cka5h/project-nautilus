package infrapulumi_test

import (
	"testing"

	infrapulumi "github.com/nautilus/infra-pulumi-go"
	"github.com/nautilus/infra-pulumi-go/policy"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// ── policy.RequiredTags ────────────────────────────────────────────────────────

func TestRequiredTags_ContainsMandatoryKeys(t *testing.T) {
	tags := policy.RequiredTags("myapp", "dev", nil)
	if tags["managed_by"] != "pulumi" {
		t.Errorf("expected managed_by=pulumi, got %q", tags["managed_by"])
	}
	if tags["project"] != "myapp" {
		t.Errorf("expected project=myapp, got %q", tags["project"])
	}
	if tags["environment"] != "dev" {
		t.Errorf("expected environment=dev, got %q", tags["environment"])
	}
}

func TestRequiredTags_ExtraCannotOverrideReserved(t *testing.T) {
	extra := map[string]string{
		"managed_by": "manual",
		"team":       "platform",
	}
	tags := policy.RequiredTags("myapp", "prod", extra)
	if tags["managed_by"] != "pulumi" {
		t.Errorf("extra key 'managed_by' should not override required tag, got %q", tags["managed_by"])
	}
	if tags["team"] != "platform" {
		t.Errorf("expected extra tag 'team'='platform', got %q", tags["team"])
	}
}

func TestRequiredTags_ExtraKeysIncluded(t *testing.T) {
	tags := policy.RequiredTags("svc", "staging", map[string]string{"cost_center": "eng"})
	if tags["cost_center"] != "eng" {
		t.Errorf("expected cost_center=eng, got %q", tags["cost_center"])
	}
}

// ── NetworkComponent ───────────────────────────────────────────────────────────

func TestNetworkComponent_InvalidEnvironment(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := infrapulumi.NewNetworkComponent(ctx, "net", &infrapulumi.NetworkComponentArgs{
			Project:       "myapp",
			Environment:   "uat",
			ResourceGroup: "rg",
			Location:      "eastus",
			AddressSpace:  []string{"10.0.0.0/16"},
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", &testMocks{}))

	if err == nil {
		t.Error("expected error for invalid environment 'uat'")
	}
}

func TestNetworkComponent_ValidEnvironment(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := infrapulumi.NewNetworkComponent(ctx, "net", &infrapulumi.NetworkComponentArgs{
			Project:       "myapp",
			Environment:   "dev",
			ResourceGroup: "myapp-dev-rg",
			Location:      "eastus",
			AddressSpace:  []string{"10.10.0.0/16"},
			Subnets: map[string]*infrapulumi.SubnetConfig{
				"aks": {AddressPrefix: "10.10.0.0/22"},
				"db": {
					AddressPrefix: "10.10.8.0/24",
					Delegation: &infrapulumi.SubnetDelegation{
						Name:    "postgres",
						Service: "Microsoft.DBforPostgreSQL/flexibleServers",
						Actions: []string{"Microsoft.Network/virtualNetworks/subnets/join/action"},
					},
				},
			},
			PrivateDnsZones: []string{"privatelink.postgres.database.azure.com"},
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", &testMocks{}))

	if err != nil {
		t.Errorf("unexpected error: %v", err)
	}
}

// ── DatabaseComponent ──────────────────────────────────────────────────────────

func TestDatabaseComponent_InvalidEnvironment(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := infrapulumi.NewDatabaseComponent(ctx, "db", &infrapulumi.DatabaseComponentArgs{
			Project:       "myapp",
			Environment:   "qa",
			ResourceGroup: "rg",
			Location:      "eastus",
			SubnetId:      "sn",
			DnsZoneId:     "dns",
			AdminPassword: "secret",
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", &testMocks{}))

	if err == nil {
		t.Error("expected error for invalid environment 'qa'")
	}
}

func TestDatabaseComponent_HaEnabled(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := infrapulumi.NewDatabaseComponent(ctx, "db", &infrapulumi.DatabaseComponentArgs{
			Project:       "myapp",
			Environment:   "prod",
			ResourceGroup: "myapp-prod-rg",
			Location:      "eastus",
			SubnetId:      "/subscriptions/x/subnets/db",
			DnsZoneId:     "/subscriptions/x/privateDnsZones/postgres",
			AdminPassword: "Hunter2!",
			Postgres: &infrapulumi.PostgresConfig{
				HaEnabled: true,
				Databases: []string{"appdb"},
			},
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", &testMocks{}))

	if err != nil {
		t.Errorf("unexpected error: %v", err)
	}
}

// ── AksComponent ───────────────────────────────────────────────────────────────

func TestAksComponent_InvalidEnvironment(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := infrapulumi.NewAksComponent(ctx, "aks", &infrapulumi.AksComponentArgs{
			Project:        "myapp",
			Environment:    "badenv",
			ResourceGroup:  "rg",
			Location:       "eastus",
			SubnetId:       "sn",
			LogWorkspaceId: "ws",
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", &testMocks{}))

	if err == nil {
		t.Error("expected error for invalid environment 'badenv'")
	}
}

func TestAksComponent_WithAdditionalNodePool(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := infrapulumi.NewAksComponent(ctx, "aks", &infrapulumi.AksComponentArgs{
			Project:        "myapp",
			Environment:    "staging",
			ResourceGroup:  "myapp-staging-rg",
			Location:       "eastus",
			SubnetId:       "/subscriptions/x/subnets/aks",
			LogWorkspaceId: "/subscriptions/x/workspaces/logs",
			Aks: &infrapulumi.AksConfig{
				SystemNodeCount: 1,
				AdditionalNodePools: map[string]*infrapulumi.NodePoolConfig{
					"workers": {
						VMSize:            "Standard_D8s_v3",
						EnableAutoScaling: true,
						MinCount:          2,
						MaxCount:          10,
						Labels:            map[string]string{"workload": "app"},
					},
				},
			},
		})
		return err
	}, pulumi.WithMocks("test-project", "test-stack", &testMocks{}))

	if err != nil {
		t.Errorf("unexpected error: %v", err)
	}
}

// ── testMocks ──────────────────────────────────────────────────────────────────

type testMocks struct{}

func (m *testMocks) NewResource(args pulumi.MockResourceArgs) (string, pulumi.PropertyMap, error) {
	outputs := args.Inputs.Copy()
	outputs["id"]   = pulumi.NewStringProperty(args.Name + "_id")
	outputs["name"] = pulumi.NewStringProperty(args.Name)
	outputs["fullyQualifiedDomainName"] = pulumi.NewStringProperty(args.Name + ".postgres.database.azure.com")
	return args.Name + "_id", outputs, nil
}

func (m *testMocks) Call(args pulumi.MockCallArgs) (pulumi.PropertyMap, error) {
	return pulumi.PropertyMap{}, nil
}
