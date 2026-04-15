#!/usr/bin/env bash
#
# seed-issues.sh — create Feature/Spike/Task issues in bulk from
# docs/issue-conversion-mapping.md.
#
# Idempotent. Safe to re-run; uses issue titles to detect duplicates.
#
# Requires: gh CLI authenticated against anonymort/butter-bar, and python3.
#
# Usage:
#   ./scripts/seed-issues.sh                 # dry-run (default)
#   ./scripts/seed-issues.sh --create        # actually create issues
#
# Run setup-repo.sh first; this script assumes labels, milestones, and
# epics already exist.

set -euo pipefail

REPO="${REPO:-anonymort/butter-bar}"
MAPPING="docs/issue-conversion-mapping.md"
DRY_RUN=true

if [[ "${1:-}" == "--create" ]]; then
  DRY_RUN=false
fi

if ! command -v gh >/dev/null; then
  echo "error: gh CLI not found." >&2
  exit 1
fi

if ! command -v python3 >/dev/null; then
  echo "error: python3 not found." >&2
  exit 1
fi

if [[ ! -f "$MAPPING" ]]; then
  echo "error: $MAPPING not found. Run from repo root." >&2
  exit 1
fi

# Parse the mapping document with python and emit one TSV row per planned issue.
# Columns: type, title, priority, module, milestone, depends, source_section
PARSED=$(python3 <<'PY'
import re
import sys

with open("docs/issue-conversion-mapping.md") as f:
    lines = f.readlines()

current_module = None
current_section = None
emit = []

# Module header: "## Module N — Name"
mod_re = re.compile(r"^## Module (\d+) — (.+)$")
oq_re = re.compile(r"^## Open-question issues")

# Feature table rows look like:
#   | 1.1 | Checkbox text | `Title in backticks` | p0 | discovery | v1 | depends notes |
feature_row_re = re.compile(
    r"^\|\s*([\d.]+)\s*\|\s*(.+?)\s*\|\s*`([^`]+)`\s*\|\s*(p\d)\s*\|\s*(\w+)\s*\|\s*(v?[\d.]+|backlog)\s*\|\s*(.+?)\s*\|"
)

# Open-question rows:
#   | OQ.1 | Question | `Title` | spike | p0 |
oq_row_re = re.compile(
    r"^\|\s*(OQ\.\d+)\s*\|\s*(.+?)\s*\|\s*`([^`]+)`\s*\|\s*(\w+)\s*\|\s*(p\d)\s*\|"
)

in_oq = False

for line in lines:
    m = mod_re.match(line)
    if m:
        current_section = f"Module {m.group(1)} ({m.group(2)})"
        in_oq = False
        continue
    if oq_re.match(line):
        current_section = "Open questions"
        in_oq = True
        continue

    if not in_oq:
        m = feature_row_re.match(line)
        if m:
            num, checkbox, title, pri, mod, milestone, depends = m.groups()
            # Spike rows have "spike" in their title
            issue_type = "spike" if "spike" in title.lower().split(":")[1] else "feature"
            emit.append((issue_type, title, pri, mod, milestone, depends, current_section, num, checkbox))
    else:
        m = oq_row_re.match(line)
        if m:
            num, question, title, issue_type, pri = m.groups()
            # Open questions don't have explicit module; default to "settings" for tasks
            mod = "settings" if issue_type == "task" else "discovery"
            milestone = "v1"
            depends = "—"
            emit.append((issue_type, title, pri, mod, milestone, depends, current_section, num, question))

for row in emit:
    print("\t".join(row))
PY
)

TOTAL=$(echo "$PARSED" | wc -l | tr -d ' ')
echo "Parsed $TOTAL issues from $MAPPING"
echo

if $DRY_RUN; then
  echo "DRY RUN — no issues will be created. Pass --create to actually create."
  echo
fi

# Cache existing issue titles once
EXISTING=$(gh issue list --repo "$REPO" --state all --limit 500 --json title -q '.[].title' || true)

CREATED=0
SKIPPED=0

while IFS=$'\t' read -r issue_type title priority module milestone depends section num checkbox; do
  if echo "$EXISTING" | grep -Fxq "$title"; then
    if $DRY_RUN; then
      echo "[skip] exists: $title"
    fi
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  body=$(cat <<EOF
## Summary

$checkbox

## Spec context

From \`.claude/specs/07-product-surface.md\` — see $section.

## Acceptance criteria

(populate before picking this up)

## Dependencies

$depends

## Parent epic

(link the corresponding epic issue)

## Source

Item $num in \`docs/issue-conversion-mapping.md\`.
EOF
)

  if $DRY_RUN; then
    echo "[create] $title  [type:$issue_type, priority:$priority, module:$module, milestone:$milestone]"
  else
    gh issue create --repo "$REPO" \
      --title "$title" \
      --body "$body" \
      --label "type:$issue_type,priority:$priority,module:$module" \
      --milestone "$milestone" >/dev/null
    echo "  created: $title"
    CREATED=$((CREATED + 1))
  fi
done <<< "$PARSED"

echo
if $DRY_RUN; then
  echo "Dry run complete. $SKIPPED already exist, $((TOTAL - SKIPPED)) would be created."
  echo "Re-run with --create to create them."
else
  echo "Done. Created $CREATED issues, skipped $SKIPPED that already existed."
  echo "Next: link each child issue to its parent epic via the epic's 'Child issues' task list."
fi
