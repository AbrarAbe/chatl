# ADR 0003: Incremental last-block markdown renderer (spike validated)

**Status:** Accepted
**Date:** 2026-09-27

## Context

plan_v0.1.0 Task 0 spike required answering, before any renderer work: is a custom
incremental markdown renderer viable at streaming rates in nocterm, or do we fall back to
plain-text streaming + `/render markdown` toggle? A second open question was whether
nocterm's built-in `MarkdownText` could serve as the drop-in renderer.

## Evidence

Two throwaway artifacts on branch `spike/markdown-renderer`:

**`spike/bench.dart` — render-cost benchmark.** Streams a 4 KB realistic LLM-style
markdown corpus (headings, lists, code fences, tables, blockquotes) in 4–24 char chunks,
flushed at 30 fps, parsing with `package:markdown` (gitHubFlavored):

| Strategy | p50 | p95 | max | frames over 8 ms budget |
| --- | --- | --- | --- | --- |
| Whole-document reparse per flush | 6.6 ms | 12.2 ms | 36 ms | 35 / 117 |
| Last-block-only reparse | 0.16 ms | 0.47 ms | 0.88 ms | 0 / 117 |

Cost is parse-only; layout/paint is additive, so whole-doc is strictly worse than shown.
**`MarkdownText` reparses the whole document whenever `data` changes** (its cache hits
only on unchanged input), so it cannot be used for the live streaming block — but is ideal
for frozen blocks, where its span cache makes re-layouts free.

**`spike/anchor_test.dart` — headless behavioral test** (`package:nocterm/nocterm_test.dart`,
plain `dart test`, no TTY): stream starts via keypress, content overflows the viewport,
anchor releases on PageUp and re-engages on PageDown, full corpus completes. **PASSED.**

One real defect surfaced: nocterm's `AutoScrollController` uses a 1-row near-bottom
threshold, and during an active stream content growth re-engages the anchor before a
single-line ↑ scroll can escape it. Users need multiple scroll-ups or PageUp to break
free. Mitigation (Task 5): handle user scroll intent ourselves — release the anchor on
any upward scroll, re-engage only at the true bottom — rather than relying on the
default threshold semantics.

## Decision

**Build the custom incremental renderer** (spec §Risk Module, path (a)):

- Split the incoming buffer at block boundaries (blank line outside fenced code) —
  `splitBlocks` from the spike, fence-aware, handles unclosed fences and half-streamed
  tables by construction (they stay in the open block until complete).
- Render completed blocks once as immutable widgets (`MarkdownText` with stable keys is
  acceptable); re-render only the open block per flush.
- Coalesce stream updates to ~30 fps, never per-token rebuilds.
- `ui.markdown: false` keeps plain-text rendering regardless (config, not an escape
  hatch anymore).

The `/render markdown` escape hatch is **retired** — no longer needed.

## Consequences

- **Positive:** Streaming markdown is provably affordable (≤0.9 ms worst observed flush
  vs 33 ms frame budget); scroll anchoring is provably implementable and headlessly
  testable via `nocterm_test`.
- **Negative:** Last-block-only means mid-document retroactive edits can't be
  re-rendered — acceptable: LLM streams are append-only by definition.
- Key Assumption #1 (spec) is now validated; #2 (scroll anchoring) partially validated
  (mechanism works; UX nuance handled in Task 5).
