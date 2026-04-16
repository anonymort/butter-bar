# Phase 0–6 Issue Loop — Design

**Date:** 2026-04-16
**Author:** Claude Opus (via superpowers:brainstorming)
**Status:** DRAFT — pending user review

## Purpose

Drive the 16 open engine-scope GitHub issues that relate to phases 0–6 to completion through a structured, semi-autonomous pipeline. Each issue is implemented on a fresh branch, reviewed by an Opus-model subagent, and auto-merged on `APPROVE` or `APPROVE-WITH-FOLLOW-UPS`. The loop pauses between waves and halts mid-wave on `CHANGES-REQUESTED` (after 2 implementer iterations) or `BLOCKED`.

This design is not a new system — it is a workflow/orchestration plan for a bounded set of existing tickets. Its lifetime ends when the 16 issues close (or when a non-clean verdict halts the loop and requires user input).

## Scope

### In scope (16 issues)

**Engine follow-ups with explicit T-\* refs in P0–P6 (12):**
- #18, #90, #92, #107, #110, #111, #113, #114, #115, #116, #117, #118

**Engine-labelled issues without explicit T-\* refs (4):**
- #86, #87, #88 — spec 04 addendum bumps (A20/A21/A22)
- #89 — TorrentBridge alert field addition

### Out of scope

- **Product-surface features** #33, #34, #36 (Library watched-state, favourites, extended playback_history). These reference T-STORE-SCHEMA as a blocker but are feature work per spec 07 and require product design, not a mechanical engine-loop treatment.
- **Phase 7 hardening** (#103 style tasks, T-DOC-ARCHITECTURE). Separate loop after this one completes.
- Any `priority:p0` issue that appears mid-loop — halt and ask.

## Ordering

Dependency-aware, small wins first. Six waves:

| Wave | Issues | Rationale |
|---|---|---|
| 1 | #118 | Fixes test action; needed to verify snapshot tests for later waves |
| 2 | #86, #87, #88 | Spec 04 addendum bumps; Opus-owned, zero code impact, clears noise |
| 3 | #111, #113, #114, #115, #116 | UI nits from T-UI-PLAYER/LIBRARY review follow-ups |
| 4 | #89 → #90 | Hard dep: #89 adds pieceIndex; #90 consumes it in AlertDispatcher |
| 5 | #110, #117, #92 | Cross-boundary work (HUD reconnect, XPC typed enum, status snapshot) |
| 6 | #107, #18 | Design-heavy: new SLA threshold; player state model |

Within a wave, sequential. Between waves, pause for user review of summary.

## Per-issue pipeline

Seven-step state machine. Halt = stop the loop, present state to user.

1. **PRE-FLIGHT**
   - `gh issue view <N>` confirms issue still open and no new user comments
   - `git status` confirms clean tree on `main`
   - `git fetch origin && git status` confirms up to date with origin
   - `clash status --json` confirms no conflicting worktrees (per global CLAUDE.md)
   - Halt on any failure.

2. **BRANCH** — per spec 08 naming:
   - `fix/<scope>-<short>` for code fixes
   - `docs/<scope>-<short>` for spec edits
   - `refactor/<scope>-<short>` for non-behavioural refactors
   - No `engine/T-*` prefix (these are follow-ups, not T-\* tasks).

3. **DISPATCH IMPLEMENTER** — subagent with model per routing table (below). Brief includes: issue body verbatim, relevant specs, "forbid spec modification except where explicitly authorised", "write tests on any non-trivial change", "verify before claiming done". Agent returns terminal state: `READY-FOR-PR | BLOCKED | VERIFY-FAILED`.

4. **LOCAL VERIFY** — `swift build && swift test` for touched packages; `xcodebuild` for touched Xcode targets. On failure, re-dispatch implementer up to 2× with the failure output attached. After 2 failures, halt.

5. **PR** — Conventional Commits title. Body: `Closes #<N>`, spec refs, acceptance criteria verbatim, `Co-Authored-By` trailer. PR lifecycle hook (`scripts/pr-lifecycle-hook.sh`) fires automatically.

6. **OPUS REVIEW** — Opus-model subagent reads diff + issue + specs. Returns structured verdict:
   - `APPROVE` | `APPROVE-WITH-FOLLOW-UPS` | `CHANGES-REQUESTED` | `BLOCKED`
   - Plus numbered findings (severity: blocker/nit/follow-up) and draft follow-up issue bodies.

7. **ACT ON VERDICT**
   - `APPROVE` → `gh pr merge --squash --delete-branch`. GitHub auto-closes issue via `Closes #N`. Proceed to next issue.
   - `APPROVE-WITH-FOLLOW-UPS` → merge as above, then `gh issue create` for each follow-up with labels from the reviewer's draft. Proceed to next.
   - `CHANGES-REQUESTED` → re-dispatch implementer with Opus findings. Max 2 iterations, then halt.
   - `BLOCKED` → halt immediately.

## Agent routing

| Role | Model | Type |
|---|---|---|
| Orchestrator | Opus (this session) | — |
| Implementer (trivial spec-doc edits) | Haiku | general-purpose |
| Implementer (typical code) | Sonnet | general-purpose |
| Implementer (design-heavy) | Opus | general-purpose, briefed as [opus] per `.claude/agents/opus-designer.md` |
| Reviewer (all issues) | Opus | general-purpose, briefed per `.claude/agents/opus-designer.md` |

### Per-issue implementer model

| Issues | Model | Reason |
|---|---|---|
| #86, #87, #88 | Haiku | Addendum bumps + single spec file edit; small, mechanical |
| #89, #90 | Sonnet | ObjC++/Swift boundary in TorrentBridge + AlertDispatcher |
| #92, #110, #111, #113, #114, #115, #116, #117, #118 | Sonnet | Typical Swift work, 1–3 files each |
| #107 | Opus | Establishing a new numerical SLA + regression threshold; design call |
| #18 | Opus | Defining a new player state model; design call |

### Tooling contracts

- Implementer agents: `Read`, `Write`, `Edit`, `Grep`, `Glob`, `Bash` (for `gh`, `xcodebuild`, `swift`, `git`). **No** `Agent` (no recursive subagents). **No** `gh pr merge`, **no** issue closure, **no** `git push --force`.
- Reviewer agents: `Read`, `Grep`, `Glob`, `Bash` (read-only `gh`/`git`). No edits. No merges.
- Orchestrator: drives `gh pr merge`, branch deletion, follow-up issue creation, TASKS.md updates, session-resume memory updates.

## Docs & status updates

Per the user's directive "update docs and issue status as you go":

| Artefact | Trigger | Owner |
|---|---|---|
| GitHub issue state | PR merge | Automatic via `Closes #N` |
| `TASKS.md` status for T-\* tasks | PR merge on `engine/T-*` branch | `scripts/pr-lifecycle-hook.sh` (existing) |
| `TASKS.md` follow-up note strike-throughs | PR merge on non-`engine/` branch | Orchestrator — after each merge, if the source issue is listed in a T-\* task's follow-ups, mark it resolved |
| Spec addendum edits | Part of #86/#87/#88 PR diffs | Implementer agent (authorised for those issues only) |
| Session-resume memory | End of each wave | Orchestrator — updates `project_session_resume.md` with wave, last merged PR, next wave's issue list |
| Wave summary message | End of each wave | Orchestrator — presents merged issues, filed follow-ups, deleted branches, any halts |

## Pause policy (wave boundaries)

Within a wave, the loop auto-proceeds on `APPROVE` or `APPROVE-WITH-FOLLOW-UPS`. At the end of each wave, the orchestrator pauses and presents a summary. User can then say "continue" or adjust scope.

Pauses also happen mid-wave on any halt condition (below), without waiting for wave end.

## Stop conditions

| Condition | Action |
|---|---|
| All 6 waves complete | Final summary; loop ends |
| Opus `BLOCKED` | Halt; present issue + rationale + suggested next step |
| Opus `CHANGES-REQUESTED` after 2 implementer iterations | Halt; present findings + both attempts |
| Pre-flight failure | Halt; surface the failed check |
| CI failure on PR | Halt; await user triage |
| Merge conflict on `main` | Halt (should be rare; sequential flow) |
| New `priority:p0` issue appears during loop | Halt; ask user whether to preempt |
| User interrupt | Graceful exit; current PR left open |

## What this design explicitly does NOT do

- Invoke the `/loop` skill (interval-based execution is wrong model for order-dependent, Opus-gated work).
- Run PRs in parallel within a wave (sequential only — keeps diff review tractable).
- Use git worktrees (overhead not worth it for single-branch sequential flow).
- Auto-escalate on P0 issues (user call).
- Retry CI failures without surfacing them first.
- Touch the 3 product-surface issues (#33, #34, #36) — those need spec 07 work.

## Success criteria

- All 16 in-scope issues closed on GitHub.
- `TASKS.md` is updated for any impacted T-\* task follow-up notes.
- All follow-ups from `APPROVE-WITH-FOLLOW-UPS` verdicts filed as new issues with correct labels.
- `main` remains clean at every wave boundary (no orphan branches, no stale PRs).
- `project_session_resume.md` reflects the final state.

## Open questions / risks

- **Opus-as-subagent cost and latency.** Each wave ends with ~1–5 Opus reviews. Cost is fine for the batch size but worth keeping an eye on if we extend the loop.
- **Spec-touching PRs** for #86/#87/#88 will trigger the `[spec]` prefix convention in spec 08. The implementer brief must enforce: `[spec]` title prefix + addendum item + revision block bump, all in one PR.
- **#107 and #18 being Opus-implemented** is a departure from the usual Sonnet-implementer pattern. If Opus produces overly opinionated output, reviewer will catch it — but worth acknowledging the model/reviewer coupling weakens when both are Opus.
- **PR lifecycle hook expectations.** The hook enforces TASKS.md updates on `engine/T-*` branches only. Non-`engine/` branches rely on `Closes #N` for issue closure; TASKS.md follow-up note updates are orchestrator-owned.

## Terminal state

Loop ends successfully when:
1. All 6 waves have completed without a non-resolved halt, and
2. `gh issue list --state open --label module:engine` returns only issues NOT in the original 16 (i.e., any that appeared mid-loop as follow-ups or that were out of scope from the start).

On success, the orchestrator writes a final summary to `project_session_resume.md` and awaits the next user instruction.
