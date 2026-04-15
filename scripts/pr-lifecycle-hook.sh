#!/bin/bash
# PR lifecycle hook for Claude Code.
# Fires after `gh pr create` and `gh pr merge` commands.
#
# On create:
#   - Warns if PR body lacks issue reference (Closes #N / Refs #N).
#   - For engine/T-* branches, reminds to update TASKS.md.
#
# On merge:
#   - For engine/T-* branches, instructs agent to mark task DONE or REVIEW.
#
# Review-gated tasks (per CLAUDE.md review gates):
#   T-PLANNER-CORE, T-XPC-INTEGRATION, T-STREAM-E2E → mark REVIEW, not DONE.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Detect action
if echo "$COMMAND" | grep -q 'gh pr create'; then
    ACTION="create"
elif echo "$COMMAND" | grep -q 'gh pr merge'; then
    ACTION="merge"
else
    exit 0
fi

REVIEW_GATED="T-PLANNER-CORE T-XPC-INTEGRATION T-STREAM-E2E"

get_branch() {
    local branch
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [[ "$branch" == "main" || -z "$branch" ]]; then
        local pr_num
        pr_num=$(echo "$COMMAND" | grep -oE '[0-9]+' | head -1 || echo "")
        if [[ -n "$pr_num" ]]; then
            branch=$(gh pr view "$pr_num" --json headRefName -q .headRefName 2>/dev/null || echo "")
        fi
    fi
    echo "$branch"
}

extract_task_id() {
    local branch="$1"
    if [[ "$branch" =~ engine/(T-[A-Z0-9_-]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

target_status() {
    local task_id="$1"
    for gated in $REVIEW_GATED; do
        if [[ "$task_id" == "$gated" ]]; then
            echo "REVIEW"
            return
        fi
    done
    echo "DONE"
}

BRANCH=$(get_branch)
TASK_ID=$(extract_task_id "$BRANCH")

build_context() {
    local ctx=""

    if [[ "$ACTION" == "create" ]]; then
        if ! echo "$COMMAND" | grep -qiE '(closes|refs|fixes|resolves)\s+#[0-9]+'; then
            ctx="WARNING: PR created without issue reference. Per spec 08, every PR must link an issue via Closes #N or Refs #N in the body."
        fi
        if [[ -n "$TASK_ID" ]]; then
            ctx="${ctx:+$ctx }Engine task $TASK_ID: verify TASKS.md status has been updated from TODO."
        fi

    elif [[ "$ACTION" == "merge" ]]; then
        if [[ -n "$TASK_ID" ]]; then
            local status
            status=$(target_status "$TASK_ID")
            ctx="Engine PR merged for $TASK_ID. Update .claude/tasks/TASKS.md: mark this task $status."
            if [[ "$status" == "REVIEW" ]]; then
                ctx="$ctx This is a review-gated task — Opus must sign off before marking DONE."
            fi
        fi
    fi

    echo "$ctx"
}

CONTEXT=$(build_context)

if [[ -n "$CONTEXT" ]]; then
    CONTEXT_ESCAPED=$(echo "$CONTEXT" | jq -Rs '.')
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":$CONTEXT_ESCAPED}}"
fi
