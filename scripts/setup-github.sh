#!/usr/bin/env bash
# One-time GitHub setup for a fresh clone or fork. Idempotent.
#
#   scripts/setup-github.sh [owner/name] [--private]    default: <logged-in user>/tienda-api, public
#
# 1. creates the repository if it does not exist (public unless --private; CodeQL and required reviewers on a free account need a public repo)
# 2. pushes main and develop
# 3. creates the 'staging' and 'production' environments; the logged-in user becomes
#    required reviewer of 'production' (self-review allowed, so the teacher can approve their own demo)
#
# Pushing .github/workflows needs the 'workflow' scope: gh auth refresh -h github.com -s workflow

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VISIBILITY="--public"
REPO=""
for a in "$@"; do
  case "$a" in
    --private) VISIBILITY="--private" ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    */*) REPO="$a" ;;
    *) die "Unknown argument: $a" ;;
  esac
done

require_cmd git
require_cmd gh
gh auth status > /dev/null 2>&1 || die "gh is not logged in. Run: gh auth login"
gh auth status 2>&1 | grep -q "workflow" || warn "The gh token lacks the 'workflow' scope; the push will be rejected. Run: gh auth refresh -h github.com -s workflow"

LOGIN="$(gh api user --jq .login)"
USER_ID="$(gh api user --jq .id)"
REPO="${REPO:-$LOGIN/tienda-api}"

if gh api "repos/$REPO" --silent > /dev/null 2>&1; then
  info "Repository $REPO already exists: reusing it."
else
  gh repo create "$REPO" "$VISIBILITY" --description "Teaching repo: Spring Boot products API with a full CI/CD pipeline on GitHub Actions (UTN Programacion IV, Unit 5)" > /dev/null
  ok "Created repository $REPO ($VISIBILITY)"
fi

if git remote get-url origin > /dev/null 2>&1; then
  info "Remote origin: $(git remote get-url origin)"
else
  git remote add origin "https://github.com/$REPO.git"
  ok "Added remote origin"
fi

gh_git push -u origin main develop || die "Push failed. If it mentions the 'workflow' scope: gh auth refresh -h github.com -s workflow"
ok "Pushed main and develop"

gh api -X PUT "repos/$REPO/environments/staging" --silent && ok "Environment 'staging' ready"
printf '{"prevent_self_review":false,"reviewers":[{"type":"User","id":%s}]}' "$USER_ID" \
  | gh api -X PUT "repos/$REPO/environments/production" --input - --silent \
  && ok "Environment 'production' ready, required reviewer: $LOGIN"

info "Next: scripts/doctor.sh"
