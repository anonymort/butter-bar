# Contributing to Butter Bar

This document is a quick-reference. The authoritative source is [`.claude/specs/08-issue-workflow.md`](./.claude/specs/08-issue-workflow.md).

## Before you start

1. Read [`CLAUDE.md`](./CLAUDE.md) for orientation.
2. Read [`.claude/specs/00-addendum.md`](./.claude/specs/00-addendum.md) for current revision decisions.
3. Read the spec(s) relevant to your work.
4. Read [`.claude/specs/08-issue-workflow.md`](./.claude/specs/08-issue-workflow.md) in full.

## Branch and PR rules

- The default branch is `main`. **Never commit directly to `main`.**
- One branch per issue. Naming pattern: `<type>/<scope>-<short-description>`. Engine tasks use `engine/T-<TASK-ID>`.
- One PR per branch. PR title uses Conventional Commits (`feat:`, `fix:`, `docs:`, etc.).
- PR body links the issue with `Closes #N` (or `Refs #N`).
- PR body references the spec section(s) it implements.
- CI must pass before merge.
- Branches are auto-deleted after merge.

## Spec changes

Frozen specs (01–09, each with a `Revision N` block) require:

1. A new addendum item appended to `00-addendum.md`.
2. A revision-block bump on the affected spec.
3. PR title prefixed `[spec]`.

Both edits happen in the same PR.

Spec 09 is particularly load-bearing — it governs the deployment target and the Liquid Glass adoption stance. Changes here ripple into Xcode build settings and `Info.plist` and should be reviewed with extra care.

## Issue creation

Use one of the templates in `.github/ISSUE_TEMPLATE/`. Apply labels per spec 08:
- One `type:` label.
- One `priority:` label.
- One `module:` label.
- Special labels (`needs-design`, `blocked`, `breaking-change`) as relevant.

Outstanding-work checkboxes in spec 07 each become one Feature issue. The `scripts/seed-issues.sh` helper can do this in bulk.

## Engine work

Engine tasks remain in `.claude/tasks/TASKS.md`. They become branches when picked up; they do not get GitHub issues. PRs that satisfy an engine task update `TASKS.md` to mark the task `DONE` or `REVIEW`.

## Code style

Per the agent role files in `.claude/agents/`. Modern Swift concurrency, no force-unwraps in production, tests alongside non-trivial code.

## Review

CODEOWNERS assigns reviewers by path. Spec changes and planner/XPC code require Opus review (an explicit invocation per `.claude/agents/opus-designer.md`). Other changes require one human reviewer.

## Voice

Documentation and UI strings follow the brand voice in `.claude/specs/06-brand.md`: direct, calm, concrete, British English.
