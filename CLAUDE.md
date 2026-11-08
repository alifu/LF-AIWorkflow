# LF-AIWorkflow: build rules

macOS notch app (Swift/SwiftUI + C core). Plan: `.claude/plans/lf-aiworkflow.plan.md`. Tech debt: `.claude/plans/techdebt.md`.

## Depth tiers
Pick the tier before any work and say which one in the first reply.
| Tier | When | Steps | Commit |
|---|---|---|---|
| Quick | One area, <~50 lines, no new type or API | `lf-coder` (haiku or sonnet) with a test, VALIDATE, commit | `fix:` / `chore:` |
| Standard | One feature or a tech-debt pass | `lf-planner` (sonnet) batches, `lf-coder`, VALIDATE per batch, one `lf-reviewer` | `feat:` / `refactor:` |
| Full | A plan phase, or anything touching C core, spawn, persistence, security | The phase loop below with the model table | `feat: phase <N>` |
- Escalate one tier when a Quick change touches C, process spawning, persistence or file safety. The reviewer checks the tier.
- Standard or Full work not in the master plan starts with `.claude/plans/<slug>/requirements.md` from `lf-planner`; the user approves it before any code.
- Every user answer and every default chosen for the user is appended to `.claude/plans/decisions.md`.

## Phase loop (repeat for each phase)
1. Read only that phase's section of the plan (§5) and the sections it points to.
2. Run each step with the agent and model from the table below. Pass the model with the Agent tool's `model` parameter, so the model switches automatically per step.
3. A phase is done when all its tasks are done, build and tests pass (plan §8), and review has no open CRITICAL or HIGH.
4. Log tech debt, then commit (rules below).
5. Stop and report: phase done, commit hash, TD items added, next phase and its models.

## Model per phase
| Phase | Plan (`lf-planner`) | Code (`lf-coder`) | Review (`lf-reviewer`) |
|---|---|---|---|
| 1 Setup | — | haiku | — |
| 2 C core | opus | sonnet | opus |
| 3 Claude session | opus | sonnet | sonnet |
| 4 Engine + context | opus | sonnet | opus |
| 5 Notch UI | sonnet | sonnet | sonnet |
| 6 Polish + art styles | sonnet | haiku (theme tokens: sonnet) | sonnet |
| 7 Research mode | opus | sonnet | opus |
| 8 Review + hardening | — | sonnet (fixes) | opus |
| 9 Homebrew | — | haiku | sonnet |
| 10 Operations | — | haiku | sonnet |
| Tech-debt pass | sonnet | each item's Model column | sonnet |

- Fixing a failed build or test: `lf-coder` with haiku first; if it still fails, once more with sonnet; then stop and ask.
- This session only routes work, runs build/test and commits. Run it on Sonnet.

## Commit rule
- One commit per completed phase. Never commit mid-phase or with a failing build or tests.
- Message: `feat: phase <N> <name>` (`chore:` for Phase 1, `refactor:` for a tech-debt pass). Body: task IDs done, `TD-###` items added.
- Check `git status`, stage only the phase's files by path. Never stage DerivedData, `graphify-out/` or secrets.
- Commit on branch `dev` (created in Phase 1). Never push, never merge to `main`: the user does that.

## Tech-debt rule
Anything deferred becomes a `TD-###` row in `.claude/plans/techdebt.md`, never a silent TODO: unfixed MEDIUM/LOW review findings, shortcuts, skipped tests, workarounds. A `// TODO` in code must cite its TD id. Don't fix tech debt during a phase unless it blocks the phase.

## Swift
Swift 6 language mode, complete strict concurrency, zero warnings. UI is main-actor (project default); I/O and long work go in `actor`s; models are `Sendable` structs/enums. Details: plan §3 "Swift 6 concurrency model".

## Token rules
- `graphify query "<symbol>"` before opening files; read line ranges, not whole files. Run `graphify update .` after each phase commit.
- Review only the phase's changes (`git diff HEAD` plus new files).
- Agents report in 10 lines or fewer.
