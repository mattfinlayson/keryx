# AGENTS.md

Guidance for coding agents working in this repository.

## Project

Keryx is a macOS menubar utility that watches a directory ("inbox") for files
written by scheduled jobs/agents, shows an unread badge, and opens files in a
chosen viewer. Written in Swift; **developed and tested on Linux**, packaged
and run on macOS.

## Toolchain

- Swift toolchain is managed by [swiftly](https://www.swift.org/swiftly/)
  (Swift 6.4, Ubuntu 26.04 native toolchain). Source it with
  `. ~/.local/share/swiftly/env.sh` before running swift commands in a fresh shell.
- Tests use **Swift Testing** (`import Testing`, `#expect`, `confirmation`) —
  never XCTest. There is no Package.resolved; the package has zero dependencies.
- Platform minimum is macOS 15 (`Package.swift` `platforms`), Ubuntu 26.04 for dev.

## Commands

```sh
swift build       # builds the whole package on Linux (AppKit code is #if os(macOS)-guarded)
swift test        # full suite (Swift Testing); all tests must pass on Linux before any commit
swift run KeryxApp  # on Linux prints a no-op notice; on macOS runs the menubar app
```

There is no linter configured — treat `swift build` warnings as failures and fix them.

## Architecture (respect these boundaries)

| Target | Role | Constraints |
|--------|------|-------------|
| `Sources/KeryxKit/` | Platform-independent core: state machine, scanner, watchers, settings, controller | No AppKit/UserNotifications. **All behavior here is TDD'd on Linux.** |
| `Sources/KeryxApp/` | Thin macOS shell: menubar, menu, notifications, Settings window, login item | Everything guarded with `#if os(macOS)` so the package still builds on Linux. Presentation only — business logic belongs in KeryxKit. |
| `Tests/KeryxKitTests/` | Swift Testing suite for KeryxKit | Test files are named `<Type>Tests.swift` and use `@Suite("Name")` structs. |

Key invariants:
- **Single update point:** `AppDelegate.render()` is the only place that rebuilds
  the menubar icon and menu. Do not fragment state updates into ad-hoc paths.
- **Single opener chain:** file-opening resolution (extension rule → `*` rule →
  `KERYX_OPEN_APP` env → OS default) lives in one shared helper. Menu clicks and
  notification taps must both route through it.
- **Thread-safety:** `InboxController` serializes state access on an internal
  queue; the watcher fires on a background queue and UI reads happen on main.
  Preserve this when touching controller code.
- **No binary assets in the repo** — the app icon is generated at release time
  by `Scripts/make-icon.swift` on the macOS runner.

## Swift Testing quirks (learned the hard way)

- `#expect` cannot capture a *mutating* call: `#expect(!state.foo())` fails to
  compile. Bind first: `let changed = state.foo()` then `#expect(!changed)`.
- Linux corelibs `FileManager.enumerator(at:)` silently returns an empty
  enumerator for a missing directory (Darwin returns nil) — never rely on
  its nil-ness without checking existence first.
- Darwin `open()` returns non-optional `Int32` (check `fd != -1`, not nil).
- `NSButton` has no `representedObject`; `NSWindow` init takes no `title:`.
- `#expect` with `confirmation` counts every call — use `expectedCount: 1...`
  for at-least-once.

## Workflow conventions

- **TDD on Linux for all KeryxKit behavior**: write the failing test, see it
  red, implement, see it green, then commit. No exceptions for core changes.
- macOS shell changes are compile-checked by CI (`.github/workflows/ci.yml`
  builds on a macOS runner) and visually verified manually on the Mac; put
  `Test expectation: none — [reason]` in plans for these.
- Conventional commits: `feat(kit): …`, `feat(app): …`, `fix(…)`; work happens
  on `feat/*` or `fix/*` branches, fast-forward merged to `main`.
- **CI is the Darwin compiler.** The Linux suite cannot catch AppKit API
  mismatches — always push and wait for the `test-macos` job before merging.
- Releases are tag-driven: `git tag vX.Y.Z && git push origin vX.Y.Z` triggers
  `.github/workflows/release.yml` (builds, generates the app icon, packages
  `Keryx.app`, creates a GitHub Release with generated notes).
- **End every work stream that ships a release with the user's full
  download/removal commands** — `curl -L` of the release zip, `unzip`,
  `xattr -cr` (Gatekeeper workaround), and `open` — pinned to the version
  just shipped, plus the `releases/latest/download/` variant when the asset
  name is current. The user installs from these commands directly.
- Settings persist in `UserDefaults` under the `keryx` domain. `KERYX_INBOX`
  and `KERYX_OPEN_APP` env vars override settings at runtime.

## Docs

- Requirements live in `docs/brainstorms/`, implementation plans in `docs/plans/`.
  Plans carry `status: active|completed` frontmatter — flip to `completed` when
  a plan fully ships.
- `docs/solutions/` — documented solutions to past problems (bugs, best
  practices, workflow patterns), organized by category with YAML frontmatter
  (`module`, `tags`, `problem_type`). Relevant when implementing or debugging
  in documented areas.
- Open work is tracked as GitHub issues (e.g., #1: notarization).