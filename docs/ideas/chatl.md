# Chatl

> Chat-only terminal agent. No file reads, no file edits. Only shaping the conversation.

## Problem Statement

**How might we** build a terminal chat client that does *only* chat — no file reads, no file
edits, no shell — but gives a real customization surface, sitting in the gap between tgpt (which
has none) and coding-agent harnesses (which have everything else)?

The precise problem is not "tgpt needs more features." It is that tgpt has **no config surface at
all**, so the only way to gain flexibility is to jump to a coding agent — which drags in file
tools, shell execution, sandboxing, permissions, and project context. None of which we want.

## Recommended Direction

**Declarative config, not a plugin runtime.** The gap between tgpt and the harnesses is exactly
*declarative configuration*: it buys UI *and* behavior customization with none of the harness
machinery. Slash commands become YAML entries that render as prompts — no lifecycle hooks, no
arbitrary code execution, nothing that can touch the filesystem. This single line is what keeps
the project out of the agent-harness trap.

**Fork-on-edit branching, not a DAG.** Branching lives in the *data model* from day one
(`parent_id` + `active_head_id`, ~10 lines in SQLite) but only *fork-on-edit* ships in v1. Editing
a message makes subsequent turns an alternative branch automatically. The git-graph navigator UI
is cut from v1 — arbitrary DAG navigation is the rabbit hole that turns a chat client into a
knowledge-graph app.

**Single provider, kept behind a seam.** "OpenAI-compatible only" is less closed than it feels:
it already covers Ollama, LM Studio, vLLM, llama.cpp, Groq, Together, OpenRouter, DeepSeek, and
Mistral. Multi-provider routing is therefore free via client-side config profiles. A `Provider`
interface is still kept — not for extensibility, but so the orchestration layer never touches
HTTP or SSE, which makes the whole app testable against a fake stream.

## Architecture

```
lib/src/
  config/       yaml load, validate, $ENV interpolation
  providers/    openai_compat.dart, sse.dart
  state/        sqlite store + fork ops
  session/      orchestration: session ⇄ state ⇄ provider
  commands/     slash registry (built-in + from config)
  resolve/      @-mention resolver layer (client-side, pre-request)
  ui/           flutter_tui app, screens, theme, widgets/
  ui/render/    INCREMENTAL markdown → terminal text   ← the risk module
```

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

```sql
sessions(id, title, model, persona, active_head_id, created_at, updated_at)
messages(id, session_id, parent_id, role, content, model,
         prompt_tokens, completion_tokens,
         sources,            -- nullable JSON: [{url, title}] — populated by @fetch / @search
         created_at)
```

`sources` ships empty in v1. It exists so web search later is a feature, not a migration. Both
`@fetch` and `@search` populate it.

### Config surface

```yaml
# ~/.config/chatl/config.yaml
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

### The `@` resolver layer

`@` mentions expand client-side, **before** the request is built. The model never sees the
syntax.

```text
user input  →  @-resolver  →  [context blocks] + message  →  Provider.chat
```

`@fetch https://example.com — is this a scam?` becomes a context block plus the question:

```text
[CONTEXT source="https://example.com" fetched="2026-09-27"]
... extracted markdown ...
[/CONTEXT]

Q: is this a scam?
```

- **Composable** — multiple refs per message: `@fetch A @fetch B — compare these`.
- **Uniform** — `@fetch`, `@search`, `@clipboard`, `@time`... one syntax; a new resolver is
  config plus a small registered function.
- **Invisible to the model** — resolved before the request is built, so the model cannot learn
  or misuse the syntax. This is what makes "user-invoked only" self-enforcing.
- **Fails visibly** — a dead URL or timeout becomes an inline error block in the transcript,
  never a silent drop.

Unknown `@x` passes through literally, so email addresses stay harmless. Reserved names must
never shadow unknown tokens.

**Why two syntaxes.** `/` is a verb — it transforms the turn and takes no payload (`/recap`).
`@` is a reference — it attaches context to the message (`@fetch URL`). The grammar stays small:
`/recap @fetch https://x` is ill-formed, and that's a feature.

### Stack

- **Language:** Dart/Flutter (`flutter_tui`)
- **State:** SQLite via `drift`
- **Markdown:** `package:markdown` (Dart AST) + custom ~200-line terminal renderer

## MVP Scope

- Config file: `models`, `persona`, `ui`, `commands`
- `--continue` / `--session <id>` resume; persisted sessions
- Fork-on-edit branching (data model + UX); flat `/history` list of current branch
- `/model`, `/persona` — switch mid-conversation
- Config-driven slash commands, themes, system prompts
- `/context` — session id, model, tokens used
- `/copy`, `/rename`, `/new`
- Incremental markdown rendering with partial-block handling

## Not Doing (and Why)

- **Local file read/edit** — the defining constraint. The filesystem is untouched entirely;
  `@fetch` reads the *network*, not your disk.
- **Plugin runtime** — a lifecycle/code-execution surface is exactly what turns this into a
  harness. Declarative YAML is the ceiling for v1.
- **Model-chosen destinations** — you paste the URL and type the query; the model never picks
  one. That's the line between "look things up" and "act on the world."
- **Autonomous multi-step research** — "research X and report back" is out. You drive every
  step. See the Scope Rule.
- **Session graph visualization** — DAG navigator UI. Fork-on-edit covers 95% of the use case
  without any of the cost. v1.5 at the earliest.
- **Multi-pane parallel sessions** — defer.
- **Vision / image input** — doubles rendering work. Defer.
- **ChatGPT import/export** — tempting, defer.
- **Voice** — no.
- **Backward-compat guarantees** — solo project, OSS *eventually*. No compat promises in v1.

## The Scope Rule

> **Read the world, never write it. And the model never invokes anything — you do.**

Two clauses. Both are load-bearing.

**1. Read-only.** Allowed: web search, URL fetch, reading the clipboard, reading the terminal
title. Rejected: file edits, command execution, network POSTs with side effects, sending
messages, git operations. The model's output goes nowhere except your screen.

**2. User-invoked only.** The model calls zero tools. Everything it can reach, *you* invoke
through `@` mentions. There is no "research this for me" — no autonomous multi-step browsing.
That's a deliberate v2 fork (with a permission model), not an evolution.

The danger that makes agent harnesses feel heavy is arbitrary *writes* plus *model-chosen
destinations*. Removing both is what keeps this a chat client.

**Why `@` enforces clause 2 for free.** Mentions resolve client-side before the request is
built, so the syntax never reaches the model. It cannot learn that fetching exists, and
therefore cannot be induced into using it. A `/` command list, by contrast, is often surfaced
to the model in the system prompt — which is how "commands" quietly become "tools."

**Security note.** Fetched content is untrusted; delineate it structurally, not just with a
prompt comment. Prompt injection from a fetched page is the realistic attack here, and it is
not hypothetical. Its blast radius is bounded to a single response — there are no tools to
follow injected instructions with.

## Roadmap (Post-v1)

### Web search and fetch — user-invoked, one implementation

Mandatory, and it will be built. Settled here now so v1 needs no rework.

**No provider-native tier.** OpenAI-style `web_search` works by the *model*
emitting a tool call that the backend executes — which is model-invoked, so clause 2 excludes
it. The cheapest path is out by principle. That's the honest cost of the user-invoked-only
stance: you trade provider magic for one consistent model.

**The implementation** is two `@` resolvers, configured like every other backend:

```yaml
search:
  backend: ddgr          # or: brave, tavily, openrouter, or a shell command
  results: 5
  citations: true
fetch:
  reader: w3m -dump      # or: lynx -dump, html2text — HTML → text extraction
```

`@search "react suspense" — when should I use it?` resolves to ranked snippets plus the
question. `@fetch <url>` resolves to extracted page text. You always type the query and paste
the URL; the model never chooses a destination or iterates on its own.

**The reader problem is the hard part.** Dart has no good HTML→text extractor, and raw HTML in
context is huge, noisy, and instruction-bearing. The external-reader-command pattern above
matches the search design (same config shape, same failure modes), at the cost of accepting a
configured-subprocess surface — the one thing the "no plugin runtime" stance has been
avoiding. Small and single-purpose, but the tension is real.

**Forward-compat already in v1** (two small decisions, no implementation):

- `ChatEventKind` reserves room for non-text events — don't narrow it to text-only.
- `messages.sources` ships empty in v1 — cheap today, painful migration later. Both resolvers
  populate it, so it pays off twice.

**Citations are non-negotiable.** Search without visible sources is unusable; users stop
trusting answers they can't verify.

## Key Assumptions to Validate

- [ ] `package:markdown` + a custom terminal renderer hits acceptable streaming latency in
      `flutter_tui`. **Validate in day 1 with a throwaway spike, not after.**
- [ ] `flutter_tui` `ListView` / scroll anchoring behaves sanely under ~30fps repaint.
- [ ] Fork-on-edit alone is enough after ~500 real messages — you won't notice missing branch
      UI until you try to switch *back* to an old branch.
- [ ] `drift`/`sqlite3` FFI is painless on the target platforms.

## The Risk Module

`flutter_markdown` **will not work here** — it renders into Flutter's HTML widget tree, while
`flutter_tui` paints into a text buffer. There is no drop-in streaming renderer; it must be
written, using `package:markdown` for the AST and re-rendering **only the last block** per frame.
Handle explicitly: unclosed fenced code blocks, half-streamed tables.

Known TUI-chat bugs to budget for:

- Per-token `setState` → full rebuild. Coalesce to ~30–60fps.
- **Auto-scroll anchoring** — scroll unless the user scrolled up manually. The #1 complaint
  about every TUI chat app.
- SSE sharp edges: `: OPENAI` keepalive comments, `[DONE]`, partial chunks, multi-line `data:`.
  Don't hand-roll line splitting.

**Escape hatch:** timebox streaming markdown to 2–3 days. If unacceptable, ship plain-text
streaming with a `/render markdown` toggle that renders-on-complete.

## Open Questions

- How should `/history` present branching — a flat current-branch list, or an indented tree with
  depth shown? (Suggests: flat first, tree only if it proves necessary.)
- Should `persona` compose with `model` profiles, or be strictly independent axes? (Suggests:
  independent — a "reasoning" model shouldn't imply a "reviewer" persona.)
- What is the session title default — first user message truncated, or an LLM-generated one?
  (LLM-generated is a nice touch but costs a turn; suggest truncated-first for v1.)
- Token counting when the provider omits usage fields — estimate, or hide?
- Citation UX for web search — trailing sources block, inline footnotes, or a toggleable
  panel? (A TUI argues for trailing-block-plus-toggle; footnotes fight the scroll model.)
- When `@search` has no configured backend, fail the mention visibly or drop it silently?
  (Suggests: fail — a silent drop makes the model answer ungrounded and the user never knows.)
- Context block size cap — a 2MB page will blow the window. Truncate with a notice, or reject
  above a threshold?
- Which names are reserved for `@` resolvers? Anything unknown must pass through literally.

## Next

1. Streaming-renderer spike (day 1, timeboxed 2–3 days) → confirms or kills the risky module
2. `docs/spec.md` — living spec, promoted from this doc
3. `docs/plan/plan_v0.1.0.md` — ordered tasks from the MVP scope above
