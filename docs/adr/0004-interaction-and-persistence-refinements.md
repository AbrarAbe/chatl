# ADR 0004: Implementation-time refinements to the interaction and persistence model

**Status:** Accepted
**Date:** 2026-09-27

## Context

Four decisions were forced during implementation of v0.1.0 that the spec did not
anticipate. Each was verified by a failing test or a reproduced framework behaviour, and
each is recorded here instead of being left as an unexplained trait of the code.

## Decisions

### 1. `/edit <new text>` is the fork-on-edit affordance, not a Ctrl+E chord

The plan called for Ctrl+E to prefill the input with the turn being edited. Two problems,
both reproduced:

- **Key routing:** nocterm dispatches key events children-first, so the focused
  `TextField` consumes chords before the screen's `Focusable` handler ever sees them.
- **Input prefill:** nocterm's `TextField` keeps an internal buffer that mutating the
  shared controller does not reliably reset; keying the field to force a rebuild produced
  different results across interleavings (a race), which is unacceptable for an editing
  flow.

`/edit <new text>` is a one-shot verb: deterministic, typed (so it inherits the `/`-verb
grammar from the spec), and testable without touching focus at all. Cost: no prefill, so
the user retypes the turn they are revising.

### 2. drift DateTimes are stored as text (`build.yaml`)

drift's default integer storage has second resolution, which made `updatedAt` collide for
sessions created within the same second — `--continue` then resumed the wrong session.
`store_date_time_values_as_text: true` keeps sub-second precision. Schema v1 was
unreleased, so no migration was needed.

### 3. `appendMessage` distinguishes "omitted parent" from "explicit null parent"

`parentId ?? currentHead` silently attached a fork of the *first* message to the head,
producing branches with the wrong ancestry. `linkToHead: false` marks a deliberate root.
Forks never advance the head themselves (`advanceHead: false`); the caller does it with
`setHead`, matching the spec's `SessionStore` seam.

### 4. Requests carry only real conversation turns, and turn-resolved content

Two related rules, each found by a live failure or a test:

- `notice` turns (command feedback, `/context`) and error turns are excluded from API
  requests. Sending `role: "notice"` made OpenAI-compatible endpoints reject the whole
  request with **HTTP 400 invalid role**; error text was also being fed back as assistant
  prose.
- `Turn.requestContent` holds the `@`-resolved form so the syntax never reaches the model
  even in replayed history, while the transcript keeps what the user actually typed.
  Turns restored from disk replay raw text (re-resolution is deferred with the resolvers
  themselves).

## Consequences

- The spec's §Interaction Model, §Fork-on-edit and §The `@` resolver layer were updated to
  match (single source of truth stays current).
- Retaining these as ADR-level decisions means a future contributor does not "fix" the
  `/edit` verb back into a chord, revert the date storage, or reintroduce notice turns
  into requests without knowing why they are the way they are.
