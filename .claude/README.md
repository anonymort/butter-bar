# .claude directory — structure

```
.claude/
├── specs/                          # Frozen specs. Sonnet reads, Opus revises.
│   ├── 00-addendum.md              # Revision decisions. Overrides numbered specs on conflict.
│   ├── 01-architecture.md          # Engine: top-level shape, components, exclusions
│   ├── 02-stream-health.md         # Engine: canonical StreamHealth type + tier semantics
│   ├── 03-xpc-contract.md          # Engine: NSXPCConnection protocols + DTO definitions
│   ├── 04-piece-planner.md         # Engine: planner contract, trace schema, fixture set
│   ├── 05-cache-policy.md          # Engine: piece-granular eviction, resume offsets
│   ├── 06-brand.md                 # Brand: identity, voice, palette, logo specs (Tahoe)
│   ├── 07-product-surface.md       # Product: catalogue, sync, providers, watch state
│   ├── 08-issue-workflow.md        # Process: GitHub issue/branch/PR conventions
│   └── 09-platform-tahoe.md        # Platform: macOS 26 target, SDK, Liquid Glass stance
├── tasks/
│   └── TASKS.md                    # Engine build queue with blockers
└── agents/
    ├── opus-designer.md            # Role instructions for Opus
    └── sonnet-implementer.md       # Role instructions for Sonnet
```

The `icons/` folder at the repo root is the supplied logo source material (flat package + `ButterBar-LiquidGlass-prep/` subfolder). It's referenced by spec 06 and consumed by `T-BRAND-ASSETS`. It is not in this `.claude/` tree because design assets are not specs.

## How the pieces fit

- `CLAUDE.md` is the root. Read first, always.
- `00-addendum.md` is read next. It resolves cross-cutting ambiguities and wins over numbered specs where they conflict.
- Numbered specs are the contract. Frozen until Opus revises via a new addendum entry or a bumped revision block. Sonnet implements against them.
- `TASKS.md` is the work queue. Phased, with explicit blockers. Pick top-down.
- Agent files define the role each tier plays when invoked. They enforce the separation of concerns.

## How a typical Sonnet invocation looks

```
You are operating per .claude/agents/sonnet-implementer.md.
Pick up task T-PLANNER-CORE from .claude/tasks/TASKS.md.
Relevant specs: .claude/specs/04-piece-planner.md and .claude/specs/02-stream-health.md.
Implement against the frozen spec. Do not modify specs.
Acceptance criteria are in the task description. Mark REVIEW when done.
```

## How a typical Opus invocation looks

```
You are operating per .claude/agents/opus-designer.md.
Review T-PLANNER-CORE (currently REVIEW).
Read the diff, run the fixture tests mentally against the spec, and mark DONE or return with specific feedback.
```
