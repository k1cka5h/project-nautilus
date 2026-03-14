# setup

Everything needed to provision a complete Nautilus implementation from scratch.

## 🐚 Quick start — the Nautilus wizard

**`nautilus.sh` is the primary entry point.** It is an interactive, Nautilus-themed
wizard that handles the complete implementation in a single guided session:

```bash
bash setup/nautilus.sh
```

The wizard will:
1. Check prerequisites (`gh`, `jq`, `git`, `terraform`)
2. Authenticate to GitHub via device flow
3. Create all platform repositories in your org
4. Push source code scaffolding to each repo
5. Apply branch protection, environments, labels, CODEOWNERS, and templates
6. Optionally run the Azure bootstrap inline

No manual steps are required. After the wizard completes, the only remaining
work is setting Azure secrets (printed by the bootstrap Terraform output).

**Prerequisites:** `gh` CLI, `jq`, `git`
**Optional:** `terraform` ≥ 1.7 (for inline Azure bootstrap)

---

## Directory layout

```
setup/
├── nautilus.sh                 🐚 Primary setup wizard — start here
├── configs/                    JSON configuration profiles — one per repo type
│   ├── terraform-modules.json  For the Terraform module library
│   ├── reusable-workflows.json For the shared GitHub Actions workflow repo
│   ├── construct-library.json  For each language construct library repo
│   └── product-team.json       For each product team's infrastructure repo
├── scripts/
│   └── apply-repo-config.sh    Low-level helper (called by nautilus.sh)
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

## Using `apply-repo-config.sh` directly (advanced)

`apply-repo-config.sh` is the low-level helper called by `nautilus.sh`. You can
also run it directly to apply or re-apply a config to a single repo — useful
for updating an existing repo after a config change.

**Prerequisites:**
- `gh` CLI authenticated with `repo`, `admin:org`, and `read:org` scopes
- `jq` installed
- `platform-infra` team already exists in the org

```bash
bash setup/scripts/apply-repo-config.sh <org> <repo> <config-file> [--dry-run]
```

### Examples

```bash
# Apply platform config to the Terraform modules repo
bash setup/scripts/apply-repo-config.sh \
  k1cka5h terraform-modules setup/configs/terraform-modules.json

# Apply construct library config to the Python library repo
bash setup/scripts/apply-repo-config.sh \
  k1cka5h k1cka5h-infra-python setup/configs/construct-library.json

# Apply product team config when onboarding a new team
bash setup/scripts/apply-repo-config.sh \
  k1cka5h portal-infra setup/configs/product-team.json

# Dry run — print what would happen without making any changes
bash setup/scripts/apply-repo-config.sh \
  k1cka5h portal-infra setup/configs/product-team.json --dry-run
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
| Creating the GitHub repository | `gh repo create k1cka5h/<repo> --private` or GitHub UI |
| Adding `REGISTRY_TOKEN` secret (construct repos) | `gh secret set REGISTRY_TOKEN --repo k1cka5h/<repo>` |
| Adding product team Azure secrets | From `terraform output github_secrets` in `bootstrap/product-team/` |
| Adding `TF_MODULES_DEPLOY_KEY` | See [wiki/platform-module-maintenance.md](../wiki/platform-module-maintenance.md#provisioning-a-deploy-key-for-a-new-product-team) |
| Inviting product team members | GitHub org member management |

Full onboarding checklist: [wiki/platform-product-maintenance.md](../wiki/platform-product-maintenance.md#onboarding-a-new-product-team)
