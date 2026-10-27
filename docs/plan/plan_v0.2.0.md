# Implementation Plan: chatl v0.2.0 (distribution + roadmap features)

Delivers release **0.2.0**. Follows the completed 0.1.0 MVP
(`plan_v0.1.0.md`); the app behaviour contract stays `docs/spec.md`.

**Milestone shape:** Phase 0 makes chatl *installable* (release engineering — no
user-visible app behaviour); Phase 1 delivers the spec's post-v1 roadmap
(`@fetch`/`@search` with citations), which was designed for in v1 but deliberately not
built.

## Phase 0 — Release engineering

Bundle: all Phase 0 tasks land on **`chore/release-engineering`** (shared files:
`pubspec.yaml`, `.github/`, `tool/`), merged when the phase's checkpoint holds. Scope is
infrastructure (`ci`/`chore`) — no spec behaviour change beyond the new Distribution
section.

**Decisions settled 2026-09-27 (with the maintainer):**

- **Distribution:** native binaries per platform as GitHub Release assets, consumed by
  `install.sh` / `install.ps1` with SHA256 verification. `dart pub global activate`
  deferred; no Homebrew/scoop/winget manifests in 0.2.0.
- **sqlite3:** bundled beside the binary (Windows `sqlite3.dll`; Linux a bundled
  `libsqlite3.so` used when the system library is absent). The native-assets hook is the
  considered upgrade, not this milestone's work.
- **Release channel:** CI builds and uploads; **release notes and the version bump/tag
  come from the maintainer's release skill** — CI must never draft prose.

- [x] **Task 0.1: CI workflow (analyze, format, test)** — DONE on
      `chore/release-engineering`. `.github/workflows/ci.yml`: push-to-main + PRs,
      matrix `ubuntu-latest`/`windows-latest`, Dart stable, pub cache, and the four
      Definition-of-done gates (format check and `dart analyze --fatal-infos`
      included). Format gate forced a repo-wide `dart format` sweep (45 files,
      mechanical) — the maintainer's editor was not formatting on save; **if
      format-on-save is reconfigured to a different style the CI gate will fail, so
      align the editor or drop that step.** Local parity verified: `pub get`,
      format check (0 changed), `analyze --fatal-infos` clean, 145 tests pass; workflow
      YAML parses with the expected matrix and steps.
  - **Acceptance:** `.github/workflows/ci.yml` runs on push to `main` and on PRs; matrix
    `ubuntu-latest` + `windows-latest` on Dart stable; steps are exactly the Definition of
    done gates: `dart pub get`, `dart format --output=none --set-exit-if-changed .`,
    `dart analyze --fatal-infos`, `dart test`; pub cache restored via `dart-lang/setup-dart`
    + `actions/cache`; a red test or an unformatted file fails the build.
  - **Verify:** the same four commands pass locally today (they do: 145 tests, clean
    analyze); workflow YAML parses; `actionlint` if available.
  - **Files:** `.github/workflows/ci.yml`.
  - **Scope:** M · bundle branch · test strategy: none (config); verification is command
    parity + YAML parse.

- [x] **Task 0.2: Version plumbing (`chatl --version`)** — DONE on
      `chore/release-engineering`. `lib/src/version.dart` reads
      `String.fromEnvironment('CHATL_VERSION', defaultValue: 'dev')`; `--version`
      prints `chatl <version>`; `tool/check_version.dart` guards tag↔pubspec (leading
      `v` optional, `+build` metadata ignored, non-versions rejected). Verified for real:
      compiled with `-DCHATL_VERSION=0.1.0` → prints `chatl 0.1.0`; `dart run` → `chatl
      dev`; guard exits 0 on `v0.1.0`, 1 on `v9.9.9` and on `nightly`. 152 tests pass,
      analyze `--fatal-infos` clean.
  - **Acceptance:** `pubspec.yaml` stays the single source of truth; the binary carries the
    version via `--define=CHATL_VERSION=<pubspec version>` read by
    `const String.fromEnvironment('CHATL_VERSION', defaultValue: 'dev')`; `chatl --version`
    prints it and exits 0; an unbuilt `dart run bin/chatl.dart` prints `dev`;
    `tool/check_version.dart --tag v0.2.0` exits 0 on a match and non-zero with a clear
    message on a mismatch (the guard that keeps ADR 0001's coupled scheme honest).
  - **Verify:** `dart test test/cli/ test/tool/`.
  - **Files:** `lib/src/version.dart`, `lib/src/cli/args.dart`, `bin/chatl.dart`,
    `tool/check_version.dart`, tests.
  - **Scope:** S · bundle · TDD (`dart-add-unit-test`). *(done)*

- [x] **Task 0.3: Release packaging (`tool/package_release.dart`)** — DONE on
      `chore/release-engineering`. `tool/package_release.dart` compiles with the injected
      version, lays out binary + sqlite3 + README, zips and appends to `dist/SHA256SUMS`
      (via `package:crypto`, which nocterm/analyzer already pull in transitively; dev-only);
      `lib/src/state/sqlite_loader.dart` points `package:sqlite3` at a bundled
      `libsqlite3.so` beside the binary (Linux does not search the executable's dir;
      Windows does, so it needs nothing). **Verified on a real Linux package:**
      `chatl-0.1.0-linux-x64.zip` built, `sha256sum -c SHA256SUMS` → OK, unzipped binary
      reports `chatl 0.1.0`, and a run from an empty HOME created a valid
      `SQLite format 3` session DB while `LD_DEBUG` showed it loading the *bundled*
      `/tmp/…/libsqlite3.so`. 161 tests pass; Windows packaging stays CI-only.
  - **Acceptance:** running it produces `dist/chatl-<version>-<platform>.zip` containing the
    compiled binary, the bundled sqlite3 library, `README` (how to run/where to unzip), and
    writes `dist/SHA256SUMS`; the zipped binary reports the injected version and can open a
    session DB from an empty directory with only the bundled library present.
  - **Verify:** run locally on Linux (Linux artifact) — `dart run tool/package_release.dart
    --version 0.2.0`; unzip to a temp dir, run `--version`, and start one session to prove
    sqlite3 loads; `dart test test/tool/` for the checksum/assembly helpers.
  - **Files:** `tool/package_release.dart`, `tool/sqlite_assets.dart`, tests.
  - **Scope:** M · bundle · TDD on the pure helpers; the compile step is verified by the
    run above. **Windows artifact is built by CI (Task 0.4), not locally** — the local run
    is the Linux proof. *(done)*

- [x] **Task 0.4: Release workflow (tag-triggered)** — DONE on
      `chore/release-engineering`. `.github/workflows/release.yml`: on every `v*` tag,
      verify tag vs pubspec via tool/check_version.dart, matrix build both platforms
      via tool/package_release.dart (Windows sqlite3.dll downloaded from sqlite.org),
      create the GitHub Release with gh --verify-tag --clobber for idempotent re-runs.
      YAML parsed locally; all 161 tests pass; analyze clean; format gate green.
  - **Acceptance:** `.github/workflows/release.yml` triggers on `v*` tags; first step runs
    `tool/check_version.dart --tag <tag>` so a tag/pubspec mismatch fails fast; matrix builds
    both platforms, uploads the zips + `SHA256SUMS` to the GitHub Release for that tag
    (`gh release create --verify-tag`, no notes drafting); re-running is idempotent
    (`--clobber`).
  - **Verify:** YAML parse + `dart test test/tool/` (the version guard is the tested part);
    end-to-end is a dry tag push on a scratch tag, run by the maintainer on demand.
  - **Files:** `.github/workflows/release.yml`.
  - **Scope:** M · bundle · test strategy: config + the tool it calls.

- [x] **Task 0.5: Install scripts***
  - **Acceptance:** `install.sh` (Linux) and `install.ps1` (Windows): detect OS/arch, fetch
    the matching asset for `--version <v>` (default: latest), **verify SHA256 against
    `SHA256SUMS`**, install to `~/.local/bin/chatl` (Linux) / `%LOCALAPPDATA%\chatl`
    (Windows), print a PATH hint, support `--uninstall`, and are idempotent. Both accept
    `CHATL_DIST_DIR` so they can be exercised against a local `dist/` without network.
  - **Verify:** `CHATL_DIST_DIR=dist ./install.sh --version 0.2.0` installs and
    `~/.local/bin/chatl --version` reports it; a tampered asset fails the checksum step;
    `--uninstall` removes it. Same flow in CI for `install.sh`; `install.ps1` exercised on
    the Windows runner.
  - **Files:** `install.sh`, `install.ps1`, `tool/test_install.sh`, CI step.
  - **Scope:** M · bundle · test strategy: shell-level integration in CI + local run above.

- [x] **Task 0.6: Distribution docs + scaffold cleanup***
  - **Acceptance:** spec gains a Distribution section (install commands, `--version`, asset
    names, checksum verification, uninstall); `README.md` has a quickstart (install, config
    sample, first run, `/` and `@` cheatsheet); Flutter/IDE leftovers removed:
    `.metadata`, `chatl.iml` (`.idea/` stays ignored), and any remaining `flutter:` blocks in
    configs.
  - **Verify:** `dart test` + `dart analyze` still green; `grep -r flutter` returns nothing
    outside docs/history.
  - **Files:** `docs/spec.md`, `README.md`, deletions.
  - **Scope:** S · bundle · tests-after (docs).

### Checkpoint: Phase 0

- [ ] CI green on both platforms for the merged branch.
- [ ] `dist/` artifacts build locally on Linux; install scripts verified against them.
- [ ] Tag guard proven: a mismatched tag is rejected.
- [ ] Version reported by the binary matches `pubspec.yaml`.
- [ ] Merge `chore/release-engineering` → `main`.

## Phase 1 — Roadmap features (spec §Post-v1 Roadmap)

Planned here as the milestone contract; each task is detailed (failures, caps, UX) when its
implementation starts, since the spec fixes the design already. Branch: `feature/search-fetch`
bundle (they share `resolve/`, `config`, `message_list`).

- [ ] **Task 1.1: `@search` resolver**
  - **Acceptance:** config `search: {backend: ddgr|brave|tavily, results, citations: true}`;
    `@search "query" — question` resolves to ranked snippets + the question, client-side;
    a missing backend fails **visibly** (spec Decisions); results populate
    `messages.sources`.
  - **Verify:** unit tests against a faked backend process/HTTP; live check by the user.
  - **Files:** `lib/src/resolve/search.dart`, config parsing, tests.
  - **Scope:** L · bundle · TDD (`dart-add-unit-test`, `dart-generate-test-mocks`).
- [ ] **Task 1.2: `@fetch` resolver**
  - **Acceptance:** config `fetch: {reader: 'w3m -dump'}` (also lynx/html2text); fetched text
    becomes a `[CONTEXT …]` block; subprocess failure → `[CONTEXT ERROR …]`;
    untrusted-content delineation preserved (spec §Security note).
  - **Verify:** unit tests with a fake reader binary; live check by the user.
  - **Files:** `lib/src/resolve/fetch.dart`, config parsing, tests.
  - **Scope:** L · bundle · TDD.
- [ ] **Task 1.3: Context size cap + visible truncation**
  - **Acceptance:** configurable cap (default 100 KB per resolver, spec Decisions); over-cap
    content is truncated **with a visible notice**, never silently dropped.
  - **Verify:** `dart test test/resolve/`.
  - **Files:** `lib/src/resolve/*`, tests.
  - **Scope:** S · bundle · TDD.
- [ ] **Task 1.4: Citations UX + `sources` persistence**
  - **Acceptance:** trailing sources block after the reply (spec Decisions) with a toggle
    key; `messages.sources` written on resolve and restored on resume.
  - **Verify:** store tests + widget tests for the trailing block/toggle.
  - **Files:** `lib/src/state/session_store.dart`, `ui/widgets/message_list.dart`, tests.
  - **Scope:** M · bundle · TDD for persistence, tests-after for layout.

### Checkpoint: Phase 1

- [ ] Both resolvers work end-to-end, user-invoked only (no model tool calls).
- [ ] Citations visible and persisted; failures never silent.
- [ ] Merge `feature/search-fetch` → `main`.

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Bundled sqlite3 drifts from the version `package:sqlite3` expects | Med | Pin the sqlite version in `tool/sqlite_assets.dart`; CI smoke-runs the packaged binary against a temp DB |
| Release workflow publishes without checksums/verification | High | Checksums generated in the same job as the assets; install scripts refuse assets without a matching hash |
| Windows path/loader differences surface only at release time | Med | Windows artifact is built and smoke-run in CI on every tag, not on the maintainer's machine |
| `--define` version injection forgotten for a build | Low | `tool/check_version.dart` runs first in the release workflow; `dev` fallback makes a missing injection obvious |
| Subprocess-based resolvers (`@fetch`, `@search`) reopen the "no plugin runtime" tension | Med | Confined to the two resolvers, configured by the user, documented in the spec (already noted in §Post-v1) |

## Open Questions

- Do we keep the throwaway `spike/markdown-renderer` branch, or delete it now that ADR 0003
  carries the findings? (Suggests: delete.)
- Should CI also run `dart pub outdated` as an advisory check? (Suggests: no, keep the gate
  deterministic; dependabot/renovate later if wanted.)
- macOS: still not a target, but pub.dev activation would cover it for free — revisit if the
  couple-of-extra-lines cost ever looks worth it.
