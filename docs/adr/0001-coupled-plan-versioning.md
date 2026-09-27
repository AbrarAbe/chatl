# ADR 0001: Couple plan files to app release milestones

**Status:** Accepted
**Date:** 2026-09-27

## Context

Two things need version numbers: plan files under `docs/plan/` and the app itself
(`pubspec.yaml`). Options considered:

1. **Decoupled** — plans carry their own iteration numbers (`plan_v1.0`, `v1.1`, `v2.0`)
   while pubspec follows semver independently.
2. **Coupled** — a plan file names the app milestone it delivers (`plan_v0.1.0.md` ↔
   release `0.1.0`).
3. **Sequential plans only** — `plan_v1`, `plan_v2`; pubspec semver carries all
   granularity.

## Decision

**Coupled.** `docs/plan/plan_vX.Y.Z.md` is a milestone contract for release `X.Y.Z`:

- A feature belongs to version `X.Y.Z` iff its tasks live in `plan_vX.Y.Z.md` — the plan
  file is the only feature↔version registry.
- Release mechanics (version bump, tagging, publishing) are owned by the dedicated
  release skill, not the development workflow.
- The plan filename never changes once work begins; mid-flight re-scopes are recorded in
  a `## Revisions` note at the top of the file. Unstarted tasks may move to the next
  milestone's plan; a task with commits stays where it landed.
- Patch-version plans exist only when the fix is substantial enough to need tasks.

## Consequences

- **Positive:** There is exactly one place to answer "which version ships X?"; the
  Definition-of-done audit maps directly onto a release; no second numbering system to
  keep in sync.
- **Negative:** A plan re-scope can't bump the plan number (filename is stable), so
  revisions are documented in-file instead of by rename. If planning rounds ever diverge
  from releases (e.g., a plan covers two milestones), the coupling breaks and this ADR
  must be revisited.

## Alternatives rejected

- *Decoupled:* two numbering systems invite drift; "the plan says v1.1 but the app is
  0.2.0" is unanswerable without a mapping table.
- *Sequential only:* loses the feature↔version mapping entirely — every version question
  would require reading the full plan history.
