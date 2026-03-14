# github.com/k1cka5h/infra-go — Go

Platform-managed CDKTF construct library for Azure. Published to the internal
Go proxy at `https://goproxy.k1cka5h.internal`.

## Install

```bash
GONOSUMCHECK=github.com/k1cka5h/infra-go \
GOPROXY=https://goproxy.k1cka5h.internal,direct \
  go get github.com/k1cka5h/infra-go@v1.4.0
```

## Constructs

| Type | Wraps | Key outputs |
|------|-------|-------------|
| `BaseAzureStack` | Provider + AzureRM state backend | — |
| `NetworkConstruct` | `modules/networking` | `VnetId()`, `VnetName()`, `SubnetIds()`, `DnsZoneIds()` |
| `DatabaseConstruct` | `modules/database/postgres` | `Fqdn()`, `ServerId()` |
| `AksConstruct` | `modules/compute/aks` | `ClusterId()`, `KubeletIdentityObjectId()` |

## Usage

```go
package main

import (
    "github.com/aws/constructs-go/constructs/v10"
    "github.com/aws/jsii-runtime-go"
    "github.com/hashicorp/terraform-cdk-go/cdktf"
    infra "github.com/k1cka5h/infra-go"
)

type MyAppStack struct {
    *infra.BaseAzureStack
}

func NewMyAppStack(scope constructs.Construct, id *string, props *infra.BaseAzureStackProps) *MyAppStack {
    base := infra.NewBaseAzureStack(scope, id, props)
    s := &MyAppStack{BaseAzureStack: base}

    net := infra.NewNetworkConstruct(s, jsii.String("network"), &infra.NetworkConstructProps{
        Project:       base.Project(),
        Environment:   base.Environment(),
        ResourceGroup: jsii.String("myapp-dev-rg"),
        Location:      base.Location(),
        AddressSpace:  &[]*string{jsii.String("10.10.0.0/16")},
        Subnets: &map[string]*infra.SubnetConfig{
            "aks": {AddressPrefix: jsii.String("10.10.0.0/22")},
            "db":  {AddressPrefix: jsii.String("10.10.4.0/24")},
        },
    })

    infra.NewDatabaseConstruct(s, jsii.String("database"), &infra.DatabaseConstructProps{
        Project:       base.Project(),
        Environment:   base.Environment(),
        ResourceGroup: jsii.String("myapp-dev-rg"),
        Location:      base.Location(),
        SubnetId:      (*net.SubnetIds())["db"],
        DnsZoneId:     (*net.DnsZoneIds())["postgres.database.azure.com"],
        Postgres: &infra.PostgresConfig{
            HaEnabled: jsii.Bool(false),
        },
    })

    infra.NewAksConstruct(s, jsii.String("aks"), &infra.AksConstructProps{
        Project:       base.Project(),
        Environment:   base.Environment(),
        ResourceGroup: jsii.String("myapp-dev-rg"),
        Location:      base.Location(),
        SubnetId:      (*net.SubnetIds())["aks"],
    })

    return s
}

func main() {
    app := cdktf.NewApp(nil)
    NewMyAppStack(app, jsii.String("myapp-dev"), &infra.BaseAzureStackProps{
        Project:     jsii.String("myapp"),
        Environment: jsii.String("dev"),
    })
    app.Synth()
}
```

## Development

```bash
go build ./...
go test ./...
```

## Publishing

Tag the commit and push — the internal Go proxy mirrors from GitHub automatically:

```bash
git tag constructs/go/v1.4.1
git push origin constructs/go/v1.4.1
```
