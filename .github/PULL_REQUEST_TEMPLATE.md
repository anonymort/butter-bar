<!--
  Pull request template for butter-bar.
  See .claude/specs/08-issue-workflow.md for the full PR conventions.
-->

## What this changes

<!-- One paragraph. What does this PR do, and why now. -->

## Linked issue

Closes #
<!-- Or use "Refs #N" if this PR doesn't fully close the issue. -->

## Spec references

<!-- Which spec section(s) does this implement or modify? Example: -->
<!-- - .claude/specs/04-piece-planner.md § Initial play -->
<!-- - .claude/specs/07-product-surface.md § Module 1 (Discovery) -->

## Type

<!-- Tick one. PR title prefix should match (feat:, fix:, docs:, chore:, test:, refactor:, spike:, engine:). -->

- [ ] `feat:` — new user-facing capability
- [ ] `fix:` — defect repair
- [ ] `docs:` — documentation only
- [ ] `chore:` — repo hygiene, deps, CI
- [ ] `test:` — test additions or fixes
- [ ] `refactor:` — internal change with no behavioural difference
- [ ] `spike:` — investigation outcome
- [ ] `engine:` — engine task from `.claude/tasks/TASKS.md`
- [ ] `[spec]` — modifies a frozen spec (also requires addendum item; tick this in addition to one of the above)

## Engine task

<!-- If this is engine work, which task ID? -->
- T-________

## Acceptance check

<!-- Walk through the acceptance criteria from the issue or task. -->
- [ ]
- [ ]
- [ ]

## Tests

<!-- What tests cover this change? -->
- [ ] Unit
- [ ] Integration
- [ ] Snapshot
- [ ] Manual (described below)
- [ ] N/A — explain:

## Spec drift check

<!-- For any PR touching a spec: -->
- [ ] Addendum item appended (`A__`)
- [ ] Revision block on affected spec bumped
- [ ] N/A — no spec changes

## Follow-ups

<!-- Things you noticed but did not do. These become new issues. -->
-
