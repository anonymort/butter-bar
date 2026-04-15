# 08 — Issue Workflow

> **Revision 1** — initial workflow spec. Defines how the product surface (spec 07) and the engine task list (TASKS.md) become GitHub issues, branches, and pull requests. This spec is the canonical source for repo conventions.

## Why two trackers

Butter Bar tracks work in two places, on purpose:

1. **`.claude/tasks/TASKS.md`** — the **engine build plan**. Phased, dependency-ordered, Opus/Sonnet routed, with review gates. Lives in the repo. Updated in PRs alongside the code that satisfies each task. This is how Phase 0–6 of the engine is built.

2. **GitHub Issues** — the **product surface tracker**. One issue per feature-area outstanding-work item from spec 07. Grouped into Epics (one per module). Milestoned to v1 / v1.1 / v1.5+. This is how the product surface above the engine is built.

The two trackers connect at well-defined points:

- The engine build plan completes Phase 0–5 *before* most product-surface issues become actionable. Phase 6 of the engine plan (UI tasks) is the seam where the two trackers begin to interleave.
- A product-surface issue may reference an engine task as a blocker (e.g. "blocked by T-STREAM-E2E").
- An engine task may reference a product-surface issue (e.g. "T-UI-PLAYER acceptance: closes #42").

If you find yourself wanting to add a third tracker, stop. Two is the right number.

## Issue types

Five issue templates live under `.github/ISSUE_TEMPLATE/`:

1. **Epic** — one per module from spec 07 (eight epics for v1). Tracks high-level scope, links child feature issues, holds the milestone.
2. **Feature** — one per outstanding-work checkbox in spec 07. Has acceptance criteria, links to its parent epic, may have engine-task blockers.
3. **Bug** — defects against shipped or in-flight code.
4. **Spike** — time-boxed investigations (e.g. "evaluate Trakt OAuth flow for ASWebAuthenticationSession compatibility").
5. **Task** — operational/non-feature work (CI setup, dependency upgrades, doc edits).

## Labels

Labels are categorical, not workflow. Workflow lives in issue state (open/closed) and project boards.

### Type labels (one per issue)
- `type:epic`
- `type:feature`
- `type:bug`
- `type:spike`
- `type:task`

### Priority labels (one per issue)
- `priority:p0` — blocking v1 release
- `priority:p1` — required for credible v1
- `priority:p2` — post-v1
- `priority:p3` — nice-to-have / unscheduled

### Module labels (one per issue, mirrors spec 07 modules)
- `module:discovery`
- `module:playback`
- `module:subtitles`
- `module:library`
- `module:sync`
- `module:provider`
- `module:settings`
- `module:macos`
- `module:engine` — for issues that touch the engine layer (specs 01–05)
- `module:brand` — for issues touching the brand spec (06)

### Special labels
- `needs-design` — open question requires design decision before implementation
- `blocked` — blocked on another issue or external dependency
- `good-first-issue` — small, well-scoped, suitable for a fresh contributor or fresh agent context
- `breaking-change` — modifies a frozen spec or the XPC contract

## Milestones

- **v1** — initial public release. P0 + P1 issues only.
- **v1.1** — first patch release. Defects, watched-seconds reporting, container-metadata bitrate path.
- **v1.5** — first feature release. Sidecar subtitle fetching, advanced ranking, conflict resolution UI.
- **v2** — major release. Plugin providers, multi-account, deep links.
- **backlog** — unmilestoned. Triaged later.

## Branch conventions

The default branch is `main`. **No direct commits to `main`** — every change arrives via a pull request from a topic branch.

### Naming

Branch names follow the pattern `<type>/<scope>-<short-description>`:

- `feat/discovery-home-rows`
- `feat/sync-trakt-oauth`
- `fix/player-resume-off-by-one`
- `spike/metadata-source-evaluation`
- `task/ci-add-swift-build`
- `docs/update-spec-04-readahead-policy`
- `chore/bump-grdb`
- `engine/T-PLANNER-CORE` — engine tasks use the `engine/` prefix and the task ID

### Lifetime

- One branch per issue. The issue number goes in the PR description, not the branch name (PRs link issues via `Closes #N`).
- Long-lived feature branches are forbidden. If a feature is too big for a single branch, it should be sub-divided into smaller issues.
- After merge, the branch is deleted (auto-delete via repo setting).

### Worktrees

For parallel work — common when an Opus design pass and a Sonnet implementation pass run in parallel — use `git worktree add` rather than juggling branches in one checkout:

```bash
git worktree add ../butter-bar-T-PLANNER-CORE engine/T-PLANNER-CORE
git worktree add ../butter-bar-spike-metadata spike/metadata-source-evaluation
```

This keeps Claude Code sub-agent invocations isolated to their own filesystem so they can't accidentally see or modify another branch's state.

## Pull request conventions

Every PR must:

1. Link an issue via `Closes #N` (or `Refs #N` if it doesn't fully close it).
2. Reference the spec section(s) it implements.
3. Pass CI (build + tests).
4. Be reviewed by at least one human or by Opus (for review-gated engine tasks).
5. Update `TASKS.md` if it satisfies an engine task.
6. Update `00-addendum.md` if it surfaces a spec ambiguity that needs recording.

PRs that touch frozen specs (01–07 in their `Revision N` body) require an addendum item *and* a Revision-block bump on the affected spec, both in the same PR. The PR title must be prefixed `[spec]` so reviewers know to scrutinise it.

PR titles use Conventional Commits prefixes: `feat:`, `fix:`, `docs:`, `chore:`, `test:`, `refactor:`, `spike:`, `engine:`. The body explains *why*, not *what*.

## Conversion: outstanding-work checkbox → GitHub issue

Each `- [ ]` checkbox in spec 07 maps to one Feature issue. The conversion rule:

- **Title:** the checkbox text, lightly cleaned up. Example: "Define metadata schema for movie, show, season, episode" → `Discovery: define metadata schema (movie/show/season/episode)`.
- **Body:** quote the surrounding context from spec 07; state the acceptance criteria; list dependencies (engine tasks or other issues).
- **Labels:** `type:feature`, the module label, the priority label.
- **Milestone:** v1 for P0/P1 items; v1.5 for items marked "(v1.5+)" in the spec.
- **Linked epic:** added as a comment on the parent epic, or linked via the project board.

A helper script — `scripts/seed-issues.sh` — produces the eight epic issues and seeds child issues from spec 07. It uses the GitHub CLI (`gh`) and is idempotent (safe to re-run; uses issue titles to detect duplicates).

## Conversion: engine task → branch

Engine tasks in `TASKS.md` are not converted to issues — they remain in `TASKS.md`. They become branches when work starts:

- Branch: `engine/T-PLANNER-CORE` (or whichever task ID).
- PR: title `engine: T-PLANNER-CORE — implement deterministic state machine`.
- PR body: references the spec sections, lists the acceptance criteria from the task, notes any follow-ups.
- On merge, `TASKS.md` is updated to mark the task `DONE` or `REVIEW` per the agent role conventions.

Engine tasks may *generate* issues (when a follow-up surfaces during implementation). Those issues use `type:feature` or `type:bug` and reference the engine task that produced them.

## CODEOWNERS and review

A `CODEOWNERS` file at the repo root assigns reviewers by path:

- `.claude/specs/**` — Opus reviewer (i.e. requires explicit Opus review before merge).
- `EngineService/Planner/**` — Opus reviewer (the planner is review-gated per `01-architecture.md`).
- `EngineService/XPC/**` — Opus reviewer (per the XPC review gate).
- Everything else — default reviewer (the project owner).

CODEOWNERS does not block merges automatically; it just adds reviewers. The "Opus reviewer" label is conceptual — in practice this means an explicit invocation per `.claude/agents/opus-designer.md`.

## CI

A minimal GitHub Actions workflow lives at `.github/workflows/ci.yml`:

- On every PR: `swift build && swift test` for the Swift packages (planner, engine interface, fixtures). The full Xcode project build is not run in CI for v1 (requires macOS runners and meaningful runtime); it runs locally and at release-tag time.
- On merge to `main`: same as PR plus a tag check that no PR sneaked in without a linked issue.

## What this spec deliberately does not cover

- The actual content of issues — that's spec 07.
- The engine build sequence — that's `TASKS.md`.
- Brand voice for issue text — that's spec 06 (use the same calm/direct tone as the product UI).
- Release notes / changelog format — defer to v1 release prep.

## Test obligations

This is a process spec, not a code spec. The test is: a fresh contributor (or fresh agent context) can read this file, run `scripts/seed-issues.sh`, and end up with a populated, well-labelled GitHub project board without further guidance.
