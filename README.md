# Keryx

[![CI](https://github.com/mattfinlayson/keryx/actions/workflows/ci.yml/badge.svg)](https://github.com/mattfinlayson/keryx/actions/workflows/ci.yml)

A macOS menubar utility that watches a directory for files written by
scheduled jobs / agents and gives you a native way to receive them:

- **Menubar Caduceus icon with an unread count** — the count appears (in
  monospaced digits) when files arrive and clears as you read them.
- **Push-based watching** — the whole inbox subtree is watched via FSEvents,
  so files landing in job subdirectories notify within milliseconds; no
  polling delay. (Linux falls back to interval polling.)
- **Click a file** in the menu or a notification to open it in your markdown
  viewer of choice (or the default handler) and clear its "new" flag.
- **Read state persists across launches** — opened files stay read; only
  genuinely new (or rewritten) files re-flag unread.
- **Files removed from disk** disappear from the menu on the next scan.

## Architecture

| Target | Contents | Builds on |
|--------|----------|-----------|
| `KeryxKit` | Platform-independent core: `InboxState` (unseen/seen state machine), `DirectoryScanner`, `InboxWatcher` (interval polling + FSEvents subtree watcher on macOS), `AppSettings` + `SeenStore`, `InboxController` | Linux + macOS, fully unit-tested (Swift Testing) |
| `KeryxApp` | Thin AppKit menubar shell (`NSStatusItem`, settings window, user notifications, login item), guarded with `#if os(macOS)` | macOS only (no-op placeholder binary on Linux) |

The development loop is entirely on Linux: every behavior is TDD'd in
`KeryxKit`, which knows nothing about AppKit. The macOS shell is a thin
renderer over `InboxController` state.

## Toolchain

- [swiftly](https://www.swift.org/swiftly/) manages the Swift toolchain
  (Swift 6.4, officially supports Ubuntu 26.04 as of swiftly 1.2.0).
- Tests use **Swift Testing** (bundled in the toolchain — no XCTest
  dependency).

### Linux (development)

```sh
# one-time toolchain install
curl -O https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz
tar zxf swiftly-$(uname -m).tar.gz && ./swiftly init --assume-yes
. ~/.local/share/swiftly/env.sh
sudo apt-get install binutils-gold libcurl4-openssl-dev libxml2-dev libz3-dev pkg-config

swift build   # whole package builds on Linux (AppKit part is #if-guarded)
swift test    # 46 tests over the core
```

### macOS (runtime)

**Settings:** ⌘, from the menubar menu (or "Settings…"):

- **Inbox folder** — directory picker, changes apply live
- **Ignore files older than** — hide files whose last modification predates
  the cutoff (Off / 1h / 3h / 6h / 12h / 1d / 2d / 3d / 7d / 14d). Useful
  when pointing the inbox at a directory that already holds a long history
  of output — older files never appear and never notify. A file whose
  content is rewritten shows up again (fresh modification date).
- **Open files ending in** — map a file extension to a specific application
  (e.g. `md → Marked 2`), overriding the OS default handler; without a
  rule, files open with the default app

**Mark All Read** (⇧⌘K in the menu) clears every unseen flag at once.

**Launch at Login:** checkbox in Settings. Registered via the system
(SMAppService); approve in System Settings → General → Login Items if macOS
asks. Requires the bundled app (not the bare `swift build` binary).

**Menubar:** a hand-drawn caduceus as a monochrome template image that tints
with light/dark menu bars, with an unread count in monospaced digits when
files arrive. The menu shows a latest-file preview (path + relative time),
per-file unseen markers, nested files as paths relative to the inbox root,
and SF Symbol icons on actions.

**Notifications:** the app requests notification permission on first launch
and posts a notification when new (or newly updated) files land anywhere in
the inbox subtree. **Clicking a notification opens the newest file** (via the
same opener rules as the menu) and marks it read. Watching is push-based on
macOS (FSEvents file events over the subtree, lightly debounced) — no
polling delay.

**Read state persists across launches** — files you've opened stay read when
the app restarts; only genuinely new (or rewritten) files re-flag unread.

**About:** "About Keryx" in the menu shows the app's purpose, version, and
author.

**Option 1 — prebuilt app:** download `Keryx-vX.Y.Z-macos.zip` from
[Releases](https://github.com/mattfinlayson/keryx/releases), unzip, and run
`Keryx.app`. The bundle is ad-hoc signed (not notarized — see
[issue #1](https://github.com/mattfinlayson/keryx/issues/1)), so on first
launch Gatekeeper will block it. Either run

```sh
xattr -cr /path/to/Keryx.app
```

or open **System Settings → Privacy & Security**, scroll to the warning, and
click **Open Anyway** (right-click → Open is no longer sufficient on recent
macOS). This is a one-time step per downloaded copy.

**Option 2 — from source:**

```sh
git clone https://github.com/mattfinlayson/keryx
cd keryx
swift build -c release
.build/release/KeryxApp
```

### Configuration (environment)

| Variable | Meaning | Default |
|----------|---------|---------|
| `KERYX_INBOX` | Directory to watch | `~/keryx-inbox` |
| `KERYX_OPEN_APP` | App name passed to `open -a` for viewing files | system default handler |

### Roadmap ideas

- FSEvents watcher hardening: re-arm on inbox folder recreation/move.
- Menu row context actions (reveal in Finder, copy path).
- Background-launch handling: opening a notification while the app is not
  running should reliably open the file after launch.
- Per-rule opener UI for wildcards beyond `*` (e.g. `*.log` → tail viewer).

## Building it

The first complete version of Keryx — toolchain setup, TDD'd core, menubar
app, settings, notifications, CI, and releases — was built in one working
session with the [pi coding agent](https://github.com/earendil-works) using
the Compound Engineering workflow, running **glm-5.3-flash on Ollama Cloud**
at a total token cost of **$2.56**.

[![Built With Compound Engineering](https://img.shields.io/badge/Built%20With-Compound%20Engineering-6b46c1)](https://github.com/earendil-works)