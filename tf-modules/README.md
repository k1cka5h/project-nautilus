# terraform-modules (myorg/terraform-modules)

**Platform team owned. Do not modify directly — open a GitHub issue or Jira ticket.**

This repository contains the organization's approved Terraform modules for Azure.
All modules are consumed via the `myorg-infra` CDKTF construct library. Developers
do not reference this repo directly.

## Module catalogue

| Path | Description |
|------|-------------|
| `modules/networking` | VNet, subnets, NSGs, private DNS zones |
| `modules/database/postgres` | PostgreSQL Flexible Server with private access |
| `modules/compute/aks` | AKS cluster with Azure CNI, AAD RBAC, monitoring |

## Versioning

Releases follow [Semantic Versioning](https://semver.org/) and are published as
Git tags (`v1.4.0`, etc.). The `myorg-infra` construct library pins a specific tag
in each module's source URL:

```
git::ssh://git@github.com/myorg/terraform-modules.git//modules/networking?ref=v1.4.0
```

Consumers must never use `?ref=main` or omit the ref — this breaks reproducibility.

## Access

Private repo. Terraform accesses it via a deploy key at runtime. The deploy key is
stored as `TF_MODULES_DEPLOY_KEY` in each consuming repo's GitHub Actions secrets.

To request access or add a new key: open a ticket in the Platform team's Jira board.

## Contributing (platform team)

1. Branch from `main`, name it `feat/<module>-<description>` or `fix/<...>`.
2. All changes must pass `terraform fmt`, `terraform validate`, and the CI workflow.
3. Bump the version in `CHANGELOG.md` and create a signed tag on merge.
4. Announce breaking changes in **#platform-infra** (Slack) before tagging.

## Local module development

```bash
cd modules/networking
terraform init -backend=false
terraform validate
terraform fmt
```
