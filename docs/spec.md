# Spec: chatl

> Living specification for chatl, promoted from `docs/ideas/chatl.md`.
> Update this file **before** changing behavior; it is the source of truth.

## Objective

**What:** A chat-only terminal agent. It does exactly one thing — conversation against an
OpenAI-compatible endpoint — with a real customization surface, and nothing else.

**Why:** Existing options fall into two camps: `tgpt` (chat, but zero configuration) and
coding-agent harnesses (configuration, but dragging in file tools, shell execution,
sandboxing, permissions, project context). Chatl occupies the gap: **declarative
configuration** buys UI *and* behavior customization without any harness machinery.

**Who:** Developers who live in the terminal and want a fast, scriptable-by-config chat
client — local or remote models — without an agent acting on their machine.

**Success looks like:** see [Success Criteria](#success-criteria).

## The Scope Rule (load-bearing invariants)

> **Read the world, never write it. And the model never invokes anything — you do.**

1. **Read-only.** Allowed: web search, URL fetch, clipboard read, terminal title read.
   Rejected: file reads/writes, command execution, side-effecting network POSTs, sending
   messages, git operations. Model output goes nowhere except the screen.
2. **User-invoked only.** The model calls zero tools. Everything it can reach is invoked by
   the user through `@` mentions, which resolve **client-side before the request is built**,
   so the syntax never reaches the model and cannot be learned or induced.

Any proposed feature that violates either clause is rejected by definition, regardless of
implementation cost. (The one sanctioned exception on the roadmap — a configured
reader/search subprocess for `@fetch`/`@search` — is documented under
[Post-v1 Roadmap](#post-v1-roadmap-forward-compat-noted-now) and ships no code in v1.)

## MVP Scope (v1)

- Declarative YAML config: `models`, `persona`, `ui`, `commands` (see [Config Surface](#config-surface))
- Persisted sessions (SQLite), `--continue` / `--session <id>` resume
- Fork-on-edit branching: editing a message makes subsequent turns an alternative branch
  (data model has `parent_id` + `active_head_id` from day one)
- Flat `/history` list of the current branch
- Mid-conversation `/model` and `/persona` switching
- Config-driven slash commands (built-in + user-defined)
- `/context` (session id, model, tokens used), `/copy`, `/rename`, `/new`
- Streaming responses (SSE) with incremental markdown rendering and partial-block handling

## Non-Goals (v1, with reasons)

| Not doing | Why |
| --- | --- |
| Local file read/edit | The defining constraint. Filesystem untouched entirely |
| Plugin runtime / hooks | Lifecycle + code execution is what turns this into a harness |
| Model-chosen destinations (tool calls) | That's the line between "look things up" and "act on the world" |
| Autonomous multi-step research | A deliberate v2 fork (with a permission model), not an evolution |
| Session graph visualization (DAG navigator) | Fork-on-edit covers ~95% of the need; v1.5 earliest |
| Multi-pane parallel sessions | Defer |
| Vision / image input | Doubles rendering work; defer |
| ChatGPT import/export | Tempting, defer |
| Voice | No |
| Backward-compat guarantees | Solo project, OSS eventually; no compat promises in v1 |

## Architecture

```
lib/src/
  config/       yaml load, validate, $ENV interpolation
  providers/    openai_compat.dart, sse.dart
  state/        sqlite store + fork ops (drift)
  session/      orchestration: session ⇄ state ⇄ provider
  commands/     slash registry (built-in + from config)
  resolve/      @-mention resolver layer (client-side, pre-request)
  ui/           nocterm app, screens, theme, widgets/
  ui/render/    incremental markdown → terminal text   ← the risk module
test/           mirrors lib/src structure (see Testing Strategy)
```

### Seams

```dart
abstract interface class Provider {
  Stream<ChatEvent> chat(StreamRequest req);
}

abstract interface class SessionStore {
  Future<List<Message>> activeBranch(Session s);      // walk parent links to head
  Future<Message> forkAt(String messageId, String content);
  Future<void> setHead(Session s, String headId);
}
```

Single provider protocol (OpenAI-compatible) covers Ollama, LM Studio, vLLM, llama.cpp,
Groq, Together, OpenRouter, DeepSeek, Mistral; multi-provider routing is client-side
config profiles. The `Provider` interface exists so orchestration never touches HTTP/SSE —
the whole app is testable against a fake stream.

### Data model

```sql
sessions(id, title, model, persona, active_head_id, created_at, updated_at)
messages(id, session_id, parent_id, role, content, model,
         prompt_tokens, completion_tokens,
         sources,            -- nullable JSON: [{url, title}] — ships empty in v1
         created_at)
```

`messages.sources` ships empty; `@fetch`/`@search` will populate it later so web search is
a feature, not a migration.

## Config Surface

`~/.config/chatl/config.yaml`, loaded and validated at startup, `$ENV` interpolation
supported:

```yaml
models:
  default: gpt-4o
  cheap: { model: gpt-4o-mini }
  local: { base_url: http://localhost:11434/v1, model: qwen2.5 }
persona:
  default: "Concise technical assistant. Terse. No preamble."
  review: "Act as a skeptical code reviewer. Flag the bad ideas."
ui:
  theme: dark
  prompt_prefix: "❯"
  markdown: true
commands:
  - name: recap
    prompt: Summarize our conversation in 5 bullets.
  - name: simplify
    prompt: Rewrite the last answer, 50% shorter, same meaning.
```

## Interaction Model

### `/` — verbs

Slash commands transform the turn and take no payload: `/recap`, `/model`, `/persona`,
`/history`, `/context`, `/copy`, `/rename`, `/new`. User-defined entries come from config
and render as prompts against the current conversation.

### `@` — references

`@` mentions attach context and expand client-side **before** the request is built; the
model never sees the syntax.

```text
user input  →  @-resolver  →  [context blocks] + message  →  Provider.chat
```

`@fetch https://example.com — is this a scam?` becomes:

```text
[CONTEXT source="https://example.com" fetched="2026-09-27"]
... extracted markdown ...
[/CONTEXT]

Q: is this a scam?
```

Rules:

- **Composable** — multiple refs per message: `@fetch A @fetch B — compare these`.
- **Uniform** — one syntax; a new resolver is config plus a small registered function.
- **Fails visibly** — dead URL / timeout → inline error block in the transcript, never a
  silent drop.
- **Unknown passes through literally** — `@someone@example.com` stays harmless. Reserved
  names are exactly the registered resolver set; they must never shadow unknown tokens.

`/recap @fetch https://x` is ill-formed — the small grammar is a feature (`/` transforms,
`@` attaches).

### OpenAI-compat streaming (SSE)

Handle explicitly: `: OPENAI` keepalive comments, `[DONE]`, partial chunks, multi-line
`data:`. Do not hand-roll line splitting.

### Fork-on-edit

Editing a message creates a new branch: the edited message gets a new id with
`parent_id` pointing at the previous message's parent, and the session's `active_head_id`
moves to the edited message. No DAG navigation UI in v1.

## The Risk Module (streaming markdown renderer)

Widget-tree markdown renderers (e.g. `flutter_markdown`) will not work — they render
into a Flutter widget tree while nocterm paints a text buffer. A custom renderer
(~200 lines) uses `package:markdown` for the AST and re-renders **only the last block**
per frame. Handle explicitly: unclosed fenced code blocks, half-streamed tables.

Known TUI-chat bugs to budget for:

- Per-token `setState` → full rebuild. Coalesce to ~30–60fps.
- **Auto-scroll anchoring** — scroll unless the user scrolled up manually.
- SSE sharp edges (above).

**timebox note:** resolved by spike → ADR 0003 (incremental renderer viable; escape
hatch retired).

## Tech Stack

| Concern | Choice |
| --- | --- |
| Language / UI | Dart `^3.14.0-211.1.beta`, console app via `nocterm` (ADR 0002) |
| State | SQLite via `drift` |
| Markdown | `package:markdown` (Dart AST) + custom terminal renderer |
| Transport | SSE over HTTP against OpenAI-compatible `/chat/completions` |
| Config | YAML, `~/.config/chatl/config.yaml` |
| Targets | Linux, Windows terminals |

Dependencies not yet in `pubspec.yaml` (add per plan): `nocterm`, `drift`,
`drift_flutter` or sqlite3 transport, `markdown`, `yaml`, `args`, `http`.
Test-only: `test`, `mockito`/`build_runner` if mocks are codegen'd, `nocterm_test`.

The project runs as a **pure Dart console package** (`dart run`); the Flutter desktop
scaffold (`linux/`, `windows/`, `flutter_test`) does not apply (ADR 0002).

## Commands

```
Run (dev):   dart run bin/chatl.dart       # or compiled: dart compile exe bin/chatl.dart
Test:        dart test
Analyze:     dart analyze                  # MCP: analyze_files
Pub:         dart pub get
```

## Versioning

Plan files are **coupled to app release milestones**:

- `docs/plan/plan_vX.Y.Z.md` is a milestone contract for release `X.Y.Z`. A feature
  belongs to version `X.Y.Z` iff its tasks live in that file; there is no other registry.
- Patch versions exist for milestone fixes; a plan file is written for one only when the
  fix is substantial enough to need tasks.
- The plan filename never changes once work begins. Mid-flight re-scopes are recorded in
  a `## Revisions` note at the top of the file; unstarted tasks may move to the next
  milestone's plan. A task with commits stays where it landed.
- Numbering while `0.x`: minor = feature milestone, patch = fixes. `1.0.0` when the
  public surface (config format, CLI flags) is worth promising stability for.

## Code Style

- `package:lints` (recommended; `analysis_options.yaml`), `dart format`, no deviations
  without reason.
- One public widget class per file; new widgets live in the sibling `widgets/` directory
  (e.g. `lib/src/ui/chat/widgets/message_list.dart`) — never new private widget classes in
  a pane/shell/sidebar. Private `State` classes stay alongside their widget.
- Streams over futures at the provider seam; orchestration code contains no HTTP/SSE
  imports.

```dart
/// Emits chat events for one streaming completion. Implementations must
/// close the stream on [ChatEventDone] or [ChatEventError].
abstract interface class Provider {
  Stream<ChatEvent> chat(StreamRequest req);
}

final class FakeProvider implements Provider {
  FakeProvider(this._script);

  final List<ChatEvent> _script;

  @override
  Stream<ChatEvent> chat(StreamRequest req) => Stream.fromIterable(_script);
}
```

## Testing Strategy

| Concern | Test type | Skill |
| --- | --- | --- |
| Config load/validate/normalize | Unit (`package:test`) | `dart-add-unit-test` |
| `@` resolvers (mock fetch/search) | Unit + mocks | `dart-generate-test-mocks` |
| SSE parser (keepalives, `[DONE]`, partial chunks) | Unit, table-driven fixtures | `dart-add-unit-test` |
| Store fork ops (`forkAt`, `activeBranch`, `setHead`) | Unit against in-memory sqlite | `dart-add-unit-test` |
| Markdown renderer (partial blocks, code fences, tables) | Unit (snapshot-style golden strings) | `dart-add-unit-test` |
| Session orchestration | Unit against `FakeProvider` stream | `dart-add-unit-test` |
| Chat screen widgets | Widget tests (`nocterm_test`) | — |
| End-to-end happy path | Integration (optional in v1) | — |

- **Baseline:** recorded before implementation (`dart test`); "done" means green relative
  to baseline, no new failures or skips.
- TDD (red→green) for all logic/data layers; tests-after acceptable for pure layout.
- No coverage % gate in v1; the layers above must each have meaningful tests.

## Boundaries

**Always do:**
- Run `impact` before editing any symbol; `detect_changes` before any commit (GitNexus gates).
- Validate and normalize config at startup; fail with actionable YAML-caret messages.
- Record the `dart test` baseline before implementing a task.
- Delineate fetched content **structurally** (`[CONTEXT ...]` blocks), never just by a
  prompt comment — prompt injection from fetched pages is the realistic attack.

**Ask first:**
- Any new dependency in `pubspec.yaml` beyond the stack table above.
- Schema changes to the SQLite data model.
- Anything that would breach the Scope Rule.

**Never do:**
- Read or write the user's filesystem (beyond chatl's own config dir and DB).
- Execute shell commands from the app (post-v1 reader/search subprocess is config-driven,
  user-authored, and gated to those resolvers only).
- Surface `/` command lists or `@` syntax to the model.
- Silently drop a failed mention, request, or stream chunk.

## Success Criteria

v1 is done when all of the following hold:

1. `dart run bin/chatl.dart` starts a chat against the configured default model with
   streamed responses; first token renders within ~2s of send on a healthy endpoint.
2. Every MVP feature in [MVP Scope](#mvp-scope-v1) works and is exercised by at least one
   test (logic layers) or manual checklist item (pure UI).
3. Streaming markdown renders without visual corruption across: code fences
   (incl. unclosed), tables (incl. half-streamed), lists, inline styles; frame coalescing
   keeps UI responsive at ~30fps.
4. `/continue` resumes the last session byte-identically; fork-on-edit creates a branch and
   `/history` shows the current-branch flat list.
5. Editing mid-conversation then resuming persists correctly across app restarts.
6. All four [Key Assumptions](#key-assumptions-to-validate) are validated or have a
   documented fallback in `docs/plan/`.
7. `dart analyze` clean; `dart test` green relative to baseline.

## Key Assumptions to Validate

- [x] `package:markdown` + custom renderer hits acceptable streaming latency in nocterm
      — **validated by spike** (ADR 0003: last-block reparse p95 0.47 ms vs whole-doc
      12.2 ms; whole-doc must not be used for the live block).
- [~] nocterm `ListView` / scroll anchoring behaves sanely under ~30fps repaint —
      **partially validated** (ADR 0003: mechanism works headlessly; anchor must release
      on any upward scroll, implemented in Task 5 of plan_v0.1.0).
- [ ] Fork-on-edit alone is enough after ~500 real messages (missing branch-switch-back UI
      won't bite immediately).
- [ ] `drift`/`sqlite3` FFI is painless on Linux and Windows.

## Decisions (resolved open questions)

Adopted from the suggestions in `docs/ideas/chatl.md`:

| Question | Decision |
| --- | --- |
| `/history` presentation | Flat current-branch list; tree only if it proves necessary |
| Persona × model composition | Independent axes — never coupled |
| Session title default | First user message, truncated (~60 chars); no LLM-generated title in v1 |
| Token counting when provider omits usage | Estimate locally and display with `~` marker; never block the UI on it |
| Citation UX (post-v1) | Trailing sources block plus a toggle; no inline footnotes in a TUI |
| `@search` with no backend configured | Fail visibly with an inline error block |
| Context block size cap | Configurable cap (default 100 KB / resolver); truncate with a visible notice, never reject silently |
| Reserved `@` names | Exactly the registered resolver set; unknown tokens pass through literally |

### Security note

Fetched content is untrusted and delineated structurally. Prompt injection from a fetched
page has a blast radius bounded to a single response — there are no tools to follow
injected instructions with.

## Post-v1 Roadmap (forward-compat noted now)

Web search (`@search`) and fetch (`@fetch`) are mandatory post-v1 and settled now so v1
needs no rework:

- No provider-native tool-calling tier — it violates the Scope Rule's clause 2.
- Both are `@` resolvers configured like other backends
  (`search.backend`, `search.results`, `search.citations: true`, `fetch.reader`).
- v1 forward-compat: `ChatEventKind` reserves room for non-text events;
  `messages.sources` ships empty (both resolvers will populate it).
- Citations are non-negotiable.
- The reader problem (HTML→text extraction) is the hard part; the external-reader-command
  pattern accepts a configured-subprocess surface, confined to those resolvers.

## Open Questions

None blocking v1. The spike outcome (assumption 1) decides between streaming markdown and
the `/render markdown` escape hatch — either path satisfies the spec.
