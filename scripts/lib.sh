#!/usr/bin/env bash
# Shared helpers for the classroom scripts (sourced, never executed directly).
# Requires only what stock Git Bash ships with: bash, git, curl, sed, awk, grep, plus gh.

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: run this script from inside the tienda-api clone." >&2
  exit 1
}
cd "$REPO_ROOT" || exit 1

# --- Naming conventions: this is how the scripts recognise "their" objects ---
BASE_BRANCH="develop"
PROD_BRANCH="main"
DEMO_BRANCH_GLOBS=("demo/*" "feature/demo-*")           # branches created by demo.sh
DEMO_TAG_MARKER="[tienda-api demo]"                     # first words of the annotation of tags created by demo.sh
DEMO_PR_PREFIX="[DEMO]"                                 # title prefix of PRs created by demo.sh

# --- Output helpers ---
if [ -t 1 ]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_RED=""; C_GRN=""; C_YEL=""; C_DIM=""; C_OFF=""
fi
info()  { printf '%s\n' "$*"; }
ok()    { printf '%s[ OK ]%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn()  { printf '%s[WARN]%s %s\n' "$C_YEL" "$C_OFF" "$*"; }
fail()  { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_OFF" "$*"; }
die()   { printf '%sERROR:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

require_cmd() { command -v "$1" > /dev/null 2>&1 || die "'$1' is not installed or not in PATH."; }

# owner/name of the GitHub repository behind 'origin'
detect_repo() {
  local url
  url="$(git remote get-url origin 2>/dev/null)" || die "No 'origin' remote. Run scripts/setup-github.sh first."
  url="${url%.git}"
  url="${url#git@github.com:}"
  url="${url#https://github.com/}"
  url="${url#http://github.com/}"
  case "$url" in
    */*) printf '%s' "$url" ;;
    *) die "Cannot read owner/name from the origin URL." ;;
  esac
}

# git over HTTPS using the token that gh already holds (avoids the Git Credential
# Manager browser prompt, which blocks non-interactive scripts).
gh_git() {
  GIT_TERMINAL_PROMPT=0 git -c credential.helper= -c 'credential.helper=!gh auth git-credential' "$@"
}

is_demo_branch() {
  local g
  for g in "${DEMO_BRANCH_GLOBS[@]}"; do
    # shellcheck disable=SC2254
    case "$1" in $g) return 0 ;; esac
  done
  return 1
}

working_tree_clean() { [ -z "$(git status --porcelain)" ]; }

current_branch() { git rev-parse --abbrev-ref HEAD; }

# version declared in pom.xml at a git ref (skips the <parent> version)
pom_version_at() {
  git show "$1:pom.xml" 2>/dev/null | awk '/<\/parent>/ {p=1; next} p && /<version>/ {gsub(/.*<version>|<\/version>.*/, ""); print; exit}'
}

# Is a ref present on the remote? (uses the REST API, no git credentials needed)
remote_branch_exists() { gh api "repos/$1/branches/$2" --silent > /dev/null 2>&1; }
remote_tag_exists()    { gh api "repos/$1/git/ref/tags/$2" --silent > /dev/null 2>&1; }
