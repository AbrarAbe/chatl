# chatl

Chat-only terminal agent. No file reads, no file edits — only conversation.

## Install

### Linux
```sh
curl -fsSL https://raw.githubusercontent.com/AbrarAbe/chatl/main/install.sh | sh
```

### Windows (PowerShell)
```powershell
irm https://raw.githubusercontent.com/AbrarAbe/chatl/main/install.ps1 | iex
```

This installs `chatl` to `~/.local/bin` (Linux) or `%LOCALAPPDATA%\chatl` (Windows).
Add that directory to your `PATH`, then:

```sh
chatl --version
chatl                          # start a new session
chatl --continue               # resume the latest session
chatl --session <id>           # resume a specific session
```

First run creates `~/.config/chatl/config.yaml` with defaults. Edit it to point at your
model (any OpenAI-compatible endpoint: Ollama, LM Studio, vLLM, llama.cpp, Groq, Together,
OpenRouter, DeepSeek, Mistral, OpenAI…):

```yaml
models:
  default:
    model: gpt-4o-mini
    base_url: https://api.openai.com/v1
    api_key: $OPENAI_API_KEY
```

## Usage

Send a message and press Enter. Responses stream in as they arrive.

- `↑`/`↓` scroll the transcript; scroll to the bottom to re-enable auto-scroll
- `/history` — list the current conversation branch
- `/context` — session id, model, tokens used
- `/model <name>` / `/persona <name>` — switch mid-conversation (config profiles only)
- `/new` — start a fresh session
- `/rename <title>` — rename the current session
- `/copy` — copy the last assistant reply to the clipboard
- `/edit <new text>` — edit your last message; it forks the conversation into a new
  branch and regenerates the reply from that point
- `@fetch <url>` — paste a URL to attach its extracted text as context (post-v1 feature)

Editing a message is **fork-on-edit**: the edited message becomes the head of a new branch,
and the old branch is preserved untouched.

## Config

`~/.config/chatl/config.yaml` (create it if missing):

```yaml
models:
  default: gpt-4o-mini
  local:
    model: qwen2.5
    base_url: http://localhost:11434/v1
persona:
  default: "Concise technical assistant. Terse. No preamble."
ui:
  theme: dark          # dark | light
  prompt_prefix: "❯"
  markdown: true
commands:
  - name: recap
    prompt: Summarize our conversation in 5 bullets.
```

`ui.theme`, `ui.prompt_prefix`, and `ui.markdown` all take effect immediately.

## Scope

Chatl is **read-only** and **user-invoked only**:

- It reads the web (via `@fetch`/`@search` when configured) and your clipboard — never
  your filesystem, and never sends anything out except what you type on your screen.
- The model never invokes anything. You drive every step through `@` mentions and `/`
  commands; the syntax never reaches the model.

See `docs/spec.md` for the full design, and `docs/plan/plan_v0.2.0.md` for what's next.
