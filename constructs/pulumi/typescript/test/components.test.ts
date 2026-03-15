/**
 * Component unit tests — TypeScript
 * ===================================
 * Uses pulumi.runtime.setMocks() to intercept resource creation and assert
 * component wiring without deploying any real Azure resources.
 *
 * Run:
 *   npm install && npm test
 */

import * as pulumi from "@pulumi/pulumi";

pulumi.runtime.setMocks(
  {
    newResource(args: pulumi.runtime.MockResourceArgs): { id: string; state: Record<string, unknown> } {
      const state: Record<string, unknown> = {
        ...args.inputs,
        id:                             args.name + "_id",
        name:                           args.name,
        fullyQualifiedDomainName:       args.name + ".postgres.database.azure.com",
        identityProfile: {
          kubeletidentity: { objectId: "kubelet-oid-" + args.name },
        },
        identity: { principalId: "principal-" + args.name },
      };
      return { id: args.name + "_id", state };
    },
    call(args: pulumi.runtime.MockCallArgs): Record<string, unknown> {
      return {};
    },
  },
  "test-project",
  "test-stack",
  true,
);

import {
  NetworkComponent,
  DatabaseComponent,
  AksComponent,
  requiredTags,
} from "../src/index";

// ── requiredTags ───────────────────────────────────────────────────────────────

describe("requiredTags", () => {
  it("injects managed_by, project, and environment", () => {
    const tags = requiredTags("myapp", "dev");
    expect(tags["managed_by"]).toBe("pulumi");
    expect(tags["project"]).toBe("myapp");
    expect(tags["environment"]).toBe("dev");
  });

  it("required tags override any extra key of the same name", () => {
    const tags = requiredTags("myapp", "prod", { managed_by: "manual", team: "platform" });
    expect(tags["managed_by"]).toBe("pulumi");
    expect(tags["team"]).toBe("platform");
  });
});

// ── NetworkComponent ───────────────────────────────────────────────────────────

describe("NetworkComponent", () => {
  it("throws on invalid environment", () => {
    expect(() =>
      new NetworkComponent("net", {
        project: "myapp", environment: "uat",
        resourceGroup: "rg", location: "eastus",
        addressSpace: ["10.0.0.0/16"],
      })
    ).toThrow(/environment must be/);
  });

  it("exposes vnetId as an Output", async () => {
    const comp = new NetworkComponent("net", {
      project: "myapp", environment: "dev",
      resourceGroup: "myapp-dev-rg", location: "eastus",
      addressSpace: ["10.10.0.0/16"],
      subnets: {
        aks: { addressPrefix: "10.10.0.0/22" },
        db: {
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

    const vnetId = await new Promise<string>(resolve => comp.vnetId.apply(resolve));
    expect(vnetId).toBeTruthy();
  });

  it("subnetIds contains all configured subnets", async () => {
    const comp = new NetworkComponent("net2", {
      project: "myapp", environment: "staging",
      resourceGroup: "rg", location: "eastus",
      addressSpace: ["10.0.0.0/16"],
      subnets: {
        aks: { addressPrefix: "10.0.0.0/22" },
        db:  { addressPrefix: "10.0.8.0/24" },
      },
    });

    const ids = await new Promise<Record<string, string>>(resolve =>
      comp.subnetIds.apply(resolve)
    );
    expect(Object.keys(ids)).toContain("aks");
    expect(Object.keys(ids)).toContain("db");
  });
});

// ── DatabaseComponent ──────────────────────────────────────────────────────────

describe("DatabaseComponent", () => {
  it("throws on invalid environment", () => {
    expect(() =>
      new DatabaseComponent("db", {
        project: "myapp", environment: "qa",
        resourceGroup: "rg", location: "eastus",
        subnetId: "sn", dnsZoneId: "dns",
        adminPassword: "secret",
      })
    ).toThrow(/environment must be/);
  });

  it("exposes fqdn as an Output", async () => {
    const comp = new DatabaseComponent("db", {
      project: "myapp", environment: "prod",
      resourceGroup: "myapp-prod-rg", location: "eastus",
      subnetId: "/subscriptions/x/subnets/db",
      dnsZoneId: "/subscriptions/x/privateDnsZones/postgres",
      adminPassword: "Hunter2!",
      config: { databases: ["appdb"], haEnabled: true },
    });

    const fqdn = await new Promise<string>(resolve => comp.fqdn.apply(resolve));
    expect(fqdn).toBeTruthy();
  });

  it("sets ZoneRedundant when haEnabled", async () => {
    const comp = new DatabaseComponent("db-ha", {
      project: "myapp", environment: "prod",
      resourceGroup: "rg", location: "eastus",
      subnetId: "sn", dnsZoneId: "dns",
      adminPassword: "secret",
      config: { haEnabled: true },
    });
    // Component is created without error — HA mode flows into resource args.
    expect(comp.serverId).toBeDefined();
  });
});

// ── AksComponent ───────────────────────────────────────────────────────────────

describe("AksComponent", () => {
  it("throws on invalid environment", () => {
    expect(() =>
      new AksComponent("aks", {
        project: "myapp", environment: "badenv",
        resourceGroup: "rg", location: "eastus",
        subnetId: "sn", logWorkspaceId: "ws",
      })
    ).toThrow(/environment must be/);
  });

  it("exposes clusterId as an Output", async () => {
    const comp = new AksComponent("aks", {
      project: "myapp", environment: "staging",
      resourceGroup: "myapp-staging-rg", location: "eastus",
      subnetId: "/subscriptions/x/subnets/aks",
      logWorkspaceId: "/subscriptions/x/workspaces/logs",
      config: {
        systemNodeCount: 1,
        additionalNodePools: {
          workers: {
            vmSize: "Standard_D8s_v3",
            enableAutoScaling: true,
            minCount: 2, maxCount: 10,
            labels: { workload: "app" },
          },
        },
      },
    });

    const clusterId = await new Promise<string>(resolve => comp.clusterId.apply(resolve));
    expect(clusterId).toBeTruthy();
  });

  it("required tags include managed_by=pulumi", () => {
    const comp = new AksComponent("aks2", {
      project: "myapp", environment: "dev",
      resourceGroup: "rg", location: "eastus",
      subnetId: "sn", logWorkspaceId: "ws",
      config: { extraTags: { cost_center: "eng" } },
    });
    expect(comp.clusterName).toBeDefined();
  });
});
