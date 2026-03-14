import { Testing, TerraformStack } from "cdktf";
import { Construct } from "constructs";
import {
  BaseAzureStack,
  NetworkConstruct,
  DatabaseConstruct,
  AksConstruct,
} from "../src/index";

class TestStack extends TerraformStack {
  constructor(scope: Construct) {
    super(scope, "test-stack");
  }
}

// ── NetworkConstruct ──────────────────────────────────────────────────────────

describe("NetworkConstruct", () => {
  let synth: Record<string, any>;

  beforeEach(() => {
    const app   = Testing.app();
    const stack = new TestStack(app);
    new NetworkConstruct(stack, "net", {
      project: "myapp", environment: "dev",
      resourceGroup: "myapp-rg", location: "eastus",
      addressSpace: ["10.10.0.0/16"],
      subnets: {
        aks: { addressPrefix: "10.10.0.0/22", serviceEndpoints: ["Microsoft.ContainerRegistry"] },
        db:  {
          addressPrefix: "10.10.8.0/24",
          delegation: {
            name:    "postgres",
            service: "Microsoft.DBforPostgreSQL/flexibleServers",
            actions: ["Microsoft.Network/virtualNetworks/subnets/join/action"],
          },
        },
      },
      privateDnsZones: ["privatelink.postgres.database.azure.com"],
    });
    synth = JSON.parse(Testing.synth(stack));
  });

  it("pins the module source to a ref tag", () => {
    const modules = synth["module"];
    const key = Object.keys(modules).find(k => k.includes("networking"))!;
    expect(modules[key]["source"]).toContain("ref=v");
  });

  it("injects required tags", () => {
    const modules = synth["module"];
    const key = Object.keys(modules).find(k => k.includes("networking"))!;
    const tags = modules[key]["tags"];
    expect(tags["managed_by"]).toBe("terraform");
    expect(tags["project"]).toBe("myapp");
    expect(tags["environment"]).toBe("dev");
  });

  it("serializes subnet delegation", () => {
    const modules = synth["module"];
    const key = Object.keys(modules).find(k => k.includes("networking"))!;
    expect(modules[key]["subnets"]["db"]["delegation"]["service"])
      .toBe("Microsoft.DBforPostgreSQL/flexibleServers");
  });

  it("throws on invalid environment", () => {
    const app2   = Testing.app();
    const stack2 = new TestStack(app2);
    expect(() =>
      new NetworkConstruct(stack2, "net2", {
        project: "myapp", environment: "uat",
        resourceGroup: "rg", location: "eastus",
        addressSpace: ["10.0.0.0/16"],
      })
    ).toThrow(/environment must be/);
  });
});

// ── DatabaseConstruct ─────────────────────────────────────────────────────────

describe("DatabaseConstruct", () => {
  let synth: Record<string, any>;

  beforeEach(() => {
    const app   = Testing.app();
    const stack = new TestStack(app);
    new DatabaseConstruct(stack, "db", {
      project: "myapp", environment: "prod",
      resourceGroup: "myapp-rg", location: "eastus",
      subnetId: "subnet-id", dnsZoneId: "dns-zone-id",
      adminPassword: "Hunter2!",
      config: { databases: ["appdb"], haEnabled: true },
    });
    synth = JSON.parse(Testing.synth(stack));
  });

  it("sets ZoneRedundant HA mode when haEnabled", () => {
    const modules = synth["module"];
    const key = Object.keys(modules).find(k => k.includes("postgres"))!;
    expect(modules[key]["high_availability_mode"]).toBe("ZoneRedundant");
  });

  it("forwards the admin password", () => {
    const modules = synth["module"];
    const key = Object.keys(modules).find(k => k.includes("postgres"))!;
    expect(modules[key]).toHaveProperty("administrator_password");
  });
});

// ── AksConstruct ──────────────────────────────────────────────────────────────

describe("AksConstruct", () => {
  let synth: Record<string, any>;

  beforeEach(() => {
    const app   = Testing.app();
    const stack = new TestStack(app);
    new AksConstruct(stack, "aks", {
      project: "myapp", environment: "staging",
      resourceGroup: "myapp-rg", location: "eastus",
      subnetId: "subnet-id",
      logWorkspaceId: "/subscriptions/x/workspaces/logs",
      config: {
        systemNodeCount: 1,
        additionalNodePools: {
          workers: { vmSize: "Standard_D8s_v3", enableAutoScaling: true, minCount: 2, maxCount: 10 },
        },
      },
    });
    synth = JSON.parse(Testing.synth(stack));
  });

  it("pins the module source to a ref tag", () => {
    const modules = synth["module"];
    const key = Object.keys(modules).find(k => k.includes("aks"))!;
    expect(modules[key]["source"]).toContain("ref=v");
  });

  it("forwards additional node pools", () => {
    const modules = synth["module"];
    const key = Object.keys(modules).find(k => k.includes("aks"))!;
    expect(modules[key]["additional_node_pools"]["workers"]["enable_auto_scaling"]).toBe(true);
  });
});

// ── BaseAzureStack ────────────────────────────────────────────────────────────

describe("BaseAzureStack", () => {
  it("sets the correct state key", () => {
    const app   = Testing.app();
    const stack = new BaseAzureStack(app, "base", { project: "proj", environment: "dev" });
    const synth = JSON.parse(Testing.synth(stack));
    expect(synth["terraform"]["backend"]["azurerm"]["key"]).toBe("proj/dev/terraform.tfstate");
  });

  it("throws on invalid environment", () => {
    const app = Testing.app();
    expect(() => new BaseAzureStack(app, "bad", { project: "p", environment: "qa" }))
      .toThrow(/environment must be/);
  });
});
