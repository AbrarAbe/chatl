# ADR 0002: nocterm as the TUI framework; pure-Dart console app

**Status:** Accepted
**Date:** 2026-09-27

## Context

The idea doc and initial spec named `flutter_tui` as the UI stack. Verification for the
Phase 0 spike found that **`flutter_tui` is not available**: no package on pub.dev, and no
maintained repository under that name. The stack choice had to be re-made with real
candidates before the spike could target a framework.

Candidates verified on pub.dev (2026-09-27):

| Package | Style | Concerns |
| --- | --- | --- |
| `nocterm` 0.9.0 | Flutter-like widgets | MIT, actively maintained, ships `nocterm_test` for headless widget tests |
| `termui` 0.9.4 | Flutter-like widgets | Pre-1.0, thinner docs |
| `utopia_tui` 2.0.0 | Custom API | Not Flutter-like |
| `timmaffett/flutter_tui` | Actual Flutter rendering to terminal | Unpublished, proof-of-concept, git-dep pin risk |

## Decision

**Adopt `nocterm`.** Consequences flow through the stack:

- chatl is a **pure Dart console package** run with `dart run bin/chatl.dart`. The Flutter
  desktop scaffold (`linux/`, `windows/` runners, `flutter_test`) is obsolete for this
  project and Task 1 (plan_v0.1.0) restructures accordingly.
- Tests: `package:test` for logic layers, `nocterm_test` for widget-level tests.
- "Streaming markdown in `flutter_tui`" becomes "streaming markdown in nocterm" — the
  spike's risk question is unchanged.

## Consequences

- **Positive:** Published, versioned dependency; Flutter-familiar widget API; real
  headless test harness (`nocterm_test`); pure-Dart keeps the binary small and the
  toolchain simple.
- **Negative:** Departs from "real Flutter" — no Flutter ecosystem widgets. The
  AGENTS.md Flutter-tooling notes (`hot_reload`, `dtd`, `flutter test`) yield to plain
  Dart equivalents (`dart analyze`, `dart test`; VM service still attaches to Dart CLI).
- **Revisit if:** nocterm blocks the Risk Module (streaming markdown) — the spike's escape
  hatch covers the renderer; if the framework itself fails, re-evaluate `termui` before
  considering unpublished options.
