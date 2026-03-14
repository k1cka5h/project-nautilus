#!/usr/bin/env bash
# apply-repo-config.sh
#
# Applies a Nautilus repository configuration to a GitHub repo using the gh CLI.
#
# Usage:
#   apply-repo-config.sh <org> <repo> <config-file> [--dry-run]
#
# Prerequisites:
#   - gh CLI authenticated with a PAT that has: repo, admin:org, read:org scopes
#   - jq installed
#
# Example:
#   GH_TOKEN=ghp_xxx bash setup/scripts/apply-repo-config.sh \
#     k1cka5h portal-infra setup/configs/product-team.json
#
#   # Dry run — print what would happen without making any changes:
#   bash setup/scripts/apply-repo-config.sh k1cka5h portal-infra setup/configs/product-team.json --dry-run

set -euo pipefail

ORG="${1:?Usage: $0 <org> <repo> <config-file> [--dry-run]}"
REPO="${2:?Usage: $0 <org> <repo> <config-file> [--dry-run]}"
CONFIG="${3:?Usage: $0 <org> <repo> <config-file> [--dry-run]}"
DRY_RUN="${4:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$(cd "${SCRIPT_DIR}/../templates" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }
dry()  { echo -e "${YELLOW}[DRY]${NC}   $*"; }

is_dry() { [[ "${DRY_RUN}" == "--dry-run" ]]; }

api() {
  local method="$1"; shift
  local endpoint="$1"; shift
  if is_dry; then
    dry "gh api --method ${method} ${endpoint} $*"
  else
    gh api --method "${method}" "${endpoint}" "$@"
  fi
}

# ── Validate inputs ────────────────────────────────────────────────────────────

[[ -f "${CONFIG}" ]] || fail "Config file not found: ${CONFIG}"
command -v gh  >/dev/null 2>&1 || fail "'gh' CLI is not installed"
command -v jq  >/dev/null 2>&1 || fail "'jq' is not installed"

log "Applying config: ${CONFIG}"
log "Target:          ${ORG}/${REPO}"
is_dry && warn "DRY RUN — no changes will be made"
echo ""

# ── 1. Repository settings ────────────────────────────────────────────────────

log "Applying repository settings..."
REPO_SETTINGS=$(jq '.repo' "${CONFIG}")
if is_dry; then
  dry "PATCH /repos/${ORG}/${REPO}  $(echo "${REPO_SETTINGS}" | jq -c .)"
else
  echo "${REPO_SETTINGS}" \
    | gh api --method PATCH "/repos/${ORG}/${REPO}" --input - > /dev/null
fi
ok "Repository settings applied"

# ── 2. Branch protection ──────────────────────────────────────────────────────

log "Applying branch protection..."
BRANCH=$(jq -r '.branch_protection.branch' "${CONFIG}")
PROTECTION=$(jq '.branch_protection | del(.branch)' "${CONFIG}")
if is_dry; then
  dry "PUT /repos/${ORG}/${REPO}/branches/${BRANCH}/protection  $(echo "${PROTECTION}" | jq -c .)"
else
  echo "${PROTECTION}" \
    | gh api --method PUT "/repos/${ORG}/${REPO}/branches/${BRANCH}/protection" --input - > /dev/null
fi
ok "Branch protection applied to '${BRANCH}'"

# ── 3. GitHub Environments ────────────────────────────────────────────────────

ENV_COUNT=$(jq '.environments | length' "${CONFIG}")
if [[ "${ENV_COUNT}" -gt 0 ]]; then
  log "Applying ${ENV_COUNT} environment(s)..."
  jq -c '.environments[]' "${CONFIG}" | while read -r env_cfg; do
    ENV_NAME=$(echo "${env_cfg}" | jq -r '.name')
    WAIT_TIMER=$(echo "${env_cfg}" | jq -r '.wait_timer // 0')
    BRANCH_POLICY=$(echo "${env_cfg}" | jq -r '.deployment_branch_policy // "protected_branches"')

    log "  Configuring environment: ${ENV_NAME}"

    # Resolve reviewer team slugs to IDs
    REVIEWERS="[]"
    TEAM_SLUGS=$(echo "${env_cfg}" | jq -r '.reviewer_teams[]? // empty')
    while IFS= read -r slug; do
      [[ -z "${slug}" ]] && continue
      if is_dry; then
        dry "  Resolving team slug '${slug}' to ID"
        TEAM_ID=99999
      else
        TEAM_ID=$(gh api "/orgs/${ORG}/teams/${slug}" --jq '.id' 2>/dev/null) \
          || fail "Team '${slug}' not found in org '${ORG}'"
      fi
      REVIEWERS=$(echo "${REVIEWERS}" | jq --argjson id "${TEAM_ID}" '. + [{"type":"Team","id":$id}]')
    done <<< "${TEAM_SLUGS}"

    # Build deployment_branch_policy payload
    if [[ "${BRANCH_POLICY}" == "protected_branches" ]]; then
      BRANCH_POLICY_JSON='{"protected_branches":true,"custom_branch_policies":false}'
    else
      BRANCH_POLICY_JSON='null'
    fi

    ENV_PAYLOAD=$(jq -n \
      --argjson wait "${WAIT_TIMER}" \
      --argjson reviewers "${REVIEWERS}" \
      --argjson branch_policy "${BRANCH_POLICY_JSON}" \
      '{wait_timer: $wait, reviewers: $reviewers, deployment_branch_policy: $branch_policy}')

    if is_dry; then
      dry "PUT /repos/${ORG}/${REPO}/environments/${ENV_NAME}  $(echo "${ENV_PAYLOAD}" | jq -c .)"
    else
      echo "${ENV_PAYLOAD}" \
        | gh api --method PUT "/repos/${ORG}/${REPO}/environments/${ENV_NAME}" --input - > /dev/null
    fi
    ok "  Environment '${ENV_NAME}' configured (wait=${WAIT_TIMER}m, reviewers=${REVIEWERS})"
  done
fi

# ── 4. Team permissions ───────────────────────────────────────────────────────

TEAM_COUNT=$(jq '.teams | length' "${CONFIG}")
if [[ "${TEAM_COUNT}" -gt 0 ]]; then
  log "Applying team permissions..."
  jq -c '.teams[]' "${CONFIG}" | while read -r team_cfg; do
    SLUG=$(echo "${team_cfg}" | jq -r '.slug')
    PERM=$(echo "${team_cfg}" | jq -r '.permission')
    api PUT "/orgs/${ORG}/teams/${SLUG}/repos/${ORG}/${REPO}" \
      --field "permission=${PERM}" > /dev/null
    ok "  Team '${SLUG}' granted '${PERM}'"
  done
fi

# ── 5. Labels ─────────────────────────────────────────────────────────────────

LABEL_COUNT=$(jq '.labels | length' "${CONFIG}")
if [[ "${LABEL_COUNT}" -gt 0 ]]; then
  log "Applying ${LABEL_COUNT} label(s)..."

  # Fetch existing labels once
  if is_dry; then
    EXISTING_LABELS="[]"
  else
    EXISTING_LABELS=$(gh api "/repos/${ORG}/${REPO}/labels" --paginate --jq '[.[].name]')
  fi

  jq -c '.labels[]' "${CONFIG}" | while read -r label_cfg; do
    LABEL_NAME=$(echo "${label_cfg}" | jq -r '.name')
    LABEL_COLOR=$(echo "${label_cfg}" | jq -r '.color')
    LABEL_DESC=$(echo "${label_cfg}" | jq -r '.description')

    EXISTS=$(echo "${EXISTING_LABELS}" | jq --arg n "${LABEL_NAME}" 'map(select(. == $n)) | length > 0')
    if [[ "${EXISTS}" == "true" ]]; then
      api PATCH "/repos/${ORG}/${REPO}/labels/$(python3 -c "import urllib.parse; print(urllib.parse.quote('${LABEL_NAME}'))")" \
        --field "color=${LABEL_COLOR}" \
        --field "description=${LABEL_DESC}" > /dev/null
      ok "  Updated label '${LABEL_NAME}'"
    else
      api POST "/repos/${ORG}/${REPO}/labels" \
        --field "name=${LABEL_NAME}" \
        --field "color=${LABEL_COLOR}" \
        --field "description=${LABEL_DESC}" > /dev/null
      ok "  Created label '${LABEL_NAME}'"
    fi
  done
fi

# ── 6. File templates ─────────────────────────────────────────────────────────

CODEOWNERS_VARIANT=$(jq -r '.templates.codeowners // empty' "${CONFIG}")
PR_TEMPLATE=$(jq -r '.templates.pull_request_template // false' "${CONFIG}")
ISSUE_TEMPLATES=$(jq -r '.templates.issue_templates[]? // empty' "${CONFIG}")

commit_file() {
  local dest_path="$1"
  local src_file="$2"
  local message="$3"

  if is_dry; then
    dry "Commit '${dest_path}' from '${src_file}'"
    return
  fi

  local content
  content=$(base64 < "${src_file}" | tr -d '\n')

  # Check if file already exists (need its SHA to update)
  local sha=""
  sha=$(gh api "/repos/${ORG}/${REPO}/contents/${dest_path}" --jq '.sha' 2>/dev/null || true)

  local payload
  if [[ -n "${sha}" ]]; then
    payload=$(jq -n --arg msg "${message}" --arg content "${content}" --arg sha "${sha}" \
      '{message: $msg, content: $content, sha: $sha}')
  else
    payload=$(jq -n --arg msg "${message}" --arg content "${content}" \
      '{message: $msg, content: $content}')
  fi

  echo "${payload}" \
    | gh api --method PUT "/repos/${ORG}/${REPO}/contents/${dest_path}" --input - > /dev/null
}

if [[ -n "${CODEOWNERS_VARIANT}" ]]; then
  log "Committing CODEOWNERS..."
  SRC="${TEMPLATES_DIR}/CODEOWNERS.${CODEOWNERS_VARIANT}"
  [[ -f "${SRC}" ]] || fail "CODEOWNERS template not found: ${SRC}"
  commit_file ".github/CODEOWNERS" "${SRC}" "chore: add CODEOWNERS via Nautilus setup"
  ok "CODEOWNERS committed"
fi

if [[ "${PR_TEMPLATE}" == "true" ]]; then
  log "Committing pull request template..."
  # Use platform template for platform/construct repos, product template otherwise
  if [[ "${CODEOWNERS_VARIANT}" == "product" ]]; then
    PR_SRC="${TEMPLATES_DIR}/pull_request_template.product.md"
  else
    PR_SRC="${TEMPLATES_DIR}/pull_request_template.platform.md"
  fi
  [[ -f "${PR_SRC}" ]] || fail "PR template not found: ${PR_SRC}"
  commit_file ".github/pull_request_template.md" "${PR_SRC}" "chore: add PR template via Nautilus setup"
  ok "Pull request template committed"
fi

if [[ -n "${ISSUE_TEMPLATES}" ]]; then
  log "Committing issue templates..."
  while IFS= read -r tmpl; do
    [[ -z "${tmpl}" ]] && continue
    SRC="${TEMPLATES_DIR}/issue_templates/${tmpl}.yml"
    [[ -f "${SRC}" ]] || { warn "Issue template not found, skipping: ${SRC}"; continue; }
    commit_file ".github/ISSUE_TEMPLATE/${tmpl}.yml" "${SRC}" "chore: add issue template '${tmpl}' via Nautilus setup"
    ok "  Issue template '${tmpl}' committed"
  done <<< "${ISSUE_TEMPLATES}"
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
if is_dry; then
  warn "Dry run complete — no changes were made to ${ORG}/${REPO}"
else
  ok "Setup complete for ${ORG}/${REPO}"
  log "Next steps:"
  log "  - Verify branch protection at: https://github.com/${ORG}/${REPO}/settings/branches"
  log "  - Verify environments at:      https://github.com/${ORG}/${REPO}/settings/environments"
  log "  - Add the REGISTRY_TOKEN secret (construct repos) or product team secrets as needed"
fi
