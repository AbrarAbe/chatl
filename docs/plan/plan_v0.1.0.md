# Implementation Plan: chatl v0.1.0 (MVP)

Delivers release **0.1.0**: the complete [MVP Scope](../spec.md#mvp-scope-v1) of
`docs/spec.md`. Source of truth for behavior is the spec; this file is the milestone
contract — a feature is in 0.1.0 iff its task is here.

## Architecture Decisions

- Single provider protocol (OpenAI-compatible SSE) behind the `Provider` seam;
  orchestration never imports HTTP/SSE code. (spec §Seams)
- SQLite via `drift` with `parent_id` + `active_head_id` in the schema from day one —
  data-model branching from the start, fork-on-edit UX only in v1. (spec §Data model)
- Custom incremental markdown renderer on `package:markdown`'s AST; **validated by the
  Phase 0 spike before any renderer task starts**. Escape hatch: plain-text streaming +
  `/render markdown` toggle.
- `@` resolver pipeline ships in v1 as **pure passthrough plumbing** (parse, reserved-name
  registry, visible-failure convention) with zero registered resolvers — so
  `@fetch`/`@search` (post-v1) are features, not rework.
- `messages.sources` and a non-text-capable `ChatEventKind` ship now (forward-compat),
  populated later.

## Branch Strategy

All tasks in this plan form one milestone bundle on **`feature/mvp-v0.1.0`**, branched from
`main` before Task 1 and merged when the final checkpoint holds. Tasks share
`pubspec.yaml` and the session layer continuously, so direct-to-`main` would violate the
bundle rule in AGENTS.md. The spike (Task 0) runs on a throwaway branch and produces no
product commits.

## Task List

### Phase 0 — Risk-kill spike

- [ ] **Task 0: Streaming-markdown spike (timeboxed, throwaway)**
  - **Goal:** Prove or kill the custom incremental renderer in `flutter_tui` **before**
    committing to it (spec §Key Assumptions #1, §Risk Module).
  - **Acceptance:** A throwaway app on branch `spike/markdown-renderer` streams synthetic
    chunks through `package:markdown` + a minimal block renderer; re-renders only the last
    block; handles unclosed code fences and half-streamed tables; scroll anchor holds
    while streaming at ~30fps.
  - **Decision output (ADR 0002):** incremental renderer **viable** → Task 13 proceeds;
    **not viable** within the 2–3 day timebox → ship plain-text streaming + `/render
    markdown` toggle (record in spec §Risk Module as the resolved path).
  - **Verify:** manual timing run; decision recorded in `docs/adr/0002-*.md`.
  - **Scope:** S · throwaway branch, no DoD, no `flutter test` requirement · no TDD.

### Checkpoint: Spike

- [ ] ADR 0002 written; Task 13's path confirmed.

---

### Phase 1 — Walking skeleton (plain-text chat end-to-end)

Record the `flutter test` baseline at the start of Task 1 (scaffold has no tests;
baseline is expected empty/green). Quote it in the plan entry.

- [ ] **Task 1: Project skeleton + dependencies**
  - **Description:** Add dependencies (`flutter_tui`, `drift` + sqlite transport,
    `markdown`, `yaml`, `args`, `http`, `path`), create the `lib/src/{config,providers,
    state,session,commands,resolve,ui,ui/render}` layout, add `test/` mirror, replace
    `lib/main.dart` with a minimal entrypoint.
  - **Acceptance:** `flutter analyze` clean; `flutter test` green (baseline + smoke test);
    `flutter run -d linux` opens the empty app shell.
  - **Verify:** commands above.
  - **Files:** `pubspec.yaml`, `lib/main.dart`, `lib/src/**` stubs, `test/smoke_test.dart`.
  - **Scope:** M · branch: `feature/mvp-v0.1.0` · smoke widget test after (UI/layout task,
    tests-after allowed) · deps added: list quoted to user at Step 6 gate (Ask-first
    boundary).
- [ ] **Task 2: Config layer**
  - **Description:** Load/validate/normalize `~/.config/chatl/config.yaml`:
    `models`/`persona`/`ui`/`commands` sections, `$ENV` interpolation, defaults when the
    file is absent, actionable error messages with YAML location on invalid input.
  - **Acceptance:** All valid/invalid fixtures from the spec §Config Surface parse
    correctly; `$ENV` expands; missing file → defaults; unknown keys warn, don't fail.
  - **Verify:** `flutter test test/config/`.
  - **Files:** `lib/src/config/*.dart`, `test/config/*.dart`.
  - **Scope:** M · direct bundle branch · TDD · `dart-add-unit-test`.
- [ ] **Task 3: Provider seam + OpenAI-compatible SSE client**
  - **Description:** `ChatEvent`/`StreamRequest` value types (non-text-capable
    `ChatEventKind`), robust SSE parser (keepalive comments, `[DONE]`, partial chunks,
    multi-line `data:` — no hand-rolled line splitting), `OpenAiCompatProvider`
    implementing `Provider`, `FakeProvider` for tests.
  - **Acceptance:** Table-driven SSE fixtures pass (incl. malformed/edge inputs);
    `FakeProvider` replays scripted streams; real client parses a captured OpenAI stream.
  - **Verify:** `flutter test test/providers/`.
  - **Files:** `lib/src/providers/{provider.dart,openai_compat.dart,sse.dart}`,
    `test/providers/*`.
  - **Scope:** M · bundle · TDD · `dart-add-unit-test` (+ `dart-generate-test-mocks` for
    the HTTP client if injection needs it).
- [ ] **Task 4: Session orchestration (in-memory)**
  - **Description:** `SessionController` wiring config → provider: build request from
    conversation + persona + model, stream `ChatEvent`s into a transcript model, expose
    switchable model/persona state. No persistence yet.
  - **Acceptance:** Unit tests against `FakeProvider` cover: send→stream→complete, error
    event surfaces in transcript, model/persona switch applies to next request only.
  - **Verify:** `flutter test test/session/`.
  - **Files:** `lib/src/session/*.dart`, `test/session/*`.
  - **Scope:** M · bundle · TDD · `dart-add-unit-test`.
- [ ] **Task 5: Chat UI shell (plain-text streaming)**
  - **Description:** `flutter_tui` app: input line with `prompt_prefix`, scrollback list
    with **auto-scroll anchoring** (scroll unless user scrolled up), streaming append with
    frame coalescing (~30–60fps, never per-token setState), theme from config. Plain text
    only — markdown is Task 13.
  - **Acceptance:** Widget tests: input submit, streamed append renders coalesced,
    anchor releases on scroll-up and re-engages at bottom; manual run against a local
    mock endpoint feels responsive.
  - **Verify:** `flutter test test/ui/`; manual smoke against `FakeProvider`-driven run.
  - **Files:** `lib/src/ui/**` (widgets extracted per one-widget-per-file rule),`test/ui/*`.
  - **Scope:** L · bundle · widget tests (`flutter-add-widget-test`); render-loop behavior
    covered by unit tests on the coalescer.

### Checkpoint: Walking skeleton

- [ ] A real (or local OpenAI-compatible) endpoint chats end-to-end in plain text.
- [ ] First token visible within ~2s of send on a healthy endpoint (spec Success #1,
      streaming part).
- [ ] `flutter analyze` clean; `flutter test` green vs baseline.

---

### Phase 2 — Persistence & branching

- [ ] **Task 6: SQLite store via drift**
  - **Description:** `sessions` + `messages` tables exactly per spec §Data model (`sources`
    as nullable JSON), generated drift code, migration runner pinned to v1 schema.
  - **Acceptance:** CRUD round-trips against in-memory sqlite; schema version recorded;
    `sources` accepts null and JSON list.
  - **Verify:** `flutter test test/state/`.
  - **Files:** `lib/src/state/**`, `test/state/*`, `build.yaml` if codegen config needed.
  - **Scope:** M · bundle · TDD · `dart-add-unit-test` (in-memory sqlite).
- [ ] **Task 7: `SessionStore` fork ops**
  - **Description:** `activeBranch` (walk `parent_id` to `active_head_id`), `forkAt`
    (new id, reparent), `setHead` — the ~10-line core of fork-on-edit.
  - **Acceptance:** Unit tests: linear history, single fork, fork-of-fork, head switch,
    branch isolation (editing A doesn't touch B).
  - **Verify:** `flutter test test/state/`.
  - **Files:** `lib/src/state/session_store.dart`, tests.
  - **Scope:** M · bundle · TDD · `dart-add-unit-test`.
- [ ] **Task 8: Persisted sessions + resume CLI**
  - **Description:** Orchestration writes through the store; `args`-based CLI:
    `chatl`, `chatl --continue` (latest session), `chatl --session <id>`; session title =
    first user message truncated to ~60 chars.
  - **Acceptance:** Restart → `--continue` restores the transcript byte-identically
    (spec Success #4); `--session <id>` opens that session's active branch; title follows
    the truncated-first-message rule.
  - **Verify:** `flutter test test/session/ test/state/`; manual restart check.
  - **Files:** `lib/main.dart`, `lib/src/session/*`, `lib/src/state/*`, tests.
  - **Scope:** M · bundle · TDD · `dart-add-unit-test`.
- [ ] **Task 9: Fork-on-edit UX + `/history`**
  - **Description:** Edit a prior message → `forkAt` + `setHead` automatically; `/history`
    shows a flat list of the current branch (spec Decisions: flat, not tree).
  - **Acceptance:** Editing mid-conversation creates an alternative branch and the old
    branch is untouched; `/history` lists current-branch messages in order; state
    persists across restart (spec Success #5).
  - **Verify:** `flutter test` (store + session level); manual UI check.
  - **Files:** `lib/src/ui/**`, `lib/src/session/*`, tests.
  - **Scope:** M · bundle · TDD for logic; tests-after for pure layout.

### Checkpoint: Persistence & branching

- [ ] Spec Success Criteria #4 and #5 demonstrably hold (restart, resume, fork, history).
- [ ] `flutter analyze` clean; tests green vs baseline.

---

### Phase 3 — Commands, resolvers, renderer, polish

- [ ] **Task 10: Slash-command registry + informational/built-in commands**
  - **Description:** Registry (built-in + config-defined from `commands:`), `/new`,
    `/rename`, `/copy`, `/context` (session id, model, tokens — estimated with `~` when
    the provider omits usage), `/history` hook; config-defined commands render as prompts.
  - **Acceptance:** Each built-in behaves per spec §Interaction Model; config-defined
    `/recap`-style entries submit their prompt against the conversation; unknown `/x`
    errors visibly.
  - **Verify:** `flutter test test/commands/`.
  - **Files:** `lib/src/commands/**`, tests.
  - **Scope:** M · bundle · TDD · `dart-add-unit-test`.
- [ ] **Task 11: `/model` and `/persona` mid-conversation switching**
  - **Description:** List/select from config profiles; strictly independent axes (spec
    Decisions); applies from next turn; reflected in `/context`.
  - **Acceptance:** Switching either axis affects only subsequent requests; invalid names
    error visibly; session row updates.
  - **Verify:** `flutter test test/commands/ test/session/`.
  - **Files:** `lib/src/commands/*`, `lib/src/session/*`, tests.
  - **Scope:** S · bundle · TDD · `dart-add-unit-test`.
- [ ] **Task 12: `@` resolver pipeline (passthrough)**
  - **Description:** Tokenize mentions; reserved-name registry (empty in v1); unknown `@x`
    passes through literally; message → `[context blocks] + message` request shape; the
    visible-failure convention documented for future resolvers. The model never sees `@`
    syntax.
  - **Acceptance:** Unit tests: pass-through of unknown tokens (incl. email addresses),
    no registered resolver shadows unknown names, resolver output ordering deterministic.
  - **Verify:** `flutter test test/resolve/`.
  - **Files:** `lib/src/resolve/**`, tests.
  - **Scope:** S · bundle · TDD · `dart-add-unit-test`.
- [ ] **Task 13: Markdown rendering**
  - **Description:** Path from ADR 0002: (a) incremental renderer — AST via
    `package:markdown`, re-render only the last block, handle unclosed fences and
    half-streamed tables; or (b) escape hatch — plain-text streaming + `/render markdown`
    toggle rendering on completion. `ui.markdown: false` disables either way.
  - **Acceptance:** Golden-string tests over the corpus: headings, lists, emphasis, code
    fences (closed + unclosed), tables (complete + half-streamed); no visual corruption
    in manual stream run (spec Success #3).
  - **Verify:** `flutter test test/ui/render/`; manual stream check.
  - **Files:** `lib/src/ui/render/**`, tests.
  - **Scope:** L · bundle · TDD on renderer (golden strings), widget tests for the toggle
    path.
- [ ] **Task 14: UI config polish**
  - **Description:** Theme (`ui.theme`), `prompt_prefix`, `ui.markdown` toggle wired
    through to the shell; token display polish; final UI consistency pass.
  - **Acceptance:** Each `ui.*` config key has visible effect; absence falls back to
    defaults.
  - **Verify:** `flutter test test/ui/`; manual visual pass.
  - **Files:** `lib/src/ui/**`, tests.
  - **Scope:** S · bundle · tests-after for pure layout.

### Checkpoint: Complete (milestone close-out)

- [ ] Every [Success Criterion](../spec.md#success-criteria) in `docs/spec.md` holds, with
      evidence quoted.
- [ ] All four Key Assumptions each validated or have a documented fallback here.
- [ ] `flutter analyze` clean; `flutter test` green relative to the Task 1 baseline.
- [ ] `docs/spec.md` matches shipped behavior; ADRs written for Task 0/13's rendering
      decision and any other non-obvious call.
- [ ] Every checkbox above ticked; bundle merged `feature/mvp-v0.1.0` → `main`.

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Incremental markdown renderer too slow/janky in `flutter_tui` | High | Task 0 spike, 2–3 day timebox, `/render markdown` escape hatch (ADR 0002) |
| `flutter_tui` maturity (scroll anchoring, repaint behavior) on Linux/Windows | High | Assumption validated in Tasks 0/5; fallback: evaluate alternate TUI path early, before Phase 2 |
| `drift`/`sqlite3` FFI pain on Windows | Med | Task 6 early in Phase 2; fall back to `sqlite3` package directly |
| SSE edge cases corrupt streams | Med | Task 3 table-driven fixtures incl. captured real streams; no hand-rolled splitting |
| Per-token rebuilds tank frame rate | Med | Coalescer unit-tested in Task 5; manual responsiveness gate at Checkpoint 1 |
| Per-task file overlap (pubspec, session layer) if tasks run in parallel | Low | Strictly sequential within a phase; only docs/tests parallelized |

## Parallelization

- Must run sequentially: Tasks 0→(13 path), 1→2→3→4→5, 6→7→8→9, 10→11.
- Parallelizable by subagent (after the shared contracts land): Task 10 vs Task 12, and
  Task 13 vs Task 14. Dis-joint write scopes required; parent verifies per AGENTS.md.

## Open Questions

- Task 13's path (incremental vs escape hatch) — resolved by Task 0/ADR 0002 before
  Phase 3 begins.
- Exact frame-coalescing interval (30 vs 60fps) — tune during Task 5, record in ADR if
  non-obvious.
