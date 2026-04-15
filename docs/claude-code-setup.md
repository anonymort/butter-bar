# Setting up Butter Bar in Claude Code

This document is the bootstrap procedure for taking the contents of `butterbar.zip` and getting them into the GitHub repo and Claude Code, ready for engine and product work to begin.

Read it through once before running any commands. The order matters; some steps create state that later steps depend on.

## Prerequisites

- **macOS Tahoe (26.0) or later** with **Xcode 26+** installed.
- The supplied `butter-bar-logo` source material available locally:
  - **Flat package** (legacy / preview): SVG, PNG @1x/@2x/@3x, `ButterBar.iconset/`, `ButterBar.icns`, `butter-bar-logo-1024.png`.
  - **Liquid Glass prep package**: `ButterBar-LiquidGlass-prep/` folder containing layered transparent PNGs, revised SVG master, flattened preview, size exports, and a README documenting layer order.
- [GitHub CLI](https://cli.github.com/) (`gh`) installed and authenticated against your GitHub account.
- `jq` installed (`brew install jq`).
- `python3` (preinstalled on macOS).
- [Claude Code](https://claude.com/claude-code) installed and signed in.
- Push access to `https://github.com/anonymort/butter-bar`.

## Step 1 — Unpack into the repo

```bash
# Clone the repo (only contains the placeholder README right now)
gh repo clone anonymort/butter-bar
cd butter-bar

# Create the docs branch
git checkout -b docs/initial-pack

# Unzip the pack into the repo root
unzip ~/Downloads/butter-bar.zip -d /tmp/butter-bar-extract

# Move everything except the wrapper directory into the repo
shopt -s dotglob
mv /tmp/butter-bar-extract/butter-bar/* .
shopt -u dotglob

# Drop in the supplied logo source material at the top-level icons/ directory.
# Both the flat package AND the Liquid Glass prep folder are expected.
mkdir -p icons
cp ~/path/to/your/butter-bar-logo.svg \
   ~/path/to/your/butter-bar-logo-1024.png \
   ~/path/to/your/butter-bar-logo@1x.png \
   ~/path/to/your/butter-bar-logo@2x.png \
   ~/path/to/your/butter-bar-logo@3x.png \
   ~/path/to/your/ButterBar.icns \
   icons/
cp -r ~/path/to/your/ButterBar.iconset icons/
cp -r ~/path/to/your/ButterBar-LiquidGlass-prep icons/

# Verify the structure
ls -la
ls -la .claude/specs/
ls -la icons/
ls -la icons/ButterBar-LiquidGlass-prep/
ls -la .github/
ls -la scripts/
```

Expected top-level contents after unpacking:

```
README.md
CLAUDE.md
CONTRIBUTING.md
CODEOWNERS
.gitignore
.claude/        (specs, tasks, agents, README)
.github/        (issue templates, PR template, workflow)
icons/          (supplied logo source: SVG, PNGs, .iconset, .icns, ButterBar-LiquidGlass-prep/)
docs/           (issue-conversion-mapping.md, claude-code-setup.md)
scripts/        (setup-repo.sh, seed-issues.sh)
```

The `icons/ButterBar-LiquidGlass-prep/` subfolder is the source material for `T-BRAND-ASSETS` (Icon Composer authoring). The flat assets above it are legacy / preview / fallback. Both are version-controlled.

## Step 2 — Commit and push the docs branch

```bash
git add .
git commit -m "docs: initial spec pack and repo scaffolding

- Spec set 00 (addendum) + 01-08 (engine, brand, product surface, workflow)
- CLAUDE.md orchestration root
- Agent role files for Opus and Sonnet
- GitHub issue templates, PR template, CI workflow
- CODEOWNERS, CONTRIBUTING
- Scripts: setup-repo.sh, seed-issues.sh
- Issue conversion mapping document"

git push -u origin docs/initial-pack

# Open a PR
gh pr create \
  --title "docs: initial spec pack and repo scaffolding" \
  --body "Imports the full spec pack and GitHub workflow scaffolding.

Closes nothing (this is the bootstrap PR).

Specs:
- .claude/specs/00-addendum.md (revision decisions)
- .claude/specs/01-architecture.md through 08-issue-workflow.md

Workflow:
- .github/ISSUE_TEMPLATE/* (epic, feature, bug, spike, task)
- .github/PULL_REQUEST_TEMPLATE.md
- .github/workflows/ci.yml
- CODEOWNERS, CONTRIBUTING.md

Scripts:
- scripts/setup-repo.sh (labels, milestones, epics)
- scripts/seed-issues.sh (feature issues from mapping doc)

Mapping:
- docs/issue-conversion-mapping.md (review before bulk creation)" \
  --base main \
  --head docs/initial-pack

# Merge it (squash recommended for the bootstrap commit)
gh pr merge --squash --delete-branch
```

The repo's `main` branch now has the full pack. From here on, the "no direct commits to main" rule applies.

## Step 3 — Set repo defaults

A few one-time GitHub repo settings to align with the workflow:

```bash
# Auto-delete merged branches
gh repo edit anonymort/butter-bar --delete-branch-on-merge

# Default merge commit type — squash for cleanliness
gh repo edit anonymort/butter-bar \
  --enable-squash-merge=true \
  --enable-merge-commit=false \
  --enable-rebase-merge=false

# Require PRs (no direct push to main)
# Note: this requires a paid GitHub plan or a public repo. If on a free private
# plan, enforce manually instead.
gh api -X PUT "repos/anonymort/butter-bar/branches/main/protection" \
  -f required_status_checks='null' \
  -F enforce_admins=false \
  -F required_pull_request_reviews='{"required_approving_review_count":0}' \
  -f restrictions='null' || \
  echo "(branch protection skipped — likely free private plan; enforce manually)"
```

## Step 4 — Bootstrap labels, milestones, epics

```bash
./scripts/setup-repo.sh
```

This is idempotent. It creates:
- ~25 labels (type/priority/module/special).
- 5 milestones (v1, v1.1, v1.5, v2, backlog).
- 8 epic issues, one per module from spec 07.

Verify:

```bash
gh label list --repo anonymort/butter-bar | head -30
gh issue list --repo anonymort/butter-bar --label type:epic
```

## Step 5 — Review the issue conversion mapping

**Do not skip this step.** The seed script creates ~64 child issues based on `docs/issue-conversion-mapping.md`. Read that file end-to-end and amend it before bulk creation. Common edits:

- Adjust priorities (some features you may want to demote/promote).
- Adjust dependencies (the mapping is a first pass; reality may vary).
- Remove items you've decided not to do in v1.
- Add items the spec didn't capture.

Edits go through a normal PR (branch `docs/refine-issue-mapping` or similar), following the conventions in spec 08.

## Step 6 — Dry-run, then create issues

```bash
# Dry run — shows what would be created, no side effects
./scripts/seed-issues.sh

# If the dry run looks right, actually create them
./scripts/seed-issues.sh --create
```

Expected: ~64 new issues created across milestones v1 and v1.5, labelled and prioritised. Verify with:

```bash
gh issue list --repo anonymort/butter-bar --milestone v1 --limit 100
```

## Step 7 — Link child issues to parent epics

This is currently manual. For each epic, edit its body and add `- [ ] #N <Title>` entries under "Child issues" pointing at the relevant feature issues. GitHub auto-links them and tracks completion progress automatically.

(A future improvement: extend `seed-issues.sh` to do this automatically by querying issues by module label.)

## Step 8 — Open Claude Code on the repo

```bash
cd ~/path/to/butter-bar
claude
```

Claude Code will pick up `CLAUDE.md` automatically as the project root file. Everything Claude needs to know — reading order, agent roles, addendum precedence, two-tracker model — is reachable from there.

## Step 9 — First Opus invocation (pre-flight review)

Before any code is written, do a fresh-context Opus review pass. Open Claude Code and use this prompt verbatim:

> You are operating per `.claude/agents/opus-designer.md`. This is a fresh context; you have no prior history with this project. Read the files in the order specified by your role file (CLAUDE.md, then 00-addendum.md, then specs 01–05, 06, 09, 07, 08, then TASKS.md).
>
> Then perform a final pre-implementation review pass: confirm A11–A19 are properly applied across the affected specs, confirm specs 06 and 09 are internally consistent (Tahoe targeting, Liquid Glass adoption stance, supplied icon prep package references, `App/AppIcon.icon` placement), confirm specs 07 and 08 are internally consistent and consistent with specs 01–05, and either approve the pack for execution starting at T-REPO-INIT plus the spike issues from spec 07, or append A20+ items for any remaining issues.
>
> Output: a short verdict at the top, findings underneath, and an explicit "approved" or "not approved" recommendation. Do not modify any spec — only append to `00-addendum.md` if there are findings, and only on a fresh branch.

Opus will either approve or open a `docs/addendum-aXX` branch with new addendum items. If the latter, review and merge per the normal PR process before moving on.

## Step 10 — First engine task

Once Opus approves, the first work to pick up is `T-REPO-INIT` from `.claude/tasks/TASKS.md`. Sonnet invocation:

> You are operating per `.claude/agents/sonnet-implementer.md`. This is a fresh context.
>
> Pick up task `T-REPO-INIT` from `.claude/tasks/TASKS.md`. Read your role file, the addendum, and the task itself. Do not read other specs — the task is small.
>
> Create the Xcode project structure described in CLAUDE.md → Project layout. Two targets: `ButterBar` (app) and `EngineService` (XPC service). Swift packages: `EngineInterface`, `PlannerCore`, `TestFixtures`. Empty test targets. Top-level `icons/` directory containing both the flat package and the `ButterBar-LiquidGlass-prep/` subfolder. `App/Brand/` folder. Do NOT create `App/AppIcon.icon` — that is `T-BRAND-ASSETS`, a separate task requiring Apple's Icon Composer GUI.
>
> Work on a branch named `engine/T-REPO-INIT`. When done, mark the task `DONE` in `TASKS.md` and open a PR with title `engine: T-REPO-INIT — initial Xcode project scaffolding`.

After T-REPO-INIT lands, T-SPEC-LINT (also Phase 0) can be picked up by Opus in parallel with Sonnet starting Phase 1 (T-PLANNER-TYPES).

## Step 11 — First product spike

In parallel with engine work, the metadata-source spike (issue 1.2 / OQ.1) can be picked up. This is a Claude Code spike issue, not a TASKS.md task:

> You are operating per `.claude/agents/sonnet-implementer.md`. This is a product spike, not an engine task.
>
> Read CLAUDE.md, the addendum, and `.claude/specs/07-product-surface.md` § 1 (Discovery and metadata). Then read the spike issue body for "Decision: primary metadata source (TMDB/TVDB/Trakt)".
>
> Investigate the three candidate metadata sources. Produce `docs/metadata-source-evaluation.md` covering: API quality, free-tier limits, image asset quality and licensing, response speed, dataset completeness for both films and TV. Recommend one. Open the doc as a PR on branch `spike/metadata-source-evaluation`. Comment your recommendation on the spike issue.

## Step 12 — Working pattern from here

For every subsequent piece of work:

1. Pick an issue (product surface) or task (engine).
2. Create a branch named per spec 08 conventions.
3. Read the spec sections cited in the issue/task. Read the addendum every time.
4. Implement and test.
5. Open a PR linking the issue/task; address review.
6. Merge; delete the branch.

The two trackers (TASKS.md and GitHub issues) live alongside each other. Engine tasks complete in dependency order through Phases 0–6; product issues unlock as their engine prerequisites land.

Spec changes always require an addendum item (A18+) and a revision-block bump on the affected spec, both in the same PR.

## Troubleshooting

**Q: A Sonnet sub-agent has marked a task `BLOCKED:` because of a spec ambiguity.**
A: Don't fix it in chat. Open Claude Code in Opus mode and have Opus append an addendum item resolving the ambiguity. Then unblock the task.

**Q: Two PRs are touching the same spec section.**
A: One must rebase. The addendum-item numbering is the canonical conflict signal — both PRs cannot append `A18`. Whichever lands second renumbers.

**Q: `seed-issues.sh` says it parsed 0 issues.**
A: You probably edited the mapping document and broke a table row's pipe alignment. The parser is regex-based and strict. Run from the repo root.

**Q: An engine task's acceptance includes "snapshot test" but the project doesn't have a snapshot test framework.**
A: Add the framework as a separate `task` issue first. Don't bury infrastructure additions inside feature work.

**Q: The CI link-check job is failing because my PR doesn't link an issue.**
A: It's a docs-only PR for spec changes that don't have an issue. Use `Refs #1` (the bootstrap PR) until the project gets a long-running "Spec maintenance" issue, then link that.

## Appendix: directory map

```
butter-bar/
├── README.md                    # Project intro
├── CLAUDE.md                    # Orchestration root (Claude Code reads this)
├── CONTRIBUTING.md              # Quick contributor reference
├── CODEOWNERS                   # Review routing
├── .gitignore
├── .claude/
│   ├── README.md                # Directory map
│   ├── specs/
│   │   ├── 00-addendum.md       # Revision precedence layer
│   │   ├── 01-architecture.md   # Engine top-level
│   │   ├── 02-stream-health.md
│   │   ├── 03-xpc-contract.md
│   │   ├── 04-piece-planner.md
│   │   ├── 05-cache-policy.md
│   │   ├── 06-brand.md          # Tahoe-aware brand spec (rev 3)
│   │   ├── 07-product-surface.md
│   │   ├── 08-issue-workflow.md
│   │   └── 09-platform-tahoe.md # macOS 26 platform spec
│   ├── tasks/
│   │   └── TASKS.md             # Engine build queue
│   └── agents/
│       ├── opus-designer.md     # Opus role
│       └── sonnet-implementer.md# Sonnet role
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── config.yml
│   │   ├── epic.yml
│   │   ├── feature.yml
│   │   ├── bug.yml
│   │   ├── spike.yml
│   │   └── task.yml
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── workflows/
│       └── ci.yml
├── icons/                       # Supplied logo source material
│   ├── butter-bar-logo.svg      # Flat master
│   ├── butter-bar-logo-1024.png # Flat raster master
│   ├── butter-bar-logo@1x.png   # Convenience export
│   ├── butter-bar-logo@2x.png   # Convenience export
│   ├── butter-bar-logo@3x.png   # Convenience export
│   ├── ButterBar.iconset/       # Legacy macOS icon set (inactive at v1)
│   ├── ButterBar.icns           # Legacy .icns container (inactive at v1)
│   └── ButterBar-LiquidGlass-prep/  # Layered source for Icon Composer
│       ├── README               # Layer mapping/order
│       ├── 0_*.png              # Background or first foreground layer
│       ├── 1_*.png              # Foreground layer
│       ├── 2_*.png              # Foreground layer
│       ├── 3_*.png              # Foreground layer
│       ├── butter-bar-logo.svg  # Revised SVG with layer separation
│       ├── flattened-preview.png
│       └── 16.png … 1024.png    # Size exports for legibility testing
├── docs/
│   ├── claude-code-setup.md     # This file
│   └── issue-conversion-mapping.md
└── scripts/
    ├── setup-repo.sh            # Labels, milestones, epics
    └── seed-issues.sh           # Bulk feature issue creation
```

After `T-BRAND-ASSETS` runs, an additional artefact appears:

```
butter-bar/
├── App/
│   ├── AppIcon.icon/            # Built in Icon Composer; sibling of Assets.xcassets
│   └── Assets.xcassets/         # Does NOT contain AppIcon for v1
```
