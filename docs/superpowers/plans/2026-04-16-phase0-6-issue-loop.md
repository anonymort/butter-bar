# Phase 0–6 Issue Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drive 16 open engine-scope GitHub issues in phases 0–6 to merged+closed through a 6-wave, Opus-reviewed, semi-autonomous pipeline.

**Architecture:** Sequential issue-by-issue within each wave; pause between waves. Each issue = pre-flight → branch → implementer subagent (Haiku/Sonnet/Opus per routing) → local verify → PR → Opus reviewer subagent → auto-merge on APPROVE(-WITH-FOLLOW-UPS), halt on CHANGES-REQUESTED (after 2 implementer iterations) or BLOCKED. All state updates (TASKS.md strike-throughs, session memory, follow-up issues) are orchestrator-owned.

**Tech Stack:** git + GitHub CLI (`gh`); Xcode 26 / SDK 26 (`xcodebuild`); Swift Package Manager (`swift build`, `swift test`); Agent tool for subagent dispatch.

**Spec:** `docs/superpowers/specs/2026-04-16-phase0-6-issue-loop-design.md`.

---

## File structure — what this plan touches

No new product. State updates across the following systems:

- `.claude/tasks/TASKS.md` — orchestrator strikes through follow-up notes when source issues merge
- `.claude/specs/00-addendum.md`, `.claude/specs/02-stream-health.md`, `.claude/specs/04-piece-planner.md` — edited by implementer agents authorised for #86/#87/#88 only (revision blocks bumped per spec 08 § Pull request conventions)
- `/Users/mattkneale/.claude/projects/-Users-mattkneale-Documents-Coding-ButterBar-main/memory/project_session_resume.md` — updated at each wave boundary
- GitHub issues — opened (follow-ups) and closed (via PR `Closes #N`)
- Per-issue source files — listed in each task

---

## Per-issue execution playbook (shared by all 16 issue tasks)

Each "Issue #N" task below follows these 7 sub-steps. Per-task overrides under Files/Model/Branch/Verify.

### Sub-step A: Pre-flight (halt on any failure)

```bash
gh issue view <N> --json state,comments | jq '{state, commentCount: (.comments | length)}'
# Expected: state="OPEN"; commentCount unchanged since loop started
git status
# Expected: clean, on branch main
git fetch origin && git rev-parse HEAD origin/main
# Expected: both refs equal
clash status --json 2>/dev/null || true
# Expected: no conflicting worktrees, or clash not installed (ok)
```

### Sub-step B: Create branch

```bash
git checkout main
git checkout -b <BRANCH>
```

### Sub-step C: Dispatch implementer subagent

Use `Agent` tool. `model=<MODEL>`, `subagent_type="general-purpose"`. Brief template (fill in ALL-CAPS placeholders from the task):

```
ISSUE: #<N> — <TITLE>
BRANCH: <BRANCH> (already created; you are on it)

ACCEPTANCE CRITERIA: Read fresh from `gh issue view <N>` before coding.

RELEVANT SPECS (read in this order):
  1. .claude/specs/00-addendum.md
  <SPEC-REFS>

TOUCHED FILES (expected): <FILES>

ORCHESTRATION RULES (per CLAUDE.md, non-negotiable):
  - You are the implementer. Do NOT modify spec files in `.claude/specs/`
    UNLESS this issue explicitly says "update spec X" or "revision block bump".
    (For #86/#87/#88 ONLY, spec edits are the task itself.)
  - If a spec appears wrong or ambiguous, STOP and return
    "BLOCKED: <ambiguity>". Do NOT silently reinterpret.
  - Write tests for any non-trivial code change.
  - Verify before claiming done: run `<VERIFY-COMMANDS>` and paste
    the output (or a truthful summary) into your final message.
  - Use Conventional Commits for commit messages.
  - If this task edits any frozen spec (01–07), the PR title MUST begin
    with `[spec]` and the PR body MUST include an addendum bump note
    (per spec 08 § Pull request conventions).

DELIVERABLES:
  1. One or more commits on <BRANCH>.
  2. A PR body draft (you will not create the PR; orchestrator will):
     ```
     Closes #<N>

     ## Summary
     <1–3 sentences>

     ## Spec refs
     - <refs>

     ## Acceptance
     <criteria met, evidence>

     🤖 Generated with [Claude Code](https://claude.com/claude-code)
     Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
     ```
  3. Return exactly one terminal state as the first line of your final
     message:
     - `READY-FOR-PR` (then the PR body draft)
     - `BLOCKED: <reason>`
     - `VERIFY-FAILED: <tool output excerpt>`

TOOLS: Read, Write, Edit, Grep, Glob, Bash. Do NOT use the Agent tool
(no recursive subagents). Do NOT run `gh pr create`, `gh pr merge`,
`git push --force`, or `gh issue close`.
```

### Sub-step D: Orchestrator local verify (belt-and-braces)

Re-run the `<VERIFY-COMMANDS>` from the task. If they fail here (but passed inside the agent), halt — something about the agent's environment didn't match yours. Don't auto-retry at this layer.

### Sub-step E: Push + create PR

```bash
git push -u origin <BRANCH>
gh pr create --title "<CONV-COMMIT-TITLE>" --body "$(cat <<'EOF'
<PR BODY from agent's READY-FOR-PR response>
EOF
)"
```

Capture the PR URL from `gh pr create` stdout. The PR lifecycle hook (`scripts/pr-lifecycle-hook.sh`) will fire on `gh pr create` and add guidance — follow it.

### Sub-step F: Dispatch Opus reviewer subagent

Use `Agent` tool. `model="opus"`, `subagent_type="general-purpose"`. Brief:

```
PR: <url from sub-step E>
ISSUE: #<N>
BRANCH: <BRANCH>

ROLE: Opus design reviewer per `.claude/agents/opus-designer.md`.

READ FIRST (in this order):
  1. `gh pr diff <url>` — the full diff
  2. `gh issue view <N>` — the source issue
  3. .claude/specs/00-addendum.md
  4. Each spec file referenced in the PR body
  5. .claude/tasks/TASKS.md if the PR touches any engine T-* area
  6. .claude/agents/opus-designer.md

VERIFY:
  - Every acceptance criterion in the issue is satisfied by the diff.
  - No frozen-spec violations (precedence: addendum > 01-09 > TASKS.md).
  - Tests exist and cover the change (where applicable).
  - No drive-by refactoring, no speculative abstraction (per CLAUDE.md).
  - Brand compliance for UI work (spec 06).
  - XPC contract compliance for boundary work (spec 03).
  - If the PR edits a frozen spec, it has `[spec]` prefix + addendum bump.

OUTPUT (structured, a single message with exactly these sections):
  VERDICT: APPROVE | APPROVE-WITH-FOLLOW-UPS | CHANGES-REQUESTED | BLOCKED
  FINDINGS:
    F1 [blocker|nit|follow-up] <finding>
    F2 ...
  FOLLOW-UPS (only if APPROVE-WITH-FOLLOW-UPS or if finding tagged follow-up):
    For each, a ready-to-run `gh issue create` command with --title, --body,
    and --label (using existing labels from `.claude/specs/08-issue-workflow.md`
    § Labels). Example:
      gh issue create \
        --title "Player: …" \
        --label "type:bug,priority:p2,module:playback" \
        --body "$(cat <<'EOF'
        …
        EOF
        )"
  RATIONALE: ≤150 words on why this verdict.

TOOLS: Read, Grep, Glob, Bash (read-only `gh`/`git`). No edits.
No merges. Do NOT run `gh pr merge` or `gh pr review`.
```

### Sub-step G: Act on verdict

- **APPROVE** or **APPROVE-WITH-FOLLOW-UPS**:
  ```bash
  gh pr merge <url> --squash --delete-branch
  git checkout main && git pull origin main
  # For APPROVE-WITH-FOLLOW-UPS only: run every `gh issue create` command from
  # the reviewer output verbatim. Capture the new issue numbers.
  ```
  Then: for any TASKS.md follow-up note that matches the source issue, strike through that bullet using the Edit tool on `.claude/tasks/TASKS.md`. Example transform:
  ```markdown
  - Follow-up: HUD reconnect re-subscribe (GitHub #110)
  ```
  becomes
  ```markdown
  - ~~Follow-up: HUD reconnect re-subscribe (GitHub #110)~~ — resolved by PR #<new>
  ```
  Proceed to next task.
- **CHANGES-REQUESTED**:
  Re-dispatch implementer via sub-step C with the original brief PLUS a new section at the end:
  ```
  PRIOR REVIEW FOUND THE FOLLOWING ISSUES. ADDRESS EACH:
  <paste FINDINGS from reviewer>
  ```
  Re-run sub-steps D→F. Max 2 implementer iterations total (first attempt + 1 retry). If the second review is still non-APPROVE, halt to user with all three outputs attached (first implementer, first reviewer, second implementer).
- **BLOCKED**:
  Halt to user immediately. Include the reviewer's RATIONALE + FINDINGS.

---

## Wave 1 — Test infrastructure (1 issue)

### Task 1: Issue #118 — ButterBar scheme has no test action

**Files:**
- Modify: `ButterBar.xcodeproj/xcshareddata/xcschemes/ButterBar.xcscheme` — add `ButterBarTests` target to Test action, OR create a separate `ButterBarTests.xcscheme`
- Maybe touch: `scripts/` (add one-liner for local snapshot runs, per issue acceptance)

**Model:** Sonnet
**Branch:** `fix/project-test-scheme`
**Spec refs:** None (build-tooling). Read issue body for the exact acceptance list.
**Verify commands:**
```bash
xcodebuild -list | grep -E "ButterBar|ButterBarTests"
# Expected: test scheme present
xcodebuild test -scheme ButterBar -only-testing:ButterBarTests/LibrarySnapshotTests -destination 'platform=macOS' 2>&1 | tail -30
# Expected: "Test Suite 'LibrarySnapshotTests' passed" or similar
xcodebuild test -scheme ButterBar -only-testing:ButterBarTests/PlayerHUDSnapshotTests -destination 'platform=macOS' 2>&1 | tail -30
# Expected: "Test Suite 'PlayerHUDSnapshotTests' passed"
```

- [ ] **Step 1: Apply playbook sub-step A (pre-flight) for issue 118.** Halt on any failure.
- [ ] **Step 2: Apply sub-step B — `git checkout main && git checkout -b fix/project-test-scheme`.**
- [ ] **Step 3: Apply sub-step C — dispatch Sonnet implementer with the brief above (fill N=118, TITLE from issue, BRANCH=`fix/project-test-scheme`, SPEC-REFS=none, FILES=.xcscheme + maybe scripts/, VERIFY-COMMANDS=the three xcodebuild commands). Await `READY-FOR-PR` / `BLOCKED` / `VERIFY-FAILED`.**
- [ ] **Step 4: Apply sub-step D — re-run the three verify commands locally. Halt on failure.**
- [ ] **Step 5: Apply sub-step E — push and `gh pr create --title "fix: wire ButterBarTests into Test action"` with the agent's PR body.**
- [ ] **Step 6: Apply sub-step F — dispatch Opus reviewer with the PR URL.**
- [ ] **Step 7: Apply sub-step G — act on verdict. On merge, `#118` is closed by `Closes #N`; no TASKS.md strike-through (issue is not referenced in a follow-up note).**

### Task 2: Wave 1 closing checkpoint

- [ ] **Step 1: Summarise Wave 1 to user.** Post a message with: issues merged (#118), follow-ups filed (list with labels), branch deletion confirmation, any halts encountered, next wave preview.
- [ ] **Step 2: Update session-resume memory.** Edit `/Users/mattkneale/.claude/projects/-Users-mattkneale-Documents-Coding-ButterBar-main/memory/project_session_resume.md`. Replace the current body (preserving frontmatter) with a new single-line body describing state:
      ```
      Issue loop Wave 1 complete: #118 merged. Wave 2 next (#86, #87, #88 — spec 04/02 addenda). Loop design: docs/superpowers/specs/2026-04-16-phase0-6-issue-loop-design.md; plan: docs/superpowers/plans/2026-04-16-phase0-6-issue-loop.md.
      ```
- [ ] **Step 3: Wait for user "continue" before Wave 2.** The user may ask to adjust scope or skip a wave.

---

## Wave 2 — Spec addenda (3 issues, Opus-owned spec edits)

All three are spec edits with `[spec]` prefix on PR titles. Per spec 08 § Pull request conventions: addendum item + Revision-block bump in the same PR. Model is Haiku (mechanical edits).

### Task 3: Issue #86 — spec 04 A20 served-byte

**Files:**
- Modify: `.claude/specs/04-piece-planner.md` — update § Seek wording to reflect "most recently served byte = range.end of every GET event, not delivered bytes"
- Modify: `.claude/specs/04-piece-planner.md` — Revision block bump (add a new Revision N+1 entry referencing A20)
- Check: `.claude/specs/00-addendum.md` already contains A20 (if not, this task grows)

**Model:** Haiku
**Branch:** `docs/spec-04-a20-served-byte`
**Spec refs:** `.claude/specs/00-addendum.md` (A20 definition), `.claude/specs/04-piece-planner.md` (target edit).
**Verify commands:**
```bash
# No build impact. Just verify the spec file is well-formed markdown.
grep -n "A20" .claude/specs/04-piece-planner.md
# Expected: A20 referenced in the new Revision block line
grep -nE "^## Revision [0-9]+" .claude/specs/04-piece-planner.md | tail -3
# Expected: newly-incremented Revision number appears
```

- [ ] **Step 1: Apply playbook sub-step A for issue 86.**
- [ ] **Step 2: Sub-step B — `git checkout main && git checkout -b docs/spec-04-a20-served-byte`.**
- [ ] **Step 3: Sub-step C — dispatch Haiku implementer. In the ORCHESTRATION RULES section of the brief, replace the "Do NOT modify spec files" line with: "This task EDITS `.claude/specs/04-piece-planner.md`. Scope is limited to: (a) updating the § Seek wording per A20, (b) bumping the Revision block. Do not modify any other spec file."**
- [ ] **Step 4: Sub-step D — re-run the two grep commands. Halt on empty output.**
- [ ] **Step 5: Sub-step E — `gh pr create --title "[spec] docs: spec 04 § Seek — served-byte clarification (A20)"` with the agent's PR body. PR body MUST include the addendum reference and note the Revision bump.**
- [ ] **Step 6: Sub-step F — Opus review.**
- [ ] **Step 7: Sub-step G — act on verdict. Close #86.**

### Task 4: Issue #87 — spec 04 A21 pieceLength gap

**Files:**
- Modify: `.claude/specs/04-piece-planner.md` — update § Mid-play GET or § Seek noting that `pieceLength*2..pieceLength*4` gap is treated as mid-play
- Modify: `.claude/specs/04-piece-planner.md` — Revision block bump referencing A21

**Model:** Haiku
**Branch:** `docs/spec-04-a21-piecelength-gap`
**Spec refs:** `.claude/specs/00-addendum.md` (A21), `.claude/specs/04-piece-planner.md` (target).
**Verify commands:**
```bash
grep -n "A21" .claude/specs/04-piece-planner.md
grep -nE "pieceLength\s*\*\s*[24]" .claude/specs/04-piece-planner.md | head -5
```

- [ ] **Step 1: Apply playbook sub-step A for issue 87.**
- [ ] **Step 2: Sub-step B — `git checkout main && git checkout -b docs/spec-04-a21-piecelength-gap`.**
- [ ] **Step 3: Sub-step C — dispatch Haiku implementer with spec-edit authorisation scoped to `04-piece-planner.md` § Mid-play/Seek and the Revision block.**
- [ ] **Step 4: Sub-step D — re-run the grep commands.**
- [ ] **Step 5: Sub-step E — `gh pr create --title "[spec] docs: spec 04 — pieceLength gap is mid-play (A21)"`.**
- [ ] **Step 6: Sub-step F — Opus review.**
- [ ] **Step 7: Sub-step G — act on verdict.**

### Task 5: Issue #88 — spec 02 A22 secondsBufferedAhead=0

**Files:**
- Modify: `.claude/specs/02-stream-health.md` — § Tier semantics updated: when `requiredBitrateBytesPerSec` is nil, `secondsBufferedAhead = 0.0`; buffer-path healthy/marginal unreachable until 60 s of playback
- Modify: `.claude/specs/02-stream-health.md` — Revision block bump referencing A22

**Model:** Haiku
**Branch:** `docs/spec-02-a22-seconds-buffered`
**Spec refs:** `.claude/specs/00-addendum.md` (A22), `.claude/specs/02-stream-health.md` (target).
**Verify commands:**
```bash
grep -n "A22" .claude/specs/02-stream-health.md
grep -nE "secondsBufferedAhead|requiredBitrate" .claude/specs/02-stream-health.md | head -10
```

- [ ] **Step 1: Apply playbook sub-step A for issue 88.**
- [ ] **Step 2: Sub-step B — `git checkout main && git checkout -b docs/spec-02-a22-seconds-buffered`.**
- [ ] **Step 3: Sub-step C — dispatch Haiku implementer with spec-edit authorisation scoped to `02-stream-health.md` § Tier semantics and the Revision block.**
- [ ] **Step 4: Sub-step D — re-run the grep commands.**
- [ ] **Step 5: Sub-step E — `gh pr create --title "[spec] docs: spec 02 — secondsBufferedAhead=0 when bitrate unknown (A22)"`.**
- [ ] **Step 6: Sub-step F — Opus review.**
- [ ] **Step 7: Sub-step G — act on verdict.**

### Task 6: Wave 2 closing checkpoint

- [ ] **Step 1: Summarise Wave 2 to user (#86/#87/#88 merged, any follow-ups, branches deleted).**
- [ ] **Step 2: Update session-resume memory — body replaced with "Issue loop Wave 2 complete: #86, #87, #88 merged. Wave 3 next (UI nits: #111, #113, #114, #115, #116)."**
- [ ] **Step 3: Wait for user "continue" before Wave 3.**

---

## Wave 3 — UI nits (5 issues)

All Sonnet, all small Swift changes. PR titles use Conventional Commits `fix:` or `refactor:` as fits.

### Task 7: Issue #111 — Library error banner double-prefix

**Files:**
- Modify: `App/Features/Library/LibraryView.swift:110-117` (`errorBanner(_:)`) and call sites at `:137,152` — adopt option (a): banner uses `Text(error)` verbatim; each error source supplies its own prefix (`handleRowTap`, `openStream` sites already do)

**Model:** Sonnet
**Branch:** `fix/library-error-banner-prefix`
**Spec refs:** None (bug fix in UI). `.claude/specs/06-brand.md` § Voice for error copy tone.
**Verify commands:**
```bash
xcodebuild build -scheme ButterBar -destination 'platform=macOS' 2>&1 | tail -20
# Expected: BUILD SUCCEEDED
xcodebuild test -scheme ButterBar -only-testing:ButterBarTests/LibrarySnapshotTests -destination 'platform=macOS' 2>&1 | tail -20
# Expected: tests pass (snapshot baselines should not shift; copy wording in the banner view changes but the error-state baseline is only one of the variants)
```
Note: if the light/dark error-state baselines change by more than the textual difference, halt for reviewer judgement on whether to re-record baselines.

- [ ] **Step 1: Apply sub-step A for issue 111.**
- [ ] **Step 2: Sub-step B — `git checkout main && git checkout -b fix/library-error-banner-prefix`.**
- [ ] **Step 3: Sub-step C — dispatch Sonnet implementer with the brief. Specifically call out: "The fix is option (a) from the issue — use `Text(error)` verbatim in `errorBanner`, and ensure every write site (`loadLibrary`, `handleRowTap`, `openStream`) writes a properly-prefixed message."**
- [ ] **Step 4: Sub-step D — re-run verify commands.**
- [ ] **Step 5: Sub-step E — `gh pr create --title "fix: library error banner no longer double-stacks prefixes"`.**
- [ ] **Step 6: Sub-step F — Opus review.**
- [ ] **Step 7: Sub-step G — on merge, in TASKS.md Wave-6 `T-UI-LIBRARY` follow-up block, strike-through `#111` note.**

### Task 8: Issue #113 — HUD initial visibility timer

**Files:**
- Modify: `App/Features/Player/PlayerView.swift:18,67-89` — start 3 s auto-hide timer in `.onAppear` so HUD self-hides without requiring mouse activity (the first option from the issue)
- Update: comment at `:12-15` documenting the new behaviour

**Model:** Sonnet
**Branch:** `fix/player-hud-initial-hide-timer`
**Spec refs:** `.claude/specs/06-brand.md` § Motion.
**Verify commands:**
```bash
xcodebuild build -scheme ButterBar -destination 'platform=macOS' 2>&1 | tail -20
xcodebuild test -scheme ButterBar -only-testing:ButterBarTests/PlayerHUDSnapshotTests -destination 'platform=macOS' 2>&1 | tail -20
# Expected: BUILD SUCCEEDED; snapshot tests pass (this change is runtime-only; compile-time snapshots of the HUD at a fixed state should not shift)
```

- [ ] **Step 1: Apply sub-step A for issue 113.**
- [ ] **Step 2: Sub-step B — `git checkout main && git checkout -b fix/player-hud-initial-hide-timer`.**
- [ ] **Step 3: Sub-step C — dispatch Sonnet implementer. Prefer option 1 ("start auto-hide timer in `.onAppear`") per issue guidance. Add a unit test if feasible; otherwise document that coverage is via manual QA.**
- [ ] **Step 4: Sub-step D — re-run verify.**
- [ ] **Step 5: Sub-step E — `gh pr create --title "fix: HUD self-hides after 3s without requiring mouse activity"`.**
- [ ] **Step 6: Sub-step F — Opus review.**
- [ ] **Step 7: Sub-step G — on merge, strike-through `#113` in T-UI-PLAYER follow-up block in TASKS.md.**

### Task 9: Issue #114 — drop pre-Tahoe fallbacks

**Files:**
- Modify: `App/Features/Player/StreamHealthHUD.swift:172` — remove `if #available(macOS 26, *)` guard around `.glassEffect(.regular.interactive())`; inline the call
- Modify: any other `#available(macOS 26, *)` sites discovered by grep in `App/`, `EngineService/`, `Packages/`
- Option per issue: remove else branches entirely (preferred), or replace with `#warning("Fallback unreachable; deployment target is 26.0")`

**Model:** Sonnet
**Branch:** `refactor/drop-pre-tahoe-fallbacks`
**Spec refs:** `.claude/specs/09-platform-tahoe.md` § Deployment target; addendum A18.
**Verify commands:**
```bash
grep -rn "#available(macOS 2[6-9]" App EngineService Packages 2>/dev/null | grep -v ".git"
# Expected: no matches after the fix
xcodebuild build -scheme ButterBar -destination 'platform=macOS' 2>&1 | tail -20
xcodebuild build -scheme EngineService -destination 'platform=macOS' 2>&1 | tail -20
xcodebuild test -scheme ButterBar -only-testing:ButterBarTests/PlayerHUDSnapshotTests -destination 'platform=macOS' 2>&1 | tail -20
# Expected: all pass; snapshot tests unchanged (removing an unreachable fallback does not change runtime behaviour)
```

- [ ] **Step 1: Apply sub-step A for issue 114.**
- [ ] **Step 2: Sub-step B — `git checkout main && git checkout -b refactor/drop-pre-tahoe-fallbacks`.**
- [ ] **Step 3: Sub-step C — dispatch Sonnet implementer. Explicitly authorise the grep-then-remove pattern. Emphasise: "Prefer removing guards entirely. Only keep a `#warning` marker if the else branch has documentation value."**
- [ ] **Step 4: Sub-step D — re-run the grep (must return zero matches) and both xcodebuild commands.**
- [ ] **Step 5: Sub-step E — `gh pr create --title "refactor: drop unreachable pre-Tahoe #available fallbacks"`.**
- [ ] **Step 6: Sub-step F — Opus review.**
- [ ] **Step 7: Sub-step G — on merge, strike-through `#114` in T-UI-PLAYER follow-up block in TASKS.md.**

### Task 10: Issue #115 — tint HUD glass with warm brand colour

**Files:**
- Modify: `App/Features/Player/StreamHealthHUD.swift:175` — apply `.tint(BrandColors.butter)` or `.tint(BrandColors.cocoa)` to the `.glassEffect(.regular.interactive())` call. Prefer `butter` per the warm-palette directive; reviewer can push back.
- Snapshot baselines: 6 existing (`PlayerHUDSnapshotTests`, 3 tiers × 2 modes) may shift due to tint. Re-record baselines if needed (commit the new PNGs).

**Model:** Sonnet
**Branch:** `fix/hud-glass-brand-tint`
**Spec refs:** `.claude/specs/06-brand.md` § Colour palette.
**Verify commands:**
```bash
xcodebuild test -scheme ButterBar -only-testing:ButterBarTests/PlayerHUDSnapshotTests -destination 'platform=macOS' 2>&1 | tail -40
# If tests fail due to pixel drift: the implementer should re-record baselines (using the project's snapshot-recording flag, typically an env var or scheme arg) and commit the new PNGs. Re-run tests. Expected: pass after re-record.
```

- [ ] **Step 1: Apply sub-step A for issue 115.**
- [ ] **Step 2: Sub-step B — `git checkout main && git checkout -b fix/hud-glass-brand-tint`.**
- [ ] **Step 3: Sub-step C — dispatch Sonnet implementer. Call out explicitly: "Tier colour strip + tier label stay as-is (they carry identity). Only the glass surface tint is new. If the 6 baselines shift, re-record them and include the new PNGs in the commit. Verify each tier is still readable — that's the acceptance gate."**
- [ ] **Step 4: Sub-step D — re-run the snapshot tests.**
- [ ] **Step 5: Sub-step E — `gh pr create --title "fix: tint HUD glass with warm brand colour"`. If baselines were re-recorded, note this in the PR body.**
- [ ] **Step 6: Sub-step F — Opus review. Reviewer will inspect the re-recorded PNGs if any.**
- [ ] **Step 7: Sub-step G — on merge, strike-through `#115` in T-UI-PLAYER follow-up block.**

### Task 11: Issue #116 — BrandColors.videoLetterbox token

**Files:**
- Modify: `App/Brand/BrandColors.swift` — add `static let videoLetterbox: Color = .black` with a comment explaining it is always black
- Modify: `App/Features/Player/PlayerView.swift:31` — replace `Color.black` with `BrandColors.videoLetterbox`
- Grep: any other `Color.black` in `App/Features/**` — replace per token

**Model:** Sonnet
**Branch:** `refactor/brand-videoletterbox-token`
**Spec refs:** `.claude/specs/06-brand.md` § Colour palette ("every colour reference is a `BrandColors.*` token").
**Verify commands:**
```bash
grep -rn "Color\.black" App/Features 2>/dev/null
# Expected: zero matches after the fix
xcodebuild build -scheme ButterBar -destination 'platform=macOS' 2>&1 | tail -20
xcodebuild test -scheme ButterBar -only-testing:ButterBarTests/PlayerHUDSnapshotTests -destination 'platform=macOS' 2>&1 | tail -20
# Expected: BUILD SUCCEEDED; snapshot tests pass (no visual change)
```

- [ ] **Step 1: Apply sub-step A for issue 116.**
- [ ] **Step 2: Sub-step B — `git checkout main && git checkout -b refactor/brand-videoletterbox-token`.**
- [ ] **Step 3: Sub-step C — dispatch Sonnet implementer.**
- [ ] **Step 4: Sub-step D — re-run grep + build + test.**
- [ ] **Step 5: Sub-step E — `gh pr create --title "refactor: introduce BrandColors.videoLetterbox token"`.**
- [ ] **Step 6: Sub-step F — Opus review.**
- [ ] **Step 7: Sub-step G — on merge, strike-through `#116` in T-UI-PLAYER follow-up block.**

### Task 12: Wave 3 closing checkpoint

- [ ] **Step 1: Summarise Wave 3 to user.**
- [ ] **Step 2: Update session-resume memory — body replaced with state after Wave 3 ("UI nits merged (#111, #113, #114, #115, #116). Wave 4 next (#89 → #90).").**
- [ ] **Step 3: Wait for user "continue".**

---

## Wave 4 — Bridge / Alerts (2 issues, hard dep: #89 before #90)

### Task 13: Issue #89 — add pieceIndex to piece_finished_alert dict

**Files:**
- Modify: `EngineService/Bridge/TorrentBridge.mm` `_drainAlerts` — for `piece_finished_alert`, add `dict[@"pieceIndex"] = @((int)pfa->piece_index);`
- Modify: `EngineService/Bridge/TorrentAlert.swift` — `from(_:)` reads `dict["pieceIndex"]` instead of parsing `extractPieceIndex(from:)`. Deprecate/remove the message-string parser if no other call site uses it.

**Model:** Sonnet
**Branch:** `fix/bridge-piece-index-alert`
**Spec refs:** `.claude/specs/01-architecture.md` § TorrentBridge; `.claude/specs/03-xpc-contract.md`.
**Verify commands:**
```bash
xcodebuild build -scheme EngineService -destination 'platform=macOS' 2>&1 | tail -20
# Optional if a real magnet is available locally:
# ./.build/Debug/EngineService --stream-e2e-self-test <magnet-or-torrent-path> 2>&1 | tail -30
# Expected: exit 0 with "piece_finished pieceIndex=N" style output
```

- [ ] **Step 1: Apply sub-step A for issue 89.**
- [ ] **Step 2: Sub-step B — `git checkout main && git checkout -b fix/bridge-piece-index-alert`.**
- [ ] **Step 3: Sub-step C — dispatch Sonnet implementer. In the brief, add: "ObjC++ edit in TorrentBridge.mm; Swift-side consumer in TorrentAlert.swift. Remove `extractPieceIndex(from:)` if unused after. Add a unit test in `Packages/EngineStore` or `EngineService` tests that round-trips a synthetic piece_finished dict."**
- [ ] **Step 4: Sub-step D — re-run build.**
- [ ] **Step 5: Sub-step E — `gh pr create --title "fix: add pieceIndex field to piece_finished_alert dict"`.**
- [ ] **Step 6: Sub-step F — Opus review.**
- [ ] **Step 7: Sub-step G — act on verdict. Must merge before Task 14 starts.**

### Task 14: Issue #90 — populate FileAvailabilityDTO availableRanges

**Files:**
- Modify: `EngineService/Bridge/AlertDispatcher.swift` `emitFileAvailabilityChanged` — use bridge's `havePieces(torrentID:)` + `pieceLength(torrentID:)` + `fileByteRange(torrentID:fileIndex:)` to map downloaded pieces → byte ranges, coalesce adjacent ranges, populate `availableRanges: [ByteRangeDTO]`

**Model:** Sonnet
**Branch:** `fix/alertdispatcher-availability-ranges`
**Spec refs:** `.claude/specs/03-xpc-contract.md` § DTOs; `.claude/specs/04-piece-planner.md` (piece↔byte mapping).
**Prereq:** Task 13 merged (#89 provides reliable pieceIndex).
**Verify commands:**
```bash
xcodebuild build -scheme EngineService -destination 'platform=macOS' 2>&1 | tail -20
# If there are unit tests for AlertDispatcher, run them:
swift test --package-path Packages/EngineInterface 2>&1 | tail -20
# Expected: BUILD SUCCEEDED; tests pass
```

- [ ] **Step 1: Apply sub-step A for issue 90. Additional pre-flight: confirm Task 13 is merged (`gh pr list --search "fix: add pieceIndex" --state merged | grep -q . || halt`).**
- [ ] **Step 2: Sub-step B — `git checkout main && git pull && git checkout -b fix/alertdispatcher-availability-ranges`.**
- [ ] **Step 3: Sub-step C — dispatch Sonnet implementer. Brief MUST note: "#89 just merged; use the new `dict[pieceIndex]` path, not the message-string parse. Add a coalesce helper that combines contiguous piece ranges into one `ByteRangeDTO`. Write unit tests with a synthetic bitmap that exercises: no pieces, first piece only, contiguous run, scattered pieces, all pieces."**
- [ ] **Step 4: Sub-step D — re-run build + swift test.**
- [ ] **Step 5: Sub-step E — `gh pr create --title "fix: populate FileAvailabilityDTO.availableRanges from piece bitmap"`.**
- [ ] **Step 6: Sub-step F — Opus review.**
- [ ] **Step 7: Sub-step G — act on verdict. On merge, strike-through `#90` follow-up note in T-BRIDGE-ALERTS block of TASKS.md.**

### Task 15: Wave 4 closing checkpoint

- [ ] **Step 1: Summarise Wave 4 to user.**
- [ ] **Step 2: Update session-resume memory — body replaced with "Bridge + alerts complete (#89, #90). Wave 5 next (#110, #117, #92)."**
- [ ] **Step 3: Wait for user "continue".**

---

## Wave 5 — Cross-boundary (3 issues)

### Task 16: Issue #110 — PlayerViewModel re-subscribe after XPC reconnect

**Files:**
- Modify: `App/Features/Player/PlayerViewModel.swift:85-104` — after XPC reconnect, rebind to the new `EngineEventHandler.streamHealthChangedSubject`. Remove the deferred-fix comment block.
- Likely touches: `App/Shared/EngineClient.swift` (expose invalidation / reconnect hook), `App/Shared/EngineEventHandler.swift` (fresh instance semantics)
- Test: add a unit test or self-test that simulates reconnect and asserts the HUD resumes receiving events

**Model:** Sonnet
**Branch:** `fix/player-hud-reconnect-resubscribe`
**Spec refs:** `.claude/specs/03-xpc-contract.md` § Connection model.
**Verify commands:**
```bash
xcodebuild build -scheme ButterBar -destination 'platform=macOS' 2>&1 | tail -20
xcodebuild test -scheme ButterBar -only-testing:ButterBarTests/PlayerHUDSnapshotTests -destination 'platform=macOS' 2>&1 | tail -20
# If the implementer adds a reconnect self-test (recommended):
# .build/Debug/EngineService --xpc-reconnect-self-test 2>&1 | tail -20 (if that self-test is added)
```

- [ ] **Step 1: Apply sub-step A for issue 110.**
- [ ] **Step 2: Sub-step B — `git checkout main && git checkout -b fix/player-hud-reconnect-resubscribe`.**
- [ ] **Step 3: Sub-step C — dispatch Sonnet implementer. Emphasise: "`PlayerViewModel` captures `engineClient.events` at init. After reconnect, the subject identity changes. Options: (a) observe a publisher of `events` (which republishes on reconnect) from PlayerViewModel, (b) have EngineClient expose a reconnect callback that PlayerViewModel hooks. Pick whichever is simpler and matches how the Library view model handles reconnect (look at `LibraryViewModel.start()`). Add a unit test with a fake EngineClient."**
- [ ] **Step 4: Sub-step D — re-run build + snapshot tests.**
- [ ] **Step 5: Sub-step E — `gh pr create --title "fix: PlayerViewModel resubscribes to StreamHealth after XPC reconnect"`.**
- [ ] **Step 6: Sub-step F — Opus review.**
- [ ] **Step 7: Sub-step G — on merge, strike-through `#110` in T-UI-PLAYER follow-up block.**

### Task 17: Issue #117 — typed StreamHealthDTO.tier enum

**Files:**
- Modify: `Packages/EngineInterface/Sources/EngineInterface/` — add `StreamHealthTier.swift` with `enum StreamHealthTier: String, Codable, Sendable { case healthy, marginal, starving }`
- Modify: `Packages/XPCMapping/Sources/XPCMapping/` — DTO↔domain mapping converts `tier as String` ↔ `StreamHealthTier`
- Modify: `App/Features/Player/StreamHealthHUD.swift:42,61,116` — replace string-keyed switches with enum-keyed
- Keep: wire format (`NSString`) unchanged — no XPC contract break

**Model:** Sonnet
**Branch:** `refactor/streamhealthtier-enum`
**Spec refs:** `.claude/specs/02-stream-health.md`; `.claude/specs/03-xpc-contract.md`.
**Verify commands:**
```bash
swift test --package-path Packages/EngineInterface 2>&1 | tail -20
swift test --package-path Packages/XPCMapping 2>&1 | tail -20
xcodebuild build -scheme ButterBar -destination 'platform=macOS' 2>&1 | tail -20
xcodebuild test -scheme ButterBar -only-testing:ButterBarTests/PlayerHUDSnapshotTests -destination 'platform=macOS' 2>&1 | tail -20
# Expected: all pass; snapshots unchanged (no visual impact)
```

- [ ] **Step 1: Apply sub-step A for issue 117.**
- [ ] **Step 2: Sub-step B — `git checkout main && git checkout -b refactor/streamhealthtier-enum`.**
- [ ] **Step 3: Sub-step C — dispatch Sonnet implementer. Brief addition: "The wire stays NSString — the enum is a domain-layer projection only. Add a mapping test that round-trips each of the three tiers and also handles an unknown string (suggest: map to a sentinel `.starving` with a warning log, or throw, per the reviewer's call — pick the safer option). Do not claim this touches the XPC contract; it is additive."**
- [ ] **Step 4: Sub-step D — re-run all four verify commands.**
- [ ] **Step 5: Sub-step E — `gh pr create --title "refactor: type StreamHealthDTO.tier via Swift enum at domain boundary"`.**
- [ ] **Step 6: Sub-step F — Opus review. Reviewer should confirm the wire format is unchanged (inspect the DTO's encode/decode).**
- [ ] **Step 7: Sub-step G — on merge, strike-through `#117` in T-UI-PLAYER follow-up block.**

### Task 18: Issue #92 — statusSnapshot includes torrent name

**Files:**
- Modify: `EngineService/Bridge/TorrentBridge.mm` `statusSnapshot` — add `dict[@"name"] = ...` using `torrent_info::name()` once metadata available; or option 2 per issue body (store-layer lookup).
- Per issue: option 2 (store-layer lookup) preferred for user-supplied names + persistence. This requires reading `Packages/EngineStore` to see the current shape.
- Modify: `EngineService/Bridge/AlertDispatcher.swift` — stop using torrentID-as-name placeholder; use the new name.

**Model:** Sonnet
**Branch:** `fix/bridge-status-torrent-name`
**Spec refs:** `.claude/specs/01-architecture.md` § TorrentBridge; `.claude/specs/05-cache-policy.md` § Schema (torrent names field).
**Verify commands:**
```bash
xcodebuild build -scheme EngineService -destination 'platform=macOS' 2>&1 | tail -20
swift test --package-path Packages/EngineStore 2>&1 | tail -20
# If bridge self-test covers statusSnapshot name:
# .build/Debug/EngineService --bridge-self-test 2>&1 | tail -30
```

- [ ] **Step 1: Apply sub-step A for issue 92.**
- [ ] **Step 2: Sub-step B — `git checkout main && git checkout -b fix/bridge-status-torrent-name`.**
- [ ] **Step 3: Sub-step C — dispatch Sonnet implementer. Brief: "Read Packages/EngineStore first to see if there's a names table/column. Pick option 1 (bridge-only, from torrent_info::name()) if the store doesn't have a place for names yet; pick option 2 (store-layer lookup) if it does. Return a VERDICT comment in the PR body describing which path was chosen and why."**
- [ ] **Step 4: Sub-step D — re-run build + store tests.**
- [ ] **Step 5: Sub-step E — `gh pr create --title "fix: statusSnapshot includes torrent name"`.**
- [ ] **Step 6: Sub-step F — Opus review. Reviewer confirms the option-1/option-2 choice is sound.**
- [ ] **Step 7: Sub-step G — on merge, strike-through `#92` in T-BRIDGE-API follow-up block.**

### Task 19: Wave 5 closing checkpoint

- [ ] **Step 1: Summarise Wave 5 to user.**
- [ ] **Step 2: Update session-resume memory — body: "Cross-boundary work complete (#110, #117, #92). Wave 6 next, final wave (#107, #18 — design-heavy, Opus-implemented)."**
- [ ] **Step 3: Wait for user "continue".**

---

## Wave 6 — Design-heavy (2 issues, Opus-implemented)

Both issues are design calls, not mechanical implementation. Routing Opus as implementer means the reviewer is also Opus (same session? different session? Different session — dispatched fresh). That weakens the model/reviewer independence — the user accepted this trade-off in the design. Reviewer should be briefed to apply extra scrutiny to design rationale.

### Task 20: Issue #107 — seek-to-first-frame SLA + regression threshold

**Files:**
- Modify: `docs/benchmarks/seek-baseline.json` — set `regression_threshold_pct` to a specific number (was `null`)
- Modify: `.claude/specs/02-stream-health.md` AND/OR `.claude/specs/04-piece-planner.md` AND/OR a new addendum A23+ — name the numerical SLA per fixture (p50 ≤ X ms on arm64/macOS 26.5, per fixture)
- Modify: `.claude/specs/00-addendum.md` — add addendum entry if that's the chosen route
- Optional: CI config (`.github/workflows/ci.yml`) — add a regression gate on seek bench (if the design says so)

**Model:** Opus (design call)
**Branch:** `docs/seek-sla-and-threshold`
**Spec refs:** `.claude/specs/02-stream-health.md`, `.claude/specs/04-piece-planner.md`, `.claude/specs/05-cache-policy.md`, `docs/benchmarks/seek-baseline.json`, `docs/benchmarks/README.md`.
**Verify commands:**
```bash
./scripts/run-seek-bench.sh 2>&1 | tail -20
# Expected: bench still green against the baseline; regression_threshold_pct is read correctly (no JSON parse error)
grep -n "regression_threshold_pct" docs/benchmarks/seek-baseline.json
# Expected: non-null value
grep -nE "seek.*SLA|seek-to-first-frame" .claude/specs/*.md | head -10
# Expected: at least one match in the target spec
```

- [ ] **Step 1: Apply sub-step A for issue 107.**
- [ ] **Step 2: Sub-step B — `git checkout main && git checkout -b docs/seek-sla-and-threshold`.**
- [ ] **Step 3: Sub-step C — dispatch Opus implementer. Brief is the same template but with MODEL=opus. Additional directive: "This is a design call. Follow `.claude/agents/opus-designer.md`. Decide (and justify in the PR body): (1) per-fixture SLA numbers (anchored to the current baseline with appropriate margin), (2) a regression_threshold_pct (suggest: a single number like 25% to start — defensible and not over-tuned), (3) whether CI should gate on this in v1 (default: advisory for v1, gated at v1.1), (4) which spec(s) receive the SLA text. This issue edits `.claude/specs/`; spec-edit authorisation is granted for this task. PR title MUST begin with `[spec]`."**
- [ ] **Step 4: Sub-step D — re-run the verify commands.**
- [ ] **Step 5: Sub-step E — `gh pr create --title "[spec] docs: seek-to-first-frame SLA + regression threshold"`.**
- [ ] **Step 6: Sub-step F — Opus review. Because implementer is also Opus, reviewer brief has an ADDITIONAL line: "Apply extra scrutiny to design rationale. Opus-implemented PRs can be overconfident. Push back hard on unjustified numbers."**
- [ ] **Step 7: Sub-step G — on merge, strike-through `#107` in T-PERF-SEEK-BENCH follow-up block.**

### Task 21: Issue #18 — define player state model

**Files:**
- Modify: `.claude/specs/07-product-surface.md` § Module 2 (Playback UX) — add a § Player state model subsection defining states (idle/loading/playing/paused/buffering/seeking/ended/error), transitions, and invariants
- Create: `App/Features/Player/PlayerState.swift` — Swift enum modelling the states + transition helper
- Modify: `App/Features/Player/PlayerViewModel.swift` — adopt the enum; retire any ad-hoc boolean flags
- Test: `Tests/ButterBarTests/PlayerStateTests.swift` — state-transition test matrix
- Optional: diagram in `docs/architecture/player-state.md` (if the orchestrator decides this is worth a separate doc — usually inline in spec 07 is enough)

**Model:** Opus (design call; issue is labelled `priority:p0` and `type:feature`)
**Branch:** `feat/player-state-model`
**Spec refs:** `.claude/specs/07-product-surface.md` § Module 2; `.claude/specs/02-stream-health.md` (for buffering-state integration); `.claude/specs/03-xpc-contract.md` (for stream lifecycle events).
**Verify commands:**
```bash
xcodebuild build -scheme ButterBar -destination 'platform=macOS' 2>&1 | tail -20
xcodebuild test -scheme ButterBar -only-testing:ButterBarTests/PlayerStateTests -destination 'platform=macOS' 2>&1 | tail -20
xcodebuild test -scheme ButterBar -only-testing:ButterBarTests/PlayerHUDSnapshotTests -destination 'platform=macOS' 2>&1 | tail -20
# Expected: build succeeds; new PlayerStateTests passes; snapshots don't shift
grep -n "Player state model" .claude/specs/07-product-surface.md
# Expected: at least one match (new subsection)
```

- [ ] **Step 1: Apply sub-step A for issue 18. Additional check: the issue body says "populate acceptance criteria before picking this up" — since we are picking it up, draft acceptance criteria from the issue-conversion-mapping (item 2.1) and add them as a comment on the issue via `gh issue comment 18 --body "..."` BEFORE branching. This keeps the issue trail honest.**
- [ ] **Step 2: Sub-step B — `git checkout main && git checkout -b feat/player-state-model`.**
- [ ] **Step 3: Sub-step C — dispatch Opus implementer. Model=opus. Extensive brief: "This adds a state machine to the player UX. Design inputs: stream lifecycle events from EngineInterface, AVPlayer observations (rate, timeControlStatus, currentItem.status), user actions (play/pause/seek/close), StreamHealth tier. Output: a `PlayerState` enum, a transition table, invariants (e.g., .playing implies .loading has completed), and a ViewModel adapter. Scope edit to spec 07 (new subsection), one new Swift file, one modified Swift file, one new test file. PR title prefix `[spec]` because spec 07 is frozen. Include a transition diagram in the PR body (ASCII or Mermaid — the reviewer can read both)."**
- [ ] **Step 4: Sub-step D — re-run build + both test suites + grep.**
- [ ] **Step 5: Sub-step E — `gh pr create --title "[spec] feat: define player state model (spec 07 § Module 2)"`.**
- [ ] **Step 6: Sub-step F — Opus review. Same extra-scrutiny directive as Task 20. Reviewer specifically checks: transition completeness, invariant enforcement, ViewModel non-regression.**
- [ ] **Step 7: Sub-step G — on merge, the issue closes via `Closes #18`. No TASKS.md strike-through needed (issue wasn't a T-\* follow-up note).**

### Task 22: Wave 6 closing checkpoint + loop termination

- [ ] **Step 1: Summarise Wave 6 to user (both final issues).**
- [ ] **Step 2: Terminal-state verification.**
  ```bash
  gh issue list --state open --label module:engine --json number,title
  # Expected: empty, or only issues NOT in the original 16 (i.e., follow-ups filed during the loop, or out-of-scope issues that appeared mid-loop)
  ```
- [ ] **Step 3: Final session-resume memory update.** Body replaced with:
      ```
      Issue loop COMPLETE — all 16 in-scope phase 0–6 engine issues merged. Follow-ups filed during loop: <list>. Main is clean. Next up per TASKS.md: T-DOC-ARCHITECTURE (Phase 7).
      ```
- [ ] **Step 4: Final summary message to user.** Include: all 16 issues merged with PR links, all follow-ups filed with issue links, any halts encountered + how they were resolved, suggested next step.

---

## Halt-path protocol (applies to any task above)

When the loop halts mid-wave, do NOT simply stop — present a structured halt message so the user can decide quickly:

```
🛑 LOOP HALTED — Wave <N>, Task <N> (issue #<N>)

Halt reason: <CHANGES-REQUESTED after 2 iterations | BLOCKED | PRE-FLIGHT FAILED | CI FAILED | MERGE CONFLICT>

State:
- Branch: <name> (unmerged, has X commits)
- PR: <url if any>
- Implementer output: <summary or path to full output>
- Reviewer output (if applicable): <summary or path>

Suggested next step: <specific action user should consider>

Awaiting instruction:
  (a) Take over manually — I'll stop here
  (b) Skip this issue and continue to next
  (c) Adjust the issue/spec and re-dispatch
  (d) Abandon this wave and jump to the next
```

---

## Self-review notes (performed before handoff)

- **Spec coverage:** All 16 in-scope issues from the design spec have a corresponding task (Task 1, 3–5, 7–11, 13–14, 16–18, 20–21). Pause/checkpoint tasks at wave ends (Task 2, 6, 12, 15, 19, 22). ✓
- **No placeholders:** Every task has explicit Files, Model, Branch, Spec refs, Verify commands, and 7 concrete checkboxes. ✓
- **Type consistency:** All references to `StreamHealthDTO`/`StreamHealthTier`/`BrandColors`/`AlertDispatcher`/etc. match their live names in the repo. Tasks that depend on earlier task output (Task 14 depends on Task 13's pieceIndex field name) state the dependency explicitly. ✓
- **Terminal states:** Every implementer return (`READY-FOR-PR`/`BLOCKED`/`VERIFY-FAILED`) and every reviewer verdict (`APPROVE`/`APPROVE-WITH-FOLLOW-UPS`/`CHANGES-REQUESTED`/`BLOCKED`) has explicit orchestrator handling in sub-step G or the halt-path protocol. ✓
