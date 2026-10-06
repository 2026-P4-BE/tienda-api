#!/usr/bin/env bash
# Back to the initial state, local and remote, in one command.
#
#   scripts/reset.sh             clean up everything scripts/demo.sh created
#   scripts/reset.sh --dry-run   show what would be done, change nothing
#   scripts/reset.sh --runs      also delete the whole workflow run history (opt-in)
#
# It ONLY touches objects it recognises as created by demo.sh:
#   branches  demo/*  and  feature/demo-*
#   PRs       from those branches, titled "[DEMO] ..."
#   tags      annotated tags whose message starts with "[tienda-api demo]" (and their GitHub Release)
# Anything else is left alone and reported. Safe to run twice.
# Not touched: GHCR package versions (needs the delete:packages scope; re-releasing the same
# version simply overwrites the image tag) and run history (unless --runs).

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

DRY=0
DELETE_RUNS=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --runs) DELETE_RUNS=1 ;;
    -h|--help) sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Unknown option: $a (see --help)" ;;
  esac
done

require_cmd git
require_cmd gh
gh auth status > /dev/null 2>&1 || die "gh is not logged in. Run: gh auth login"
REPO="$(detect_repo)"
REFUSED=0

# run a mutating command, or only print it in --dry-run
act() {
  if [ "$DRY" = 1 ]; then info "  (dry-run) $*"; else "$@"; fi
}

[ "$DRY" = 1 ] && info "DRY RUN: nothing will be changed."
info "Resetting $REPO (local checkout: $REPO_ROOT)"
echo

# --- 1. Discover what is ours ------------------------------------------------

REMOTE_DEMO_BRANCHES=()
for prefix in "heads/demo/" "heads/feature/demo-"; do
  while IFS= read -r ref; do
    [ -n "$ref" ] && REMOTE_DEMO_BRANCHES+=("${ref#refs/heads/}")
  done < <(gh api "repos/$REPO/git/matching-refs/$prefix" --jq '.[].ref' 2>/dev/null | grep '^refs/')
done

REMOTE_DEMO_TAGS=()
REMOTE_FOREIGN_TAGS=()
while IFS=$'\t' read -r ref type sha; do
  [ -n "$ref" ] || continue
  tag="${ref#refs/tags/}"
  msg=""
  if [ "$type" = "tag" ]; then
    msg="$(gh api "repos/$REPO/git/tags/$sha" --jq .message 2>/dev/null | head -n 1)"
  fi
  case "$msg" in
    "$DEMO_TAG_MARKER"*) REMOTE_DEMO_TAGS+=("$tag") ;;
    *) REMOTE_FOREIGN_TAGS+=("$tag") ;;
  esac
done < <(gh api "repos/$REPO/git/matching-refs/tags/" --jq '.[] | [.ref, .object.type, .object.sha] | @tsv' 2>/dev/null | grep '^refs/')

LOCAL_DEMO_TAGS=()
LOCAL_FOREIGN_TAGS=()
while IFS=$'\t' read -r tag type subject; do
  [ -n "$tag" ] || continue
  case "$subject" in
    "$DEMO_TAG_MARKER"*) LOCAL_DEMO_TAGS+=("$tag") ;;
    *) LOCAL_FOREIGN_TAGS+=("$tag") ;;
  esac
done < <(git for-each-ref refs/tags --format='%(refname:short)%09%(objecttype)%09%(contents:subject)')

in_array() { local x="$1"; shift; local e; for e in "$@"; do [ "$e" = "$x" ] && return 0; done; return 1; }

is_demo_tag() {
  # remote verdict wins when the tag exists on the remote
  if in_array "$1" "${REMOTE_DEMO_TAGS[@]}"; then return 0; fi
  if in_array "$1" "${REMOTE_FOREIGN_TAGS[@]}"; then return 1; fi
  in_array "$1" "${LOCAL_DEMO_TAGS[@]}"
}

# --- 2. Cancel in-flight runs of demo branches / demo tags -------------------

info "1/6 In-flight workflow runs"
CANCELLED=0
while IFS=$'\t' read -r id head status; do
  [ -n "$id" ] || continue
  if is_demo_branch "$head" || is_demo_tag "$head"; then
    info "  cancelling run $id ($head, $status)"
    act gh run cancel "$id" --repo "$REPO" > /dev/null 2>&1
    CANCELLED=$((CANCELLED + 1))
  fi
done < <(gh run list --repo "$REPO" --limit 100 --json databaseId,headBranch,status \
  --jq '.[] | select(.status != "completed") | [.databaseId, .headBranch, .status] | @tsv' 2>/dev/null)
[ "$CANCELLED" = 0 ] && info "  nothing in flight"

# A release run that is still finishing could re-create the Release after we delete it.
if [ "$CANCELLED" -gt 0 ] && [ "$DRY" = 0 ]; then
  for _ in $(seq 1 30); do
    pending=$(gh run list --repo "$REPO" --limit 100 --json headBranch,status \
      --jq '[.[] | select(.status != "completed") | .headBranch] | join(" ")' 2>/dev/null)
    busy=0
    for h in $pending; do
      if is_demo_branch "$h" || is_demo_tag "$h"; then busy=1; fi
    done
    [ "$busy" = 0 ] && break
    sleep 2
  done
fi

# --- 3. Close demo PRs -------------------------------------------------------

info "2/6 Demo pull requests"
CLOSED=0
while IFS=$'\t' read -r num head title; do
  [ -n "$num" ] || continue
  if is_demo_branch "$head" && [[ "$title" == "$DEMO_PR_PREFIX"* ]]; then
    info "  closing PR #$num ($head)"
    act gh pr close "$num" --repo "$REPO" --comment "Closed by scripts/reset.sh" > /dev/null
    CLOSED=$((CLOSED + 1))
  else
    warn "  leaving PR #$num alone (not created by demo.sh): $title"
    REFUSED=$((REFUSED + 1))
  fi
done < <(gh pr list --repo "$REPO" --state open --limit 100 --json number,headRefName,title \
  --jq '.[] | [.number, .headRefName, .title] | @tsv' 2>/dev/null)
[ "$CLOSED" = 0 ] && info "  nothing to close"

# --- 4. Delete Releases and tags --------------------------------------------

info "3/6 GitHub Releases and tags"
TOUCHED=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  if is_demo_tag "$rel"; then
    info "  deleting Release $rel"
    act gh release delete "$rel" --repo "$REPO" --yes > /dev/null
    TOUCHED=$((TOUCHED + 1))
  else
    warn "  REFUSING to delete Release '$rel': its tag was not created by demo.sh"
    REFUSED=$((REFUSED + 1))
  fi
done < <(gh release list --repo "$REPO" --limit 100 --json tagName --jq '.[].tagName' 2>/dev/null)

for t in "${REMOTE_DEMO_TAGS[@]}"; do
  info "  deleting remote tag $t"
  act gh api -X DELETE "repos/$REPO/git/refs/tags/$t" --silent
  TOUCHED=$((TOUCHED + 1))
done
for t in "${LOCAL_DEMO_TAGS[@]}"; do
  info "  deleting local tag $t"
  act git tag -d "$t" > /dev/null
  TOUCHED=$((TOUCHED + 1))
done
SEEN_FOREIGN=()
for t in "${REMOTE_FOREIGN_TAGS[@]}" "${LOCAL_FOREIGN_TAGS[@]}"; do
  in_array "$t" "${REMOTE_DEMO_TAGS[@]}" && continue
  in_array "$t" "${LOCAL_DEMO_TAGS[@]}" && continue
  in_array "$t" "${SEEN_FOREIGN[@]}" && continue
  SEEN_FOREIGN+=("$t")
  warn "  REFUSING to delete tag '$t': it was not created by demo.sh (no '$DEMO_TAG_MARKER' annotation)"
  REFUSED=$((REFUSED + 1))
done
[ "$TOUCHED" = 0 ] && info "  nothing to delete"

# --- 5. Delete remote demo branches -----------------------------------------

info "4/6 Remote demo branches"
for b in "${REMOTE_DEMO_BRANCHES[@]}"; do
  info "  deleting remote branch $b"
  act gh api -X DELETE "repos/$REPO/git/refs/heads/$b" --silent
done
[ "${#REMOTE_DEMO_BRANCHES[@]}" = 0 ] && info "  nothing to delete"

# --- 6. Local checkout -------------------------------------------------------

info "5/6 Local checkout"
if working_tree_clean; then
  if [ "$(current_branch)" != "$PROD_BRANCH" ]; then
    info "  switching to $PROD_BRANCH"
    act git switch -q "$PROD_BRANCH"
  fi
  while IFS= read -r b; do
    b="${b#\* }"; b="${b#  }"
    [ -n "$b" ] || continue
    if is_demo_branch "$b"; then
      info "  deleting local branch $b"
      act git branch -D -q "$b" > /dev/null
    fi
  done < <(git branch --list 'demo/*' 'feature/demo-*' | sed 's/^[ *]*//')
  if [ "$DRY" = 0 ]; then
    gh_git fetch -q --prune origin 2> /dev/null || warn "  could not fetch from origin"
    for b in "$PROD_BRANCH" "$BASE_BRANCH"; do
      if git show-ref --verify --quiet "refs/heads/$b" && git show-ref --verify --quiet "refs/remotes/origin/$b"; then
        if git merge-base --is-ancestor "$b" "origin/$b" 2> /dev/null; then
          if [ "$b" = "$(current_branch)" ]; then
            git merge -q --ff-only "origin/$b" 2> /dev/null
          else
            git branch -q -f "$b" "origin/$b"
          fi
        elif ! git merge-base --is-ancestor "origin/$b" "$b" 2> /dev/null; then
          warn "  local $b diverged from origin/$b: left untouched"
          REFUSED=$((REFUSED + 1))
        fi
      fi
    done
  fi
else
  warn "  The working tree has uncommitted changes: local cleanup SKIPPED (commit or stash, then run again)."
  REFUSED=$((REFUSED + 1))
fi

# --- 7. Optional: run history -----------------------------------------------

info "6/6 Workflow run history"
if [ "$DELETE_RUNS" = 1 ]; then
  N=0
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    act gh run delete "$id" --repo "$REPO" > /dev/null 2>&1 && N=$((N + 1))
  done < <(gh run list --repo "$REPO" --limit 500 --status completed --json databaseId --jq '.[].databaseId' 2>/dev/null)
  info "  deleted $N completed run(s)"
else
  info "  kept (pass --runs to delete the completed runs)"
fi

# --- Verification ------------------------------------------------------------

echo
info "State after reset"
BAD=0
check_none() { # label, list...
  local label="$1"; shift
  if [ "$#" = 0 ]; then ok "$label: none"; else fail "$label: $*"; BAD=$((BAD + 1)); fi
}

if [ "$DRY" = 1 ]; then
  info "  (dry-run: verification skipped)"
else
  R_BR=()
  for prefix in "heads/demo/" "heads/feature/demo-"; do
    while IFS= read -r ref; do [ -n "$ref" ] && R_BR+=("${ref#refs/heads/}"); done \
      < <(gh api "repos/$REPO/git/matching-refs/$prefix" --jq '.[].ref' 2>/dev/null | grep '^refs/')
  done
  check_none "remote demo branches" "${R_BR[@]}"

  L_BR=()
  while IFS= read -r b; do [ -n "$b" ] && L_BR+=("$b"); done < <(git branch --list 'demo/*' 'feature/demo-*' | sed 's/^[ *]*//')
  check_none "local demo branches" "${L_BR[@]}"

  PRS=()
  while IFS= read -r l; do [ -n "$l" ] && PRS+=("$l"); done \
    < <(gh pr list --repo "$REPO" --state open --json number,headRefName --jq '.[] | select(.headRefName | test("^(demo/|feature/demo-)")) | "#\(.number)"' 2>/dev/null)
  check_none "open demo PRs" "${PRS[@]}"

  TG=()
  while IFS=$'\t' read -r ref type sha; do
    [ -n "$ref" ] || continue
    m=""; [ "$type" = "tag" ] && m="$(gh api "repos/$REPO/git/tags/$sha" --jq .message 2>/dev/null | head -n 1)"
    case "$m" in "$DEMO_TAG_MARKER"*) TG+=("${ref#refs/tags/}") ;; esac
  done < <(gh api "repos/$REPO/git/matching-refs/tags/" --jq '.[] | [.ref, .object.type, .object.sha] | @tsv' 2>/dev/null | grep '^refs/')
  check_none "remote demo tags" "${TG[@]}"

  LT=()
  while IFS=$'\t' read -r tag type subject; do
    case "$subject" in "$DEMO_TAG_MARKER"*) LT+=("$tag") ;; esac
  done < <(git for-each-ref refs/tags --format='%(refname:short)%09%(objecttype)%09%(contents:subject)')
  check_none "local demo tags" "${LT[@]}"

  RL=()
  while IFS= read -r t; do [ -n "$t" ] && RL+=("$t"); done < <(gh release list --repo "$REPO" --limit 100 --json tagName --jq '.[].tagName' 2>/dev/null)
  check_none "GitHub Releases" "${RL[@]}"

  if [ "$(current_branch)" = "$PROD_BRANCH" ] && working_tree_clean; then
    ok "local checkout: clean, on $PROD_BRANCH"
  else
    fail "local checkout: on '$(current_branch)', tree $(working_tree_clean && echo clean || echo DIRTY)"
    BAD=$((BAD + 1))
  fi
fi

echo
if [ "$DRY" = 1 ]; then
  info "Dry run finished."
elif [ "$BAD" = 0 ] && [ "$REFUSED" = 0 ]; then
  ok "Initial state restored. (Run history and GHCR image versions are kept on purpose.)"
else
  fail "Not fully clean: $BAD check(s) failed, $REFUSED item(s) refused or skipped. Read the messages above."
  exit 1
fi
