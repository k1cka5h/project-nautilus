# bootstrap

One-time Terraform that provisions the Azure and Azure AD resources the Nautilus
platform depends on. Run these before any product team infrastructure can be
deployed.

```
bootstrap/
├── platform/      Run once — creates the state backend and platform service principal
└── product-team/  Run once per product team — creates SPs, OIDC credentials, and RBAC
```

Both modules are **idempotent**. Rerunning them against an existing deployment
produces no changes unless variables have changed.

---

## Prerequisites

- **Azure CLI** authenticated as a principal with:
  - Owner on the platform subscription (to create RBAC assignments)
  - Global Administrator or Application Administrator in Azure AD (to create
    applications and service principals)
- **Terraform ≥ 1.7**

---

## Step 1 — `platform/`

Run once when first implementing Nautilus.

### What it creates

| Resource | Purpose |
|----------|---------|
| Resource group | Container for platform infrastructure |
| Storage account (`platformtfstate`, GRS, versioned) | Terraform state backend for all product teams |
| Storage container (`tfstate`) | Blob container within the account |
| Management lock | Protects the state account from accidental deletion |
| Azure AD application + service principal (`nautilus-platform`) | Platform team's own CI identity |
| OIDC federated credential | Scoped to the Nautilus repo's `main` branch |
| Role assignment — Contributor on platform subscription | Allows governance (Azure Policy) deployment |
| Role assignment — Storage Blob Data Contributor on state account | Allows the platform SP to access any product team's state during incident response |

### Why `backend "local"`

`platform/` uses a local state backend intentionally — it creates the remote
backend, so it cannot use it during that first apply. After apply you can
optionally migrate:

```bash
# Add azurerm backend block to platform/main.tf, then:
terraform init -migrate-state
```

### Apply

```bash
cd bootstrap/platform

az login
az account set --subscription <platform-subscription-id>

terraform init

terraform apply \
  -var="platform_subscription_id=<platform-subscription-id>" \
  -var="github_org=myorg" \
  -var="github_repo=project-nautilus"
```

### Read the outputs

```bash
terraform output next_steps             # ready-to-copy GitHub secrets block
terraform output state_storage_account_id  # needed for product-team bootstrap
terraform output tenant_id              # AZURE_TENANT_ID Actions variable
```

Set the GitHub Actions secrets and variables on the Nautilus repo as printed.

---

## Step 2 — `product-team/`

Run once per product team when onboarding them. Creates one service principal
per environment (dev, qa, stage, prod), each with an OIDC federated credential
scoped to `repo:<org>/<repo>:environment:<env>`.

### What it creates (per environment)

| Resource | Purpose |
|----------|---------|
| Azure AD application + service principal (`<product>-<env>`) | Per-environment identity for product team CI |
| OIDC federated credential | Scoped to the product repo's GitHub Environment |
| Role assignment — Contributor on the environment's subscription | Allows `terraform apply` |
| Role assignment — Storage Blob Data Contributor on state account | Allows remote state read/write |

One SP per environment (rather than one SP with multiple credentials) limits
blast radius — a compromised dev credential cannot touch prod.

### Apply

```bash
cd bootstrap/product-team

terraform init \
  -backend-config="storage_account_name=platformtfstate" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=bootstrap/portal/terraform.tfstate" \
  -backend-config="use_oidc=true"

terraform apply \
  -var="product_name=portal" \
  -var="github_org=myorg" \
  -var="github_repo=portal-infra" \
  -var='subscription_ids={"dev":"<id>","qa":"<id>","stage":"<id>","prod":"<id>"}' \
  -var="state_storage_account_id=<from platform output>" \
  -var="platform_subscription_id=<platform-subscription-id>"
```

If environments share a subscription, repeat the same ID:

```bash
-var='subscription_ids={"dev":"<shared>","qa":"<shared>","stage":"<shared>","prod":"<prod>"}'
```

### Read the outputs

```bash
terraform output github_secrets
```

Prints the complete set of GitHub Actions secrets to copy into the product
team's repo: `DEV_AZURE_CLIENT_ID`, `DEV_AZURE_SUBSCRIPTION_ID`, and so on for
each environment, plus `AZURE_TENANT_ID`.

### Multiple product teams

Each team gets its own state file keyed by product name:

```bash
for product in portal myapp billing; do
  terraform -chdir=bootstrap/product-team init \
    -backend-config="key=bootstrap/${product}/terraform.tfstate" \
    [other backend-config flags]

  terraform -chdir=bootstrap/product-team apply \
    -var="product_name=${product}" \
    [other vars]
done
```

---

## What bootstrap does not provision

| Item | Where to handle it |
|------|-------------------|
| GitHub repositories | `gh repo create` or GitHub UI |
| Branch protection, environments, labels, templates | `setup/scripts/apply-repo-config.sh` — see [setup/README.md](../setup/README.md) |
| SSH deploy keys for `terraform-modules` | Generate and add manually — see [wiki/platform-module-maintenance.md](../wiki/platform-module-maintenance.md#provisioning-a-deploy-key-for-a-new-product-team) |
| `DB_ADMIN_PASSWORD`, `LOG_WORKSPACE_ID` secrets | `gh secret set` — see [wiki/bootstrap.md](../wiki/bootstrap.md#set-the-remaining-secrets-manually) |
| Azure Policy governance module | `cd tf-modules/governance && terraform apply` |
| Internal package registries | Organisation-specific (Artifactory, Nexus, or GitHub Packages) |

Full step-by-step instructions: [wiki/bootstrap.md](../wiki/bootstrap.md)
