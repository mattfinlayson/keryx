# Keryx

[![CI](https://github.com/mattfinlayson/keryx/actions/workflows/ci.yml/badge.svg)](https://github.com/mattfinlayson/keryx/actions/workflows/ci.yml)

A macOS menubar utility that watches a directory for files written by
scheduled jobs / agents and gives you a native way to receive them:

- **Menubar icon with an unseen count badge** — turns into `✉ N` when files
  arrive and stays that way until you click them.
- **Click a file** in the menu to open it in your markdown viewer of choice
  (or the default handler) and clear its "new" flag.
- **Files removed from disk** disappear from the menu on the next scan.

## Architecture

| Target | Contents | Builds on |
|--------|----------|-----------|
| `KeryxKit` | Platform-independent core: `InboxState` (unseen/badge state machine), `DirectoryScanner`, `InboxWatcher` + `PollingInboxWatcher`, `InboxController` | Linux + macOS, fully unit-tested (Swift Testing) |
| `KeryxApp` | Thin AppKit menubar shell (`NSStatusItem`), guarded with `#if os(macOS)` | macOS only (no-op placeholder binary on Linux) |

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
swift test    # 15+ tests over the core
```

### macOS (runtime)

**Option 1 — prebuilt app:** download `Keryx-vX.Y.Z-macos.zip` from
[Releases](https://github.com/mattfinlayson/keryx/releases), unzip, and run
`Keryx.app`. The bundle is ad-hoc signed (not notarized), so on first launch
macOS Gatekeeper may require right-click → Open, or
`xattr -cr Keryx.app` from Terminal.

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

- Swap `PollingInboxWatcher` for an FSEvents/`DispatchSource` vnode watcher
  on macOS behind the existing `InboxWatcher` protocol.
- Persist unseen state across relaunches.
- Menu icons/preview per file type.