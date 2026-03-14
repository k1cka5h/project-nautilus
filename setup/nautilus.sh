#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  nautilus.sh  ·  Nautilus IaC Platform Setup Wizard
# ─────────────────────────────────────────────────────────────────────────────
#  Interactive wizard that provisions a complete Nautilus implementation:
#    · GitHub repositories, branch protection, environments, and labels
#    · Platform team with correct permissions
#    · CODEOWNERS, PR templates, and issue templates
#    · Source code scaffolding pushed to every repo
#    · Guided Azure bootstrap walkthrough
#
#  Prerequisites: gh CLI, jq, git   (terraform optional — for Azure bootstrap)
#  Run from anywhere inside the project-nautilus repository.
#
#  Usage:
#    bash setup/nautilus.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIGS_DIR="${SCRIPT_DIR}/configs"
APPLY_SCRIPT="${SCRIPT_DIR}/apply-repo-config.sh"

# ── Theme ─────────────────────────────────────────────────────────────────────
TEAL='\033[0;36m'
LTEAL='\033[1;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Layout primitives ─────────────────────────────────────────────────────────

print_banner() {
  clear
  echo ""
  echo -e "${TEAL}    ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·${NC}"
  echo ""
  echo -e "        ${LTEAL}${BOLD}🐚   N A U T I L U S${NC}"
  echo -e "        ${DIM}Self-service Azure IaC platform for your entire org${NC}"
  echo ""
  echo -e "${TEAL}    ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·${NC}"
  echo ""
}

sep()  { echo -e "\n${TEAL}    ──────────────────────────────────────────────────────────${NC}\n"; }
section() { echo -e "    ${LTEAL}${BOLD}◈  $*${NC}\n"; }
item() { echo -e "    ${TEAL}▸${NC}  $*"; }
ok()   { echo -e "    ${GREEN}✓${NC}  $*"; }
warn() { echo -e "    ${YELLOW}⚠${NC}  $*"; }
fail() { echo -e "\n    ${RED}✗  $*${NC}\n" >&2; exit 1; }
info() { echo -e "    ${DIM}   $*${NC}"; }
link() { echo -e "    ${TEAL}→${NC}  ${DIM}$*${NC}"; }
code() { echo -e "      ${DIM}$*${NC}"; }

# ── Interactive helpers ───────────────────────────────────────────────────────

ask() {
  # ask VARNAME "Prompt text" [default]
  local var="$1" msg="$2" default="${3:-}" val
  echo ""
  if [[ -n "${default}" ]]; then
    echo -en "    ${LTEAL}?${NC}  ${msg} ${DIM}[${default}]${NC}: "
  else
    echo -en "    ${LTEAL}?${NC}  ${msg}: "
  fi
  read -r val
  val="${val:-${default}}"
  [[ -n "${val}" ]] || fail "A value is required."
  eval "${var}='${val}'"
}

confirm() {
  # confirm "Message" [y|n]  — returns 0 for yes, 1 for no
  local msg="$1" default="${2:-y}" hint choice
  [[ "${default}" == "y" ]] && hint="Y/n" || hint="y/N"
  echo ""
  echo -en "    ${LTEAL}?${NC}  ${msg} ${DIM}[${hint}]${NC}: "
  read -r choice
  choice="${choice:-${default}}"
  [[ $(echo "${choice}" | tr '[:upper:]' '[:lower:]') == "y" ]]
}

pick() {
  # pick VARNAME "Title" "Opt 1" "Opt 2" ...
  local var="$1"; shift
  local title="$1"; shift
  local opts=("$@") n
  echo ""
  echo -e "    ${LTEAL}?${NC}  ${title}"
  echo ""
  for i in "${!opts[@]}"; do
    printf "      ${TEAL}%d${NC}  %s\n" "$((i+1))" "${opts[$i]}"
  done
  echo ""
  while true; do
    echo -en "    ${DIM}Enter number [1–${#opts[@]}]${NC}: "
    read -r n
    if [[ "${n}" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#opts[@]} )); then
      echo -e "    ${GREEN}✓${NC}  ${opts[$((n-1))]}"
      eval "${var}='${opts[$((n-1))]}'"
      return
    fi
    warn "Enter a number between 1 and ${#opts[@]}"
  done
}

multiselect() {
  # multiselect ARRAY_VARNAME "Title" "opt1" "opt2" ...
  # Displays a toggle list; all selected by default.
  # Sets the named variable to a bash array of selected items.
  local var="$1"; shift
  local title="$1"; shift
  local opts=("$@")
  local sel=() input i idx

  for _ in "${opts[@]}"; do sel+=("y"); done   # all on by default

  echo ""
  echo -e "    ${LTEAL}?${NC}  ${title}"
  echo -e "    ${DIM}   Type a number to toggle · Enter to confirm (all selected by default)${NC}"

  while true; do
    echo ""
    for i in "${!opts[@]}"; do
      if [[ "${sel[$i]}" == "y" ]]; then
        printf "      ${GREEN}[✓]${NC} %d  %s\n" "$((i+1))" "${opts[$i]}"
      else
        printf "      ${DIM}[ ]${NC} %d  %s\n" "$((i+1))" "${opts[$i]}"
      fi
    done
    echo ""
    echo -en "    ${DIM}Toggle number or press Enter to confirm:${NC} "
    read -r input

    if [[ -z "${input}" ]]; then
      break
    elif [[ "${input}" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= ${#opts[@]} )); then
      idx=$((input - 1))
      [[ "${sel[$idx]}" == "y" ]] && sel[$idx]="n" || sel[$idx]="y"
      # Move cursor back up past the list + blank lines
      local lines=$(( ${#opts[@]} + 3 ))
      for (( l=0; l<lines; l++ )); do printf '\033[1A\033[2K'; done
    else
      warn "Enter a number between 1 and ${#opts[@]}, or press Enter to confirm."
    fi
  done

  local result=()
  for i in "${!opts[@]}"; do
    [[ "${sel[$i]}" == "y" ]] && result+=("${opts[$i]}")
  done
  eval "${var}=(\"\${result[@]}\")"
}

# ── Prerequisites ─────────────────────────────────────────────────────────────

TF_AVAILABLE=false

check_prereqs() {
  section "Prerequisites"
  local all_ok=true
  for cmd in gh jq git; do
    if command -v "${cmd}" &>/dev/null; then
      local ver
      ver=$(${cmd} --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
      ok "${cmd}${ver:+  (${ver})}"
    else
      warn "${cmd} not found — please install it before continuing"
      all_ok=false
    fi
  done
  if command -v terraform &>/dev/null; then
    local ver
    ver=$(terraform version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
    ok "terraform${ver:+  (${ver})}"
    TF_AVAILABLE=true
  else
    warn "terraform not found — Azure bootstrap will need a separate run"
  fi
  [[ "${all_ok}" == "true" ]] || fail "Install missing prerequisites and re-run."
}

# ── GitHub authentication ─────────────────────────────────────────────────────

github_auth() {
  sep
  section "GitHub Authentication"
  if gh auth status &>/dev/null 2>&1; then
    local user
    user=$(gh api /user --jq '.login' 2>/dev/null)
    ok "Authenticated as ${BOLD}${user}${NC}"
    echo ""
    if ! confirm "Continue as ${user}?"; then
      item "Re-authenticating..."
      gh auth logout --hostname github.com 2>/dev/null || true
      _do_auth
    fi
  else
    _do_auth
  fi
}

_do_auth() {
  item "Starting GitHub device authentication..."
  echo ""
  info "A code will be shown. Visit ${BOLD}https://github.com/login/device${NC} and enter it."
  echo ""
  # Try web first, fall back to device code
  gh auth login \
    --hostname github.com \
    --git-protocol https \
    --scopes "repo,workflow,read:org,admin:org" \
    --web 2>/dev/null || \
  gh auth login \
    --hostname github.com \
    --git-protocol https \
    --scopes "repo,workflow,read:org,admin:org" || \
  fail "Authentication failed. Try running 'gh auth login' manually."
  local user
  user=$(gh api /user --jq '.login' 2>/dev/null)
  ok "Authenticated as ${BOLD}${user}${NC}"
}

# ── State ─────────────────────────────────────────────────────────────────────

ORG=""
PRODUCT_NAME=""
SELECTED_CONSTRUCT_REPOS=()
ALL_CONSTRUCT_REPOS=(infra-python infra-typescript infra-csharp infra-java infra-go)
PLATFORM_REPOS=(terraform-modules reusable-workflows)

# ── Organization ──────────────────────────────────────────────────────────────

setup_org() {
  sep
  section "GitHub Organization"
  ask ORG "Organization slug"
  item "Validating..."
  if ! gh api "/orgs/${ORG}" &>/dev/null 2>&1; then
    fail "Organization '${ORG}' not found or not accessible with current credentials."
  fi
  ok "github.com/${ORG}"
}

# ── Platform team ─────────────────────────────────────────────────────────────

ensure_team() {
  sep
  section "Platform Team"
  local slug="platform-infra"
  if gh api "/orgs/${ORG}/teams/${slug}" &>/dev/null 2>&1; then
    ok "Team '${slug}' already exists"
  else
    item "Creating team '${slug}'..."
    gh api --method POST "/orgs/${ORG}/teams" \
      -f name="${slug}" \
      -f description="Nautilus platform engineering team" \
      -f privacy="closed" > /dev/null
    ok "Team '${slug}' created"
  fi
  local me
  me=$(gh api /user --jq '.login')
  gh api --method PUT "/orgs/${ORG}/teams/${slug}/memberships/${me}" \
    -f role="maintainer" > /dev/null 2>&1 || true
  ok "Added ${me} as maintainer"
}

# ── Repo selection ────────────────────────────────────────────────────────────

select_repos() {
  sep
  section "Repository Configuration"

  echo -e "    ${DIM}Platform repos (always included):${NC}"
  for r in "${PLATFORM_REPOS[@]}"; do info "• ${r}"; done
  echo ""

  multiselect SELECTED_CONSTRUCT_REPOS \
    "Select construct libraries to include:" \
    "${ALL_CONSTRUCT_REPOS[@]}"

  if [[ ${#SELECTED_CONSTRUCT_REPOS[@]} -eq 0 ]]; then
    warn "No construct libraries selected — defaulting to all"
    SELECTED_CONSTRUCT_REPOS=("${ALL_CONSTRUCT_REPOS[@]}")
  fi

  sep
  section "First Product Team"
  ask PRODUCT_NAME "Product name (e.g. portal)" "portal"
  ok "Product repo: ${PRODUCT_NAME}-infra"
}

# ── Create repos ──────────────────────────────────────────────────────────────

create_repos() {
  sep
  section "Creating Repositories"
  local all=("${PLATFORM_REPOS[@]}" "${SELECTED_CONSTRUCT_REPOS[@]}" "${PRODUCT_NAME}-infra")
  for repo in "${all[@]}"; do
    if gh api "/repos/${ORG}/${repo}" &>/dev/null 2>&1; then
      warn "${repo} — already exists, skipping"
    else
      gh api --method POST "/orgs/${ORG}/repos" \
        -f name="${repo}" \
        -f private=false \
        -f auto_init=false > /dev/null
      ok "github.com/${ORG}/${repo}"
    fi
  done
}

# ── Push code ─────────────────────────────────────────────────────────────────

push_code() {
  sep
  section "Pushing Code"

  _push_subdir "${PROJECT_ROOT}/tf-modules"           "terraform-modules"
  _push_subdir "${PROJECT_ROOT}/reusable-workflows"   "reusable-workflows"

  for lang_repo in "${SELECTED_CONSTRUCT_REPOS[@]}"; do
    local lang="${lang_repo#infra-}"
    _push_subdir "${PROJECT_ROOT}/constructs/${lang}"  "${lang_repo}"
  done

  _push_subdir "${PROJECT_ROOT}/tf-azure"             "${PRODUCT_NAME}-infra"
}

_push_subdir() {
  local src="$1" repo="$2"
  # Skip if repo already has commits
  local commit_count
  commit_count=$(gh api "/repos/${ORG}/${repo}/commits" --jq 'length' 2>/dev/null || echo "0")
  if (( commit_count > 0 )); then
    warn "${repo} — already has commits, skipping push"
    return
  fi
  if [[ ! -d "${src}" ]]; then
    warn "${repo} — source directory not found (${src}), skipping"
    return
  fi
  item "${repo}..."
  local tmp
  tmp=$(mktemp -d)
  cp -r "${src}/." "${tmp}/"
  (
    cd "${tmp}"
    git init -q
    git checkout -q -b main
    git add -A
    git commit -q -m "Initial commit — Nautilus"
    git remote add origin "https://github.com/${ORG}/${repo}.git"
    git push -q -u origin main 2>&1 | grep -v "^$" || true
  )
  rm -rf "${tmp}"
  ok "${repo}"
}

# ── Apply configurations ──────────────────────────────────────────────────────

apply_configs() {
  sep
  section "Applying Repository Configurations"
  _run_config "terraform-modules"  "terraform-modules.json"
  _run_config "reusable-workflows" "reusable-workflows.json"
  for lang_repo in "${SELECTED_CONSTRUCT_REPOS[@]}"; do
    _run_config "${lang_repo}" "construct-library.json"
  done
  _run_config "${PRODUCT_NAME}-infra" "product-team.json"
}

_run_config() {
  local repo="$1" config="$2"
  item "${repo}..."
  local exit_code=0
  bash "${APPLY_SCRIPT}" "${ORG}" "${repo}" "${CONFIGS_DIR}/${config}" 2>&1 | \
    grep -oP '(?<=\[OK\]  )\S.*|(?<=\[WARN\]  )\S.*' | \
    while IFS= read -r line; do
      echo -e "         ${DIM}${line}${NC}"
    done || true
  # Re-run to capture exit code (subshell above consumed it)
  bash "${APPLY_SCRIPT}" "${ORG}" "${repo}" "${CONFIGS_DIR}/${config}" > /dev/null 2>&1 || exit_code=$?
  if [[ "${exit_code}" -eq 0 ]]; then
    ok "${repo}"
  else
    warn "${repo} — partial config; check output manually"
  fi
}

# ── Azure bootstrap guidance ──────────────────────────────────────────────────

azure_guidance() {
  sep
  section "Azure Bootstrap"

  if [[ "${TF_AVAILABLE}" == "false" ]]; then
    warn "Terraform is not installed — complete this step separately."
    echo ""
    info "Install Terraform ≥ 1.7, then run:"
    echo ""
    code "cd bootstrap/platform"
    code "terraform init"
    code "terraform apply \\"
    code "  -var=\"platform_subscription_id=<your-sub-id>\" \\"
    code "  -var=\"github_org=${ORG}\" \\"
    code "  -var=\"github_repo=project-nautilus\""
    echo ""
    info "Full guide: wiki/bootstrap.md"
    return
  fi

  echo -e "    ${DIM}The Azure bootstrap creates the Terraform state backend, platform"
  echo -e "    service principal, and OIDC federated credential. It requires an active"
  echo -e "    'az login' session with Owner access on the platform subscription.${NC}"
  echo ""

  if confirm "Run Azure platform bootstrap now?"; then
    ask PLATFORM_SUB "Platform Azure subscription ID"
    item "Running bootstrap/platform..."
    (
      cd "${PROJECT_ROOT}/bootstrap/platform"
      terraform init
      terraform apply \
        -var="platform_subscription_id=${PLATFORM_SUB}" \
        -var="github_org=${ORG}" \
        -var="github_repo=project-nautilus"
    )
    ok "Platform bootstrap complete"
    echo ""
    info "Copy the 'next_steps' output values into GitHub Actions secrets on"
    info "github.com/${ORG}/project-nautilus/settings/secrets/actions"

    if confirm "Run product team bootstrap for '${PRODUCT_NAME}' now?"; then
      ask DEV_SUB   "dev subscription ID"
      ask QA_SUB    "qa subscription ID"
      ask STAGE_SUB "stage subscription ID"
      ask PROD_SUB  "prod subscription ID"
      ask STATE_ID  "state_storage_account_id (from platform output)"
      item "Running bootstrap/product-team..."
      (
        cd "${PROJECT_ROOT}/bootstrap/product-team"
        terraform init \
          -backend-config="storage_account_name=platformtfstate" \
          -backend-config="container_name=tfstate" \
          -backend-config="key=bootstrap/${PRODUCT_NAME}/terraform.tfstate" \
          -backend-config="use_oidc=true"
        terraform apply \
          -var="product_name=${PRODUCT_NAME}" \
          -var="github_org=${ORG}" \
          -var="github_repo=${PRODUCT_NAME}-infra" \
          -var="{\"dev\":\"${DEV_SUB}\",\"qa\":\"${QA_SUB}\",\"stage\":\"${STAGE_SUB}\",\"prod\":\"${PROD_SUB}\"}" \
          -var="state_storage_account_id=${STATE_ID}" \
          -var="platform_subscription_id=${PLATFORM_SUB}"
        echo ""
        info "GitHub secrets to set on ${PRODUCT_NAME}-infra:"
        terraform output github_secrets
      )
      ok "Product team bootstrap complete"
    fi
  else
    info "Skipped. Run the bootstrap when ready — see wiki/bootstrap.md"
  fi
}

# ── Product team onboarding ───────────────────────────────────────────────────

onboard_product_team() {
  sep
  section "Onboard Product Team"

  ask NEW_PRODUCT "Product name (e.g. billing)"
  local new_repo="${NEW_PRODUCT}-infra"

  item "Creating github.com/${ORG}/${new_repo}..."
  if gh api "/repos/${ORG}/${new_repo}" &>/dev/null 2>&1; then
    warn "Repo already exists — skipping creation"
  else
    gh api --method POST "/orgs/${ORG}/repos" \
      -f name="${new_repo}" \
      -f private=false \
      -f auto_init=false > /dev/null
    ok "Repo created"
    _push_subdir "${PROJECT_ROOT}/tf-azure" "${new_repo}"
  fi

  item "Applying configuration..."
  bash "${APPLY_SCRIPT}" "${ORG}" "${new_repo}" "${CONFIGS_DIR}/product-team.json" > /dev/null 2>&1 || true
  ok "${new_repo} configured"

  sep
  echo -e "    ${LTEAL}Next steps for ${NEW_PRODUCT}:${NC}\n"
  item "Run the product-team bootstrap:"
  code "cd bootstrap/product-team"
  code "terraform init -backend-config=\"key=bootstrap/${NEW_PRODUCT}/terraform.tfstate\" \\"
  code "  [other backend-config flags]"
  code "terraform apply -var=\"product_name=${NEW_PRODUCT}\" -var=\"github_org=${ORG}\" \\"
  code "  -var=\"github_repo=${new_repo}\" [other vars]"
  echo ""
  item "Copy the output secrets to github.com/${ORG}/${new_repo}/settings/secrets"
  echo ""
  item "Generate an SSH deploy key for terraform-modules:"
  code "ssh-keygen -t ed25519 -C \"github-actions@${ORG}/${new_repo}\" -f /tmp/tf_key"
  code "gh secret set TF_MODULES_DEPLOY_KEY --repo ${ORG}/${new_repo} --body \"\$(cat /tmp/tf_key)\""
}

# ── Summary ───────────────────────────────────────────────────────────────────

print_summary() {
  sep
  echo -e "    ${LTEAL}${BOLD}🐚  Nautilus is live in github.com/${ORG}${NC}"
  sep
  echo -e "    ${LTEAL}Repositories${NC}\n"
  for repo in "${PLATFORM_REPOS[@]}" "${SELECTED_CONSTRUCT_REPOS[@]}" "${PRODUCT_NAME}-infra"; do
    link "github.com/${ORG}/${repo}"
  done
  echo ""
  echo -e "    ${LTEAL}Remaining steps${NC}\n"
  item "Azure platform bootstrap  (creates state backend + platform SP):"
  code "cd bootstrap/platform && terraform init && terraform apply \\"
  code "  -var=\"platform_subscription_id=<sub-id>\" -var=\"github_org=${ORG}\" \\"
  code "  -var=\"github_repo=project-nautilus\""
  echo ""
  item "Provision OIDC credentials for ${PRODUCT_NAME}-infra:"
  code "cd bootstrap/product-team && terraform apply -var=\"product_name=${PRODUCT_NAME}\" ..."
  code "terraform output github_secrets   # paste into ${PRODUCT_NAME}-infra secrets"
  echo ""
  item "Generate SSH deploy key:"
  code "ssh-keygen -t ed25519 -C \"github-actions@${ORG}/terraform-modules\" -f /tmp/tf_key"
  code "gh secret set TF_MODULES_DEPLOY_KEY --repo ${ORG}/${PRODUCT_NAME}-infra --body \"\$(cat /tmp/tf_key)\""
  echo ""
  item "Full documentation:"
  link "wiki/bootstrap.md"
  link "wiki/platform-product-maintenance.md"
  echo ""
  sep
  echo -e "    ${DIM}Set your platform team as required reviewers on the 'stage' and 'prod'"
  echo -e "    environments in github.com/${ORG}/${PRODUCT_NAME}-infra/settings/environments${NC}"
  echo -e "    ${DIM}(requires GitHub Team plan or higher)${NC}"
  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  print_banner
  check_prereqs
  github_auth

  local MODE
  pick MODE "What would you like to do?" \
    "Full Nautilus setup  (first-time, end-to-end)" \
    "GitHub repos & config only  (skip Azure guidance)" \
    "Onboard a new product team  (add team to existing Nautilus)" \
    "Exit"
  echo ""

  case "${MODE}" in
    "Full Nautilus setup"*)
      setup_org
      ensure_team
      select_repos
      create_repos
      push_code
      apply_configs
      azure_guidance
      print_summary
      ;;
    "GitHub repos"*)
      setup_org
      ensure_team
      select_repos
      create_repos
      push_code
      apply_configs
      sep
      ok "GitHub setup complete."
      echo ""
      info "Run wiki/bootstrap.md steps when Azure credentials are ready."
      echo ""
      ;;
    "Onboard"*)
      setup_org
      onboard_product_team
      ;;
    "Exit")
      echo ""
      info "See wiki/bootstrap.md to get started."
      echo ""
      exit 0
      ;;
  esac
}

main "$@"
