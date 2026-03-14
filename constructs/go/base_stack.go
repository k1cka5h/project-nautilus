// Package infra provides platform-managed CDKTF constructs for Azure.
// Published to the internal Go proxy at https://goproxy.k1cka5h.internal.
package infra

import (
	"fmt"

	"github.com/aws/constructs-go/constructs/v10"
	"github.com/aws/jsii-runtime-go"
	"github.com/cdktf/cdktf-provider-azurerm-go/azurerm/v12/provider"
	"github.com/hashicorp/terraform-cdk-go/cdktf"
)

// BaseAzureStackProps configures a BaseAzureStack.
type BaseAzureStackProps struct {
	Project     *string
	Environment *string
	// Location defaults to "eastus" if nil.
	Location *string
}

// BaseAzureStack is the base for all developer-authored CDKTF stacks.
// It configures the AzureRM provider and remote state backend automatically.
type BaseAzureStack struct {
	cdktf.TerraformStack
	project     *string
	environment *string
	location    *string
}

// NewBaseAzureStack creates and returns a BaseAzureStack.
func NewBaseAzureStack(scope constructs.Construct, id *string, props *BaseAzureStackProps) *BaseAzureStack {
	env := jsii.String("dev")
	if props.Environment != nil {
		env = props.Environment
	}

	validEnvs := map[string]bool{"dev": true, "staging": true, "prod": true}
	if !validEnvs[*env] {
		panic(fmt.Sprintf("environment must be dev, staging, or prod — got '%s'", *env))
	}

	loc := jsii.String("eastus")
	if props.Location != nil {
		loc = props.Location
	}

	stack := &BaseAzureStack{
		TerraformStack: cdktf.NewTerraformStack(scope, id),
		project:        props.Project,
		environment:    env,
		location:       loc,
	}

	provider.NewAzurermProvider(stack, jsii.String("azurerm"), &provider.AzurermProviderConfig{
		Features: &[]*provider.AzurermProviderFeatures{{}},
	})

	cdktf.NewAzurermBackend(stack, &cdktf.AzurermBackendConfig{
		ResourceGroupName:  jsii.String("platform-tfstate-rg"),
		StorageAccountName: jsii.String("platformtfstate"),
		ContainerName:      jsii.String("tfstate"),
		Key:                jsii.String(fmt.Sprintf("%s/%s/terraform.tfstate", *props.Project, *env)),
	})

	return stack
}

func (s *BaseAzureStack) Project()     *string { return s.project }
func (s *BaseAzureStack) Environment() *string { return s.environment }
func (s *BaseAzureStack) Location()    *string { return s.location }
