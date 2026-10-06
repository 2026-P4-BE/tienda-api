#!/usr/bin/env bash
# Pre-class check (a few seconds). Exit code 0 = ready to teach, 1 = something to fix.
#
#   scripts/doctor.sh

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FAILS=0
check() { # label, status (0 = ok), hint
  if [ "$2" = 0 ]; then ok "$1"; else fail "$1"; [ -n "${3:-}" ] && info "       -> $3"; FAILS=$((FAILS + 1)); fi
}

require_cmd git
require_cmd gh

# 1. gh session
if gh auth status > /dev/null 2>&1; then
  check "gh is logged in" 0
  if gh auth status 2>&1 | grep -q "workflow"; then
    check "gh token has the 'workflow' scope (needed to push .github/workflows)" 0
  else
    check "gh token has the 'workflow' scope (needed to push .github/workflows)" 1 "gh auth refresh -h github.com -s workflow"
  fi
else
  check "gh is logged in" 1 "gh auth login"
  echo; fail "Cannot continue without gh."; exit 1
fi

# 2. remote
if ! git remote get-url origin > /dev/null 2>&1; then
  check "origin remote configured" 1 "scripts/setup-github.sh"
  echo; fail "Cannot continue without a remote."; exit 1
fi
REPO="$(detect_repo)"
VIS="$(gh api "repos/$REPO" --jq .visibility 2>/dev/null)"
check "repository $REPO is reachable" "$([ -n "$VIS" ] && echo 0 || echo 1)" "check the origin URL and your network"
check "repository is public (CodeQL and required reviewers need it)" "$([ "$VIS" = public ] && echo 0 || echo 1)" "Settings > General > Change visibility"
check "branch main exists on GitHub" "$(remote_branch_exists "$REPO" main && echo 0 || echo 1)" "scripts/setup-github.sh"
check "branch develop exists on GitHub" "$(remote_branch_exists "$REPO" develop && echo 0 || echo 1)" "scripts/setup-github.sh"

# 3. Actions + environments
ACTIONS_ENABLED="$(gh api "repos/$REPO/actions/permissions" --jq .enabled 2>/dev/null)"
check "GitHub Actions enabled" "$([ "$ACTIONS_ENABLED" = true ] && echo 0 || echo 1)" "Settings > Actions > General"
ENVS="$(gh api "repos/$REPO/environments" --jq '.environments[].name' 2>/dev/null | tr '\n' ' ')"
case " $ENVS" in *" staging "*) E1=0 ;; *) E1=1 ;; esac
case " $ENVS" in *" production "*) E2=0 ;; *) E2=1 ;; esac
check "environment 'staging' exists" "$E1" "scripts/setup-github.sh"
check "environment 'production' exists" "$E2" "scripts/setup-github.sh"
REVIEWERS="$(gh api "repos/$REPO/environments/production" --jq '[.protection_rules[]? | select(.type == "required_reviewers") | .reviewers[].reviewer.login] | join(",")' 2>/dev/null)"
check "'production' requires a reviewer (${REVIEWERS:-none})" "$([ -n "$REVIEWERS" ] && echo 0 || echo 1)" "scripts/setup-github.sh"

# 4. Local checkout
check "on branch main (now: $(current_branch))" "$([ "$(current_branch)" = main ] && echo 0 || echo 1)" "git switch main, or scripts/reset.sh"
check "working tree clean" "$(working_tree_clean && echo 0 || echo 1)" "git status"
git fetch -q origin 2> /dev/null || gh_git fetch -q origin 2> /dev/null
if git show-ref --verify --quiet refs/remotes/origin/main; then
  check "local main equals origin/main" "$([ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] && echo 0 || echo 1)" "git pull --ff-only (or push your commits)"
fi

# 5. Leftovers from earlier classes
LEFT=()
for prefix in "heads/demo/" "heads/feature/demo-"; do
  while IFS= read -r ref; do [ -n "$ref" ] && LEFT+=("branch ${ref#refs/heads/}"); done \
    < <(gh api "repos/$REPO/git/matching-refs/$prefix" --jq '.[].ref' 2>/dev/null)
done
while IFS= read -r l; do [ -n "$l" ] && LEFT+=("PR $l"); done \
  < <(gh pr list --repo "$REPO" --state open --json number --jq '.[] | "#\(.number)"' 2>/dev/null)
while IFS= read -r l; do [ -n "$l" ] && LEFT+=("tag ${l#refs/tags/}"); done \
  < <(gh api "repos/$REPO/git/matching-refs/tags/" --jq '.[].ref' 2>/dev/null)
while IFS= read -r l; do [ -n "$l" ] && LEFT+=("release $l"); done \
  < <(gh release list --repo "$REPO" --json tagName --jq '.[].tagName' 2>/dev/null)
LOCAL_LEFT="$(git branch --list 'demo/*' 'feature/demo-*' | tr -d ' *\n')"
[ -n "$LOCAL_LEFT" ] && LEFT+=("local branches $LOCAL_LEFT")
check "no leftover demo branches, PRs, tags or releases${LEFT[0]:+ (found: ${LEFT[*]})}" "$([ "${#LEFT[@]}" = 0 ] && echo 0 || echo 1)" "scripts/reset.sh"

# 6. Last CI run on main
LAST="$(gh run list --repo "$REPO" --workflow ci.yml --branch main --limit 1 --json status,conclusion --jq '.[0] | "\(.status)/\(.conclusion)"' 2>/dev/null)"
check "last CI run on main is green (${LAST:-no runs yet})" "$([ "$LAST" = "completed/success" ] && echo 0 || echo 1)" "push to main or re-run: gh workflow run ci.yml / Actions tab"

echo
if [ "$FAILS" = 0 ]; then
  ok "Ready to teach."
else
  fail "$FAILS check(s) failed."
  exit 1
fi
