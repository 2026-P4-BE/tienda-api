#!/usr/bin/env bash
# One-command classroom exercises. Every scenario applies a known patch, so nobody
# edits Java files in front of the class.
#
#   scripts/demo.sh green-pr            harmless change   -> everything green
#   scripts/demo.sh break-test          one wrong assertion -> red at the test step
#   scripts/demo.sh drop-coverage       delete a test class -> red at the JaCoCo gate (< 80%)
#   scripts/demo.sh pmd-violation       System.out.println  -> red at PMD
#   scripts/demo.sh release [version]   tag v<version> on main (default: the pom.xml version)
#   scripts/demo.sh status              what exists right now
#
# Option --no-push: create the branch and commit locally only (no push, no PR, no tag).
# Undo everything with scripts/reset.sh.

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() { sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

NO_PUSH=0
ARGS=()
for a in "$@"; do
  case "$a" in
    --no-push) NO_PUSH=1 ;;
    -h|--help) usage 0 ;;
    *) ARGS+=("$a") ;;
  esac
done
SCENARIO="${ARGS[0]:-}"
[ -n "$SCENARIO" ] || usage 1

require_cmd git
require_cmd gh
gh auth status > /dev/null 2>&1 || die "gh is not logged in. Run: gh auth login"
REPO="$(detect_repo)"
ORIG_BRANCH="$(current_branch)"
BASE_REF="$BASE_BRANCH"
SWITCHED=0

restore_branch() {
  if [ "$SWITCHED" = 1 ] && [ "$(current_branch)" != "$ORIG_BRANCH" ]; then
    git reset -q --hard 2>/dev/null
    git switch -q "$ORIG_BRANCH" 2>/dev/null
  fi
}
trap restore_branch EXIT

# --- helpers ---------------------------------------------------------------

open_pr_url() { gh pr list --repo "$REPO" --head "$1" --state open --json url --jq '.[0].url // empty' 2>/dev/null; }

# Prepares a demo branch from develop. Exits 0 with an explanation if it already exists.
start_branch() {
  local branch="$1"
  working_tree_clean || die "The working tree has uncommitted changes. Commit or stash them first (git status)."

  if git show-ref --verify --quiet "refs/heads/$branch" || remote_branch_exists "$REPO" "$branch"; then
    info "The branch '$branch' already exists, nothing was changed."
    local url
    url="$(open_pr_url "$branch")"
    [ -n "$url" ] && info "Open PR: $url" || info "No open PR for it. Run scripts/reset.sh to start from scratch."
    info "Repeat the exercise from zero with: scripts/reset.sh"
    exit 0
  fi

  if [ "$NO_PUSH" = 0 ]; then
    gh_git fetch -q origin || die "Cannot fetch from origin (network or permissions)."
  fi
  if git show-ref --verify --quiet "refs/remotes/origin/$BASE_BRANCH"; then
    BASE_REF="origin/$BASE_BRANCH"
  fi
  git switch -q -c "$branch" "$BASE_REF" || die "Cannot create '$branch' from '$BASE_REF'."
  SWITCHED=1
}

# Commits the patch, pushes the branch and opens the PR against develop.
finish_branch() {
  local branch="$1" commit_msg="$2" pr_title="$3" watch="$4"
  [ -n "$(git status --porcelain)" ] \
    || die "The patch changed nothing (the code probably diverged from what this script expects)."
  git add -A 2>/dev/null
  git commit -q -m "$commit_msg" || die "git commit failed (is user.name / user.email configured?)."
  ok "Created '$branch' from $BASE_REF with 1 commit: $commit_msg"

  if [ "$NO_PUSH" = 1 ]; then
    info "--no-push: stopping here (local branch only)."
    return
  fi

  gh_git push -q -u origin "$branch" || die "Push failed. If it says 'workflow scope', run: gh auth refresh -h github.com -s workflow"
  ok "Pushed '$branch'"

  local url
  url="$(gh pr create --repo "$REPO" --base "$BASE_BRANCH" --head "$branch" \
    --title "$DEMO_PR_PREFIX $pr_title" \
    --body "Classroom demo created by scripts/demo.sh. Safe to close: scripts/reset.sh removes it." 2>&1 | tail -n 1)"
  ok "Opened PR: $url"
  ensure_runs "$branch" ci.yml codeql.yml
  echo
  info "Open:   $url"
  info "Actions: https://github.com/$REPO/actions"
  info "Watch:  $watch"
  info "Then:   scripts/reset.sh (back to the initial state)"
}

# GitHub normally starts the workflows by itself on push / PR / tag. If no run shows up shortly
# (it was observed on a fresh repository), start them manually so the class is not blocked.
ensure_runs() {
  local ref="$1"; shift
  local wf n
  for wf in "$@"; do
    n=0
    for _ in 1 2 3 4 5 6 7 8; do
      n=$(gh run list --repo "$REPO" --workflow "$wf" --branch "$ref" --limit 1 --json databaseId --jq length 2>/dev/null)
      [ "${n:-0}" -gt 0 ] && break
      sleep 4
    done
    if [ "${n:-0}" -eq 0 ]; then
      warn "No $wf run started by GitHub for $ref; starting it with workflow_dispatch."
      gh workflow run "$wf" --repo "$REPO" --ref "$ref" > /dev/null 2>&1 || warn "Could not dispatch $wf (is the workflow on that ref?)."
    fi
  done
}

# --- scenarios -------------------------------------------------------------

scenario_green_pr() {
  local branch="feature/demo-green-pr"
  start_branch "$branch"
  mkdir -p docs/demo
  printf '# Classroom demo\n\nHarmless change created by scripts/demo.sh green-pr on %s.\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > docs/demo/green-pr.md
  finish_branch "$branch" "docs: add classroom demo note" "green-pr: harmless docs change" \
    "CI (build-test then package) and CodeQL green on the PR; open the CI run to see the job summary and the reports artifact."
}

scenario_break_test() {
  local branch="demo/break-test"
  start_branch "$branch"
  local f="src/test/java/ar/edu/utn/frc/tienda/product/ProductServiceTest.java"
  sed -i '/void createSavesNewProduct/,/isEqualTo(5)/ s/isEqualTo(5)/isEqualTo(6)/' "$f"
  finish_branch "$branch" "test: break one assertion (classroom demo)" "break-test: wrong assertion in ProductServiceTest" \
    "Job 'Build, test and quality gates' red at 'Verify' (expected: 6 but was: 5); job 'Package' is skipped."
}

scenario_drop_coverage() {
  local branch="demo/drop-coverage"
  start_branch "$branch"
  git rm -q src/test/java/ar/edu/utn/frc/tienda/product/ProductApiIntegrationTest.java
  finish_branch "$branch" "test: delete the integration test (classroom demo)" "drop-coverage: integration test removed" \
    "Remaining tests pass but 'Verify' fails: 'Rule violated for bundle tienda-api: lines covered ratio is 0.66, but expected minimum is 0.80'."
}

scenario_pmd_violation() {
  local branch="demo/pmd-violation"
  start_branch "$branch"
  sed -i '/public List<Product> findAll() {/a\        System.out.println("listing");' \
    src/main/java/ar/edu/utn/frc/tienda/product/ProductService.java
  finish_branch "$branch" "refactor: log with System.out (classroom demo)" "pmd-violation: System.out.println in ProductService" \
    "Tests and coverage pass, 'Verify' fails on PMD: rule SystemPrintln in ProductService.java. PMD report is in the artifacts."
}

scenario_release() {
  local pom_ref="$PROD_BRANCH" tag_ref="$PROD_BRANCH"
  if [ "$NO_PUSH" = 0 ]; then
    gh_git fetch -q origin || die "Cannot fetch from origin (network or permissions)."
  fi
  if git show-ref --verify --quiet "refs/remotes/origin/$PROD_BRANCH"; then
    tag_ref="origin/$PROD_BRANCH"; pom_ref="$tag_ref"
  fi
  local pom_version version tag
  pom_version="$(pom_version_at "$pom_ref")"
  version="${ARGS[1]:-$pom_version}"
  version="${version#v}"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "'$version' is not a MAJOR.MINOR.PATCH version (example: 1.0.0)."
  tag="v$version"

  if remote_tag_exists "$REPO" "$tag" || git rev-parse -q --verify "refs/tags/$tag" > /dev/null; then
    info "The tag '$tag' already exists, nothing was changed."
    info "Releases: https://github.com/$REPO/releases/tag/$tag"
    info "Repeat the exercise from zero with: scripts/reset.sh"
    exit 0
  fi

  git tag -a "$tag" "$tag_ref" -m "$DEMO_TAG_MARKER release $version created by scripts/demo.sh"
  ok "Created annotated tag $tag on $tag_ref ($(git rev-parse --short "$tag_ref"))"
  if [ "$NO_PUSH" = 1 ]; then
    info "--no-push: tag kept locally only."
    return
  fi
  gh_git push -q origin "refs/tags/$tag" || die "Pushing the tag failed. If it says 'workflow scope', run: gh auth refresh -h github.com -s workflow"
  ensure_runs "$tag" release.yml
  ok "Pushed $tag"
  echo
  info "Actions:  https://github.com/$REPO/actions/workflows/release.yml"
  if [ "$version" = "$pom_version" ]; then
    info "Watch:    release job (verify, image to ghcr.io, GitHub Release), then deploy-staging runs alone,"
    info "          then deploy-production WAITS for approval (Review deployments)."
    info "Then:     Releases: https://github.com/$REPO/releases/tag/$tag"
    info "          Packages: https://github.com/$REPO/pkgs/container/tienda-api"
  else
    warn "pom.xml says $pom_version but the tag is $tag: this run is EXPECTED to fail at"
    info "          'Check that the Git tag matches the pom.xml version' and publish nothing."
  fi
  info "Then:     scripts/reset.sh (deletes the tag and the Release so you can repeat it)"
}

scenario_status() {
  info "Repository: https://github.com/$REPO   (local branch: $ORIG_BRANCH)"
  echo
  info "Demo branches (remote):"
  local any=0 r
  for g in "heads/demo/" "heads/feature/demo-"; do
    for r in $(gh api "repos/$REPO/git/matching-refs/$g" --jq '.[].ref' 2>/dev/null | grep '^refs/'); do
      info "  ${r#refs/heads/}"; any=1
    done
  done
  [ "$any" = 1 ] || info "  (none)"
  echo
  info "Open PRs:"
  gh pr list --repo "$REPO" --state open --json number,title,url,statusCheckRollup \
    --jq '.[] | "  #\(.number) \(.title)  [" + ([.statusCheckRollup[]? | (.conclusion // .status)] | join(",")) + "]  \(.url)"' 2>/dev/null || true
  echo
  info "Tags:"
  any=0
  for r in $(gh api "repos/$REPO/git/matching-refs/tags/" --jq '.[].ref' 2>/dev/null | grep '^refs/'); do
    info "  ${r#refs/tags/}"; any=1
  done
  [ "$any" = 1 ] || info "  (none)"
  echo
  info "Latest runs:"
  gh run list --repo "$REPO" --limit 8 --json workflowName,headBranch,status,conclusion,displayTitle \
    --jq '.[] | "  \(.workflowName)  \(.headBranch)  \(.status)/\(.conclusion)"' 2>/dev/null || true
}

case "$SCENARIO" in
  green-pr)       scenario_green_pr ;;
  break-test)     scenario_break_test ;;
  drop-coverage)  scenario_drop_coverage ;;
  pmd-violation)  scenario_pmd_violation ;;
  release)        scenario_release ;;
  status)         scenario_status ;;
  *) echo "Unknown scenario: $SCENARIO" >&2; usage 1 ;;
esac
