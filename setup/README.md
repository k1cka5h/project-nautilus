# setup

Scripts, configuration, and templates for initialising GitHub repositories to
Nautilus standards. Use this when creating a new repo for any part of the
platform, or when onboarding a new product team.

```
setup/
├── configs/                    JSON configuration profiles — one per repo type
│   ├── terraform-modules.json  For the private Terraform module library
│   ├── reusable-workflows.json For the shared GitHub Actions workflow repo
│   ├── construct-library.json  For each language construct library repo
│   └── product-team.json       For each product team's infrastructure repo
├── scripts/
│   └── apply-repo-config.sh    Applies a config profile to a GitHub repo
└── templates/                  File templates committed into target repos
    ├── CODEOWNERS.platform     For platform repos (terraform-modules, reusable-workflows)
    ├── CODEOWNERS.construct    For construct library repos
    ├── CODEOWNERS.product      For product team repos
    ├── pull_request_template.platform.md
    ├── pull_request_template.product.md
    └── issue_templates/
        ├── bug_report.yml
        ├── new_module.yml
        ├── sku_request.yml
        └── infra_request.yml
```

---

## What each config applies

| Config | Branch protection | Environments | Team | Labels | Templates |
|--------|------------------|-------------|------|--------|-----------|
| `terraform-modules` | 2 reviews, strict checks, no force-push | None | `platform-infra` (maintain) | 10 module/change labels | CODEOWNERS (platform), PR template, bug/module/SKU issue templates |
| `reusable-workflows` | 2 reviews, strict checks | None | `platform-infra` (maintain) | 8 pipeline/change labels | CODEOWNERS (platform), PR template, bug issue template |
| `construct-library` | 1 review, strict checks | `registry` (required reviewer gate for publishing) | `platform-infra` (maintain) | 3 labels | CODEOWNERS (construct), PR template |
| `product-team` | 1 review, validate check | `stage` (10-min wait, platform reviewer), `prod` (10-min wait, platform reviewer) | `platform-infra` (push) | 5 operational labels (drift, plan:env, infra-request) | CODEOWNERS (product), PR template, infra-request issue template |

---

## Prerequisites

- **`gh` CLI** authenticated with a PAT that has `repo`, `admin:org`, and
  `read:org` scopes
- **`jq`** installed
- The `platform-infra` GitHub team must already exist in the organisation

---

## Running the script

```bash
bash setup/scripts/apply-repo-config.sh <org> <repo> <config-file> [--dry-run]
```

### Examples

```bash
# Apply platform config to the Terraform modules repo
bash setup/scripts/apply-repo-config.sh \
  myorg terraform-modules setup/configs/terraform-modules.json

# Apply construct library config to the Python library repo
bash setup/scripts/apply-repo-config.sh \
  myorg myorg-infra-python setup/configs/construct-library.json

# Apply product team config when onboarding a new team
bash setup/scripts/apply-repo-config.sh \
  myorg portal-infra setup/configs/product-team.json

# Dry run — print what would happen without making any changes
bash setup/scripts/apply-repo-config.sh \
  myorg portal-infra setup/configs/product-team.json --dry-run
```

### What the script does

1. **Repository settings** — visibility, merge strategy (squash only), branch
   cleanup on merge
2. **Branch protection** — required status checks, required reviews, no
   force-push, no deletion
3. **GitHub Environments** — creates environments with wait timers and required
   reviewers (resolves team slugs to IDs automatically)
4. **Team permissions** — grants the appropriate GitHub team access to the repo
5. **Labels** — creates or updates all labels defined in the config (upsert
   safe — existing labels are updated, not duplicated)
6. **File templates** — commits CODEOWNERS, PR template, and issue templates
   directly to the repo's default branch via the GitHub Contents API (creates
   or updates; will not overwrite manually edited files with wrong SHA)

---

## Running via GitHub Actions

A `workflow_dispatch` workflow is available at
`.github/workflows/setup-repo.yml`. Use it to apply configs without a local
`gh` CLI setup:

1. Go to **Actions → Setup Repository → Run workflow**
2. Fill in: `org`, `repo`, config type (dropdown), and optionally `dry_run`
3. The workflow uses the `PLATFORM_GITHUB_TOKEN` secret — set this on the
   Nautilus repo with the same scopes listed above

---

## Customising a config

The JSON configs are the canonical definition of what "correct" looks like for
each repo type. To change defaults for all future repos of a type, edit the
relevant config file and open a PR.

To apply an updated config to an existing repo (e.g. to add a new label),
rerun the script against it — the script is idempotent.

---

## What the script does not manage

| Item | How to handle it |
|------|-----------------|
| Creating the GitHub repository | `gh repo create myorg/<repo> --private` or GitHub UI |
| Adding `REGISTRY_TOKEN` secret (construct repos) | `gh secret set REGISTRY_TOKEN --repo myorg/<repo>` |
| Adding product team Azure secrets | From `terraform output github_secrets` in `bootstrap/product-team/` |
| Adding `TF_MODULES_DEPLOY_KEY` | See [wiki/platform-module-maintenance.md](../wiki/platform-module-maintenance.md#provisioning-a-deploy-key-for-a-new-product-team) |
| Inviting product team members | GitHub org member management |

Full onboarding checklist: [wiki/platform-product-maintenance.md](../wiki/platform-product-maintenance.md#onboarding-a-new-product-team)
