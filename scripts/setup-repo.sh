#!/usr/bin/env bash
#
# setup-repo.sh — bootstrap the butter-bar GitHub project.
#
# Idempotent. Safe to re-run; uses label/milestone/issue names to detect duplicates.
#
# Requires: gh CLI (https://cli.github.com/), authenticated against the
# anonymort/butter-bar repository, and jq.
#
# Usage:
#   ./scripts/setup-repo.sh
#
# What it does:
#   1. Creates labels per .claude/specs/08-issue-workflow.md § Labels
#   2. Creates milestones (v1, v1.1, v1.5, v2, backlog)
#   3. Creates the eight epic issues (one per module from spec 07)
#
# It does NOT create child Feature issues — that's seed-issues.sh.

set -euo pipefail

REPO="${REPO:-anonymort/butter-bar}"

if ! command -v gh >/dev/null; then
  echo "error: gh CLI not found. Install from https://cli.github.com/" >&2
  exit 1
fi

if ! command -v jq >/dev/null; then
  echo "error: jq not found. brew install jq" >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# Labels
# -----------------------------------------------------------------------------

echo "==> Ensuring labels exist..."

# Format: name|description|color (hex without #)
LABELS=(
  # Type
  "type:epic|High-level scope tracker|7057ff"
  "type:feature|Single user-facing capability|0e8a16"
  "type:bug|Defect|d73a4a"
  "type:spike|Time-boxed investigation|fbca04"
  "type:task|Operational or non-feature work|c5def5"

  # Priority
  "priority:p0|Blocking v1 release|b60205"
  "priority:p1|Required for credible v1|d93f0b"
  "priority:p2|Post-v1|fbca04"
  "priority:p3|Nice-to-have / unscheduled|cccccc"

  # Modules (mirror spec 07 modules)
  "module:discovery|Catalogue browse and search|f5c84b"
  "module:playback|Player UX and behaviour|f5c84b"
  "module:subtitles|Subtitle handling|f5c84b"
  "module:library|Watch state and local library|f5c84b"
  "module:sync|Account sync (Trakt/etc)|f5c84b"
  "module:provider|Provider abstraction and source resolution|f5c84b"
  "module:settings|Settings, recovery, diagnostics|f5c84b"
  "module:macos|Native macOS experience|f5c84b"
  "module:engine|Engine layer (specs 01-05)|c9971f"
  "module:brand|Brand spec (06) work|f5c84b"

  # Special
  "needs-design|Open question requires design decision|d4c5f9"
  "blocked|Blocked on another issue or external dependency|e99695"
  "good-first-issue|Small, well-scoped, suitable for fresh contributor|7057ff"
  "breaking-change|Modifies a frozen spec or the XPC contract|b60205"
)

for entry in "${LABELS[@]}"; do
  IFS='|' read -r name desc color <<< "$entry"
  if gh label list --repo "$REPO" --limit 200 --json name -q '.[].name' | grep -Fxq "$name"; then
    echo "  label exists: $name"
  else
    gh label create "$name" --repo "$REPO" --description "$desc" --color "$color" >/dev/null
    echo "  created label: $name"
  fi
done

# -----------------------------------------------------------------------------
# Milestones
# -----------------------------------------------------------------------------

echo "==> Ensuring milestones exist..."

# Format: title|description
MILESTONES=(
  "v1|Initial public release. P0 + P1 only."
  "v1.1|First patch release. Defects, watched-seconds reporting, container-metadata bitrate path."
  "v1.5|First feature release. Sidecar subtitle fetching, advanced ranking, conflict resolution UI."
  "v2|Major release. Plugin providers, multi-account, deep links."
  "backlog|Unmilestoned. Triaged later."
)

# gh has no first-class milestone command yet; use the API
EXISTING_MILESTONES=$(gh api "repos/$REPO/milestones?state=all" --paginate -q '.[].title')

for entry in "${MILESTONES[@]}"; do
  IFS='|' read -r title desc <<< "$entry"
  if echo "$EXISTING_MILESTONES" | grep -Fxq "$title"; then
    echo "  milestone exists: $title"
  else
    gh api "repos/$REPO/milestones" -X POST \
      -f title="$title" \
      -f description="$desc" >/dev/null
    echo "  created milestone: $title"
  fi
done

# -----------------------------------------------------------------------------
# Epic issues
# -----------------------------------------------------------------------------

echo "==> Ensuring epic issues exist..."

# Format: title|priority|module|milestone|spec_ref|scope_summary
EPICS=(
  "Epic: Discovery and metadata|priority:p0|module:discovery|v1|.claude/specs/07-product-surface.md § 1|Browse and search films and TV cleanly. Home screen rows, global search, title detail pages, season/episode navigation, related titles."
  "Epic: Playback UX|priority:p0|module:playback|v1|.claude/specs/07-product-surface.md § 2|Native AVKit playback wrapped in calm UI. Resume, next-episode, scrub, fullscreen, error handling. Sits on top of the engine in specs 04-05."
  "Epic: Subtitles|priority:p0|module:subtitles|v1|.claude/specs/07-product-surface.md § 3|First-class subtitle support. Embedded tracks via AVKit, sidecar SRT via drag-and-drop, language preference persisted. Sidecar fetching deferred to v1.5+."
  "Epic: Watch state and local library|priority:p0|module:library|v1|.claude/specs/07-product-surface.md § 4|Track watched/unwatched status, resume position, continue-watching list, favourites, episode progress. Sits on top of playback_history in spec 05."
  "Epic: Account sync|priority:p1|module:sync|v1|.claude/specs/07-product-surface.md § 5|Trakt OAuth, sync watched history, progress, watchlist, ratings. Background sync. Re-auth on token expiry."
  "Epic: Provider abstraction and source resolution|priority:p1|module:provider|v1|.claude/specs/07-product-surface.md § 6|MediaProvider interface, per-provider auth, parallel source search, source ranking, provider enable/disable. Torrent providers in v1; non-torrent providers v1.5+."
  "Epic: Settings, recovery, diagnostics|priority:p1|module:settings|v1|.claude/specs/07-product-surface.md § 7|Settings page, account/provider management, cache clearing, secure logging, repair flow."
  "Epic: Native macOS experience|priority:p1|module:macos|v1|.claude/specs/07-product-surface.md § 8|Native menus, keyboard shortcuts, light/dark per brand palette, drag-and-drop subtitle loading."
)

for entry in "${EPICS[@]}"; do
  IFS='|' read -r title priority module milestone spec_ref summary <<< "$entry"

  if gh issue list --repo "$REPO" --state all --search "\"$title\" in:title" --json title -q '.[].title' | grep -Fxq "$title"; then
    echo "  epic exists: $title"
    continue
  fi

  body=$(cat <<EOF
## Scope

$summary

## Required features (v1)

See $spec_ref for the full module.

## Optional features (v1.5+)

See $spec_ref § Optional but valuable.

## Child issues

(populated as Feature issues are opened)

## Spec references

- $spec_ref
EOF
)

  gh issue create --repo "$REPO" \
    --title "$title" \
    --body "$body" \
    --label "type:epic,$priority,$module" \
    --milestone "$milestone" >/dev/null
  echo "  created epic: $title"
done

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------

echo
echo "Repo bootstrap complete."
echo "Next: run ./scripts/seed-issues.sh to create child Feature issues from spec 07 outstanding-work checkboxes."
