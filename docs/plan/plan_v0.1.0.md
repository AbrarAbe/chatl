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
  `/render markdown` toggle. (Framework: nocterm, ADR 0002.)
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

- [x] **Task 0: Streaming-markdown spike** — DONE 2026-09-27, throwaway branch
      `spike/markdown-renderer` (not merged). Decision + evidence: ADR 0003 —
      incremental last-block renderer approved (bench p95 0.47 ms vs whole-doc 12.2 ms),
      `/render markdown` escape hatch retired. Note: interactive eyeball (manual TUI run)
      not performed; automated proofs only.
  - **Goal:** Prove or kill the custom incremental renderer in nocterm **before**
    committing to it (spec §Key Assumptions #1, §Risk Module).
  - **Acceptance:** A throwaway app on branch `spike/markdown-renderer` streams synthetic
    chunks through `package:markdown` + a minimal block renderer; re-renders only the last
    block; handles unclosed code fences and half-streamed tables; scroll anchor holds
    while streaming at ~30fps.
  - **Decision output (ADR 0003):** incremental renderer **viable** → Task 13 proceeds;
    **not viable** within the 2–3 day timebox → ship plain-text streaming + `/render
    markdown` toggle (record in spec §Risk Module as the resolved path).
  - **Verify:** manual timing run; decision recorded in `docs/adr/0003-*.md`.
  - **Scope:** S · throwaway branch, no DoD, no `flutter test` requirement · no TDD.

### Checkpoint: Spike

- [x] ADR 0003 written; Task 13's path confirmed (incremental last-block renderer).

---

### Phase 1 — Walking skeleton (plain-text chat end-to-end)

Record the `dart test` baseline at the start of Task 1 (scaffold has no tests;
baseline is expected empty/green). Quote it in the plan entry.

- [x] **Task 1: Project skeleton + dependencies** — DONE on `feature/mvp-v0.1.0`.
      Baseline recorded 2026-09-27: pre-code `dart test` → "Could not find package
      `test`" (no dev dep, no tests); post-task → `00:00 +1: All tests passed!`
      (smoke). `dart analyze`: No issues found. Declared gap: `dart run bin/chatl.dart`
      pty-visual not verified (headless env; exits 0; render verified via nocterm_test
      smoke). Desktop runners (`linux/`, `windows/`) removed; `flutter_lints` → `lints`.
  - **Description:** Restructure into a pure-Dart console package (ADR 0002): remove the
    unused `linux/`/`windows/` desktop runners, move the entrypoint to `bin/chatl.dart`,
    swap `flutter_test` for `package:test` (+ `nocterm_test` when widgets land). Add
    dependencies (`nocterm`, `drift` + sqlite transport, `markdown`, `yaml`, `args`,
    `http`, `path`), create the `lib/src/{config,providers,state,session,commands,
    resolve,ui,ui/render}` layout with `test/` mirror.
  - **Acceptance:** `dart analyze` clean; `dart test` green (baseline + smoke test);
    `dart run bin/chatl.dart` opens the empty app shell.
  - **Verify:** commands above.
  - **Files:** `pubspec.yaml`, `bin/chatl.dart`, `lib/src/**` stubs, `test/smoke_test.dart`,
    deletion of `linux/` `windows/` `lib/main.dart`.
  - **Scope:** M · branch: `feature/mvp-v0.1.0` · smoke test after (scaffolding task,
    tests-after allowed) · deps added: list quoted to user at Step 6 gate (Ask-first
    boundary).
- [x] **Task 2: Config layer** — DONE on `feature/mvp-v0.1.0`. TDD: 9 tests
      (defaults, full parse, `$VAR`/`${VAR}` interpolation + unset-var warning,
      invalid-YAML line info, unknown-key warning, per-key type/location errors).
      Spec note: `api_key` (env-interpolated) added to model profiles.
  - **Description:** Load/validate/normalize `~/.config/chatl/config.yaml`:
    `models`/`persona`/`ui`/`commands` sections, `$ENV` interpolation, defaults when the
    file is absent, actionable error messages with YAML location on invalid input.
  - **Acceptance:** All valid/invalid fixtures from the spec §Config Surface parse
    correctly; `$ENV` expands; missing file → defaults; unknown keys warn, don't fail.
  - **Verify:** `dart test test/config/`.
  - **Files:** `lib/src/config/*.dart`, `test/config/*.dart`.
  - **Scope:** M · direct bundle branch · TDD · `dart-add-unit-test`.
- [x] **Task 3: Provider seam + OpenAI-compatible SSE client** — DONE on
      `feature/mvp-v0.1.0`. TDD, 12 tests: SSE parser (split chunks, multi-line data,
      keepalives, `[DONE]`, CRLF, trailing event), provider mapping/error/usage,
      `FakeProvider` replay.
  - **Description:** `ChatEvent`/`StreamRequest` value types (non-text-capable
    `ChatEventKind`), robust SSE parser (keepalive comments, `[DONE]`, partial chunks,
    multi-line `data:` — no hand-rolled line splitting), `OpenAiCompatProvider`
    implementing `Provider`, `FakeProvider` for tests.
  - **Acceptance:** Table-driven SSE fixtures pass (incl. malformed/edge inputs);
    `FakeProvider` replays scripted streams; real client parses a captured OpenAI stream.
  - **Verify:** `dart test test/providers/`.
  - **Files:** `lib/src/providers/{provider.dart,openai_compat.dart,sse.dart}`,
    `test/providers/*`.
  - **Scope:** M · bundle · TDD · `dart-add-unit-test` (+ `dart-generate-test-mocks` for
    the HTTP client if injection needs it).
- [x] **Task 4: Session orchestration (in-memory)** — DONE on
      `feature/mvp-v0.1.0`. TDD, 7 tests vs `RecordingProvider`: stream→transcript,
      request shape (persona system + history + model), error turns visible,
      model/persona switch next-request-only, unknown names throw, one stream at a time,
      update notifications.
  - **Description:** `SessionController` wiring config → provider: build request from
    conversation + persona + model, stream `ChatEvent`s into a transcript model, expose
    switchable model/persona state. No persistence yet.
  - **Acceptance:** Unit tests against `FakeProvider` cover: send→stream→complete, error
    event surfaces in transcript, model/persona switch applies to next request only.
  - **Verify:** `dart test test/session/`.
  - **Files:** `lib/src/session/*.dart`, `test/session/*`.
  - **Scope:** M · bundle · TDD · `dart-add-unit-test`.
- [x] **Task 5: Chat UI shell (plain-text streaming)** — DONE on
      `feature/mvp-v0.1.0`. nocterm_test: input submit → streamed render; single
      arrow-up releases anchor, PageDown re-engages (required `ChatScrollController`
      override: nocterm's 1-row threshold keeps re-engaging mid-stream — spike finding
      confirmed real). `FrameCoalescer` unit-tested (50 rapid events → 1 flush).
      Declared gap: live-endpoint smoke not run (no credentials in this env); covered
      by FakeProvider tests + manual run on user machine.
  - **Description:** nocterm app: input line with `prompt_prefix`, scrollback list
    with **auto-scroll anchoring** (scroll unless user scrolled up), streaming append with
    frame coalescing (~30–60fps, never per-token setState), theme from config. Plain text
    only — markdown is Task 13.
  - **Acceptance:** Widget tests (`nocterm_test`): input submit, streamed append renders
    coalesced, anchor releases on scroll-up and re-engages at bottom; manual run against a
    local mock endpoint feels responsive.
  - **Verify:** `dart test test/ui/`; manual smoke against `FakeProvider`-driven run.
  - **Files:** `lib/src/ui/**` (widgets extracted per one-widget-per-file rule),
    `test/ui/*`.
  - **Scope:** L · bundle · widget tests (`nocterm_test`); render-loop behavior
    covered by unit tests on the coalescer. *(done)*

### Checkpoint: Walking skeleton

- [~] A real (or local OpenAI-compatible) endpoint chats end-to-end in plain text. —
      FakeProvider + headless chat-screen tests pass; live-endpoint run deferred to
      user's machine (no credentials here).
- [ ] First token visible within ~2s of send on a healthy endpoint (spec Success #1,
      streaming part). — deferred, same reason.
- [x] `dart analyze` clean; `dart test` green vs baseline (33 tests).

---

### Phase 2 — Persistence & branching

- [x] **Task 6: SQLite store via drift** — DONE on `feature/mvp-v0.1.0`. TDD,
      4 tests (CRUD, null/JSON sources, fork sibling chains, schema v1). Note:
      added dev-dep `drift_dev` (required codegen companion to `drift`) —
      Ask-first boundary cited here.
  - **Description:** `sessions` + `messages` tables exactly per spec §Data model (`sources`
    as nullable JSON), generated drift code, migration runner pinned to v1 schema.
  - **Acceptance:** CRUD round-trips against in-memory sqlite; schema version recorded;
    `sources` accepts null and JSON list.
  - **Verify:** `dart test test/state/`.
  - **Files:** `lib/src/state/**`, `test/state/*`, `build.yaml` if codegen config needed.
  - **Scope:** M · bundle · TDD · `dart-add-unit-test` (in-memory sqlite).
- [x] **Task 7: `SessionStore` fork ops** — DONE on `feature/mvp-v0.1.0`. TDD,
      6 tests: empty branch, linear walk, fork+setHead, branch isolation,
      fork-of-fork, unknown-message error. Design note: `appendMessage`
      defaults its parent to the current head and advances it
      (`advanceHead: false` for forks); forks never move the head themselves.
  - **Description:** `activeBranch` (walk `parent_id` to `active_head_id`), `forkAt`
    (new id, reparent), `setHead` — the ~10-line core of fork-on-edit.
  - **Acceptance:** Unit tests: linear history, single fork, fork-of-fork, head switch,
    branch isolation (editing A doesn't touch B).
  - **Verify:** `dart test test/state/`.
  - **Files:** `lib/src/state/session_store.dart`, tests.
  - **Scope:** M · bundle · TDD · `dart-add-unit-test`.
- [x] **Task 8: Persisted sessions + resume CLI** — DONE on `feature/mvp-v0.1.0`.
      TDD: 3 persistence tests (restart→identical transcript, title = first user
      message truncated to 60, `latestSession`) + 6 CLI arg tests. `bin/chatl.dart`
      wires `--continue` / `--session <id>`; new sessions start on `default` or the
      first configured profile; config warnings print to stderr. Note: moved drift
      DateTimes to text storage (`build.yaml`) — second-resolution integers broke
      `updatedAt` ordering for `--continue`.
  - **Description:** Orchestration writes through the store; `args`-based CLI:
    `chatl`, `chatl --continue` (latest session), `chatl --session <id>`; session title =
    first user message truncated to ~60 chars.
  - **Acceptance:** Restart → `--continue` restores the transcript byte-identically
    (spec Success #4); `--session <id>` opens that session's active branch; title follows
    the truncated-first-message rule.
  - **Verify:** `dart test test/session/ test/state/`; manual restart check.
  - **Files:** `bin/chatl.dart`, `lib/src/cli/*`, `lib/src/session/*`, `lib/src/state/*`,
    tests.
  - **Scope:** M · bundle · TDD · `dart-add-unit-test`.
- [ ] **Task 9: Fork-on-edit UX + `/history`**
  - **Description:** Edit a prior message → `forkAt` + `setHead` automatically; `/history`
    shows a flat list of the current branch (spec Decisions: flat, not tree).
  - **Acceptance:** Editing mid-conversation creates an alternative branch and the old
    branch is untouched; `/history` lists current-branch messages in order; state
    persists across restart (spec Success #5).
  - **Verify:** `dart test` (store + session level); manual UI check.
  - **Files:** `lib/src/ui/**`, `lib/src/session/*`, tests.
  - **Scope:** M · bundle · TDD for logic; tests-after for pure layout.

### Checkpoint: Persistence & branching

- [ ] Spec Success Criteria #4 and #5 demonstrably hold (restart, resume, fork, history).
- [ ] `dart analyze` clean; tests green vs baseline.

---

### Phase 3 — Commands, resolvers, renderer, polish

- [ ] **Task 10: Slash-command registry + informational/built-in commands**
  - **Description:** Registry (built-in + config-defined from `commands:`), `/new`,
    `/rename`, `/copy`, `/context` (session id, model, tokens — estimated with `~` when
    the provider omits usage), `/history` hook; config-defined commands render as prompts.
  - **Acceptance:** Each built-in behaves per spec §Interaction Model; config-defined
    `/recap`-style entries submit their prompt against the conversation; unknown `/x`
    errors visibly.
  - **Verify:** `dart test test/commands/`.
  - **Files:** `lib/src/commands/**`, tests.
  - **Scope:** M · bundle · TDD · `dart-add-unit-test`.
- [ ] **Task 11: `/model` and `/persona` mid-conversation switching**
  - **Description:** List/select from config profiles; strictly independent axes (spec
    Decisions); applies from next turn; reflected in `/context`.
  - **Acceptance:** Switching either axis affects only subsequent requests; invalid names
    error visibly; session row updates.
  - **Verify:** `dart test test/commands/ test/session/`.
  - **Files:** `lib/src/commands/*`, `lib/src/session/*`, tests.
  - **Scope:** S · bundle · TDD · `dart-add-unit-test`.
- [ ] **Task 12: `@` resolver pipeline (passthrough)**
  - **Description:** Tokenize mentions; reserved-name registry (empty in v1); unknown `@x`
    passes through literally; message → `[context blocks] + message` request shape; the
    visible-failure convention documented for future resolvers. The model never sees `@`
    syntax.
  - **Acceptance:** Unit tests: pass-through of unknown tokens (incl. email addresses),
    no registered resolver shadows unknown names, resolver output ordering deterministic.
  - **Verify:** `dart test test/resolve/`.
  - **Files:** `lib/src/resolve/**`, tests.
  - **Scope:** S · bundle · TDD · `dart-add-unit-test`.
- [ ] **Task 13: Markdown rendering**
  - **Description:** Incremental renderer per ADR 0003 — AST via
    `package:markdown`, re-render only the last block (block boundaries: blank line
    outside fenced code; unclosed fences and half-streamed tables stay in the open
    block), frozen blocks immutable (keyed `MarkdownText`), ~30fps coalescing.
    `ui.markdown: false` forces plain text.
  - **Acceptance:** Golden-string tests over the corpus: headings, lists, emphasis, code
    fences (closed + unclosed), tables (complete + half-streamed); no visual corruption
    in manual stream run (spec Success #3).
  - **Verify:** `dart test test/ui/render/`; manual stream check.
  - **Files:** `lib/src/ui/render/**`, tests.
  - **Scope:** L · bundle · TDD on renderer (golden strings), widget tests for the toggle
    path.
- [ ] **Task 14: UI config polish**
  - **Description:** Theme (`ui.theme`), `prompt_prefix`, `ui.markdown` toggle wired
    through to the shell; token display polish; final UI consistency pass.
  - **Acceptance:** Each `ui.*` config key has visible effect; absence falls back to
    defaults.
  - **Verify:** `dart test test/ui/`; manual visual pass.
  - **Files:** `lib/src/ui/**`, tests.
  - **Scope:** S · bundle · tests-after for pure layout.

### Checkpoint: Complete (milestone close-out)

- [ ] Every [Success Criterion](../spec.md#success-criteria) in `docs/spec.md` holds, with
      evidence quoted.
- [ ] All four Key Assumptions each validated or have a documented fallback here.
- [ ] `dart analyze` clean; `dart test` green relative to the Task 1 baseline.
- [ ] `docs/spec.md` matches shipped behavior; ADRs written for Task 0/13's rendering
      decision and any other non-obvious call.
- [ ] Every checkbox above ticked; bundle merged `feature/mvp-v0.1.0` → `main`.

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Incremental markdown renderer too slow/janky in nocterm | High | Task 0 spike, 2–3 day timebox, `/render markdown` escape hatch (ADR 0003) |
| nocterm maturity (scroll anchoring, repaint behavior) | High | Assumption validated in Tasks 0/5; fallback: evaluate `termui` early, before Phase 2 (ADR 0002) |
| `drift`/`sqlite3` FFI pain on Windows | Med | Task 6 early in Phase 2; fall back to `sqlite3` package directly |
| SSE edge cases corrupt streams | Med | Task 3 table-driven fixtures incl. captured real streams; no hand-rolled splitting |
| Per-token rebuilds tank frame rate | Med | Coalescer unit-tested in Task 5; manual responsiveness gate at Checkpoint 1 |
| Per-task file overlap (pubspec, session layer) if tasks run in parallel | Low | Strictly sequential within a phase; only docs/tests parallelized |

## Parallelization

- Must run sequentially: Tasks 0→(13 path), 1→2→3→4→5, 6→7→8→9, 10→11.
- Parallelizable by subagent (after the shared contracts land): Task 10 vs Task 12, and
  Task 13 vs Task 14. Dis-joint write scopes required; parent verifies per AGENTS.md.

## Open Questions

- Task 13's path — **resolved (ADR 0003)**: incremental last-block renderer.
- Exact frame-coalescing interval (30 vs 60fps) — tune during Task 5, record in ADR if
  non-obvious.
