---
title: Weak watcher ownership silently killed push notifications in the bundled app
date: 2026-09-25
category: runtime-errors
module: keryx-notifications
problem_type: runtime_error
component: background_job
symptoms:
  - "No notification fires when a file lands in the watched directory, in any release since v0.4.0"
  - "Files are correctly identified on app launch, but never on change"
  - "Linux test suite is fully green while the bundled macOS app is dead"
  - "FSEvents callbacks never delivered even after the watcher implementation was replaced"
root_cause: logic_error
resolution_type: code_fix
severity: critical
related_components:
  - "testing_framework"
  - "development_workflow"
tags: [swift, arc, weak-reference, fsevents, nsstatusitem, swiftpm, tdd, linux-ci, deallocation]
---

# Weak watcher ownership silently killed push notifications in the bundled app

## Problem

Keryx's push-based file watcher (FSEvents, formerly vnode) never fired in the
bundled macOS app: files written to the inbox produced no notification and no
badge update, though the launch-time scan listed files correctly. The failure
was completely silent — no error, no log — and had shipped in every release
since the watcher-factory architecture landed in v0.4.0.

## Symptoms

- No notification, no badge change when files are added to the inbox at runtime
- Launch-time scan works fine (`apply()` → `refresh()` is called directly)
- `swift test` fully green on Linux while the real app is dead
- Same silence across two different watcher implementations (vnode and FSEvents)

## What Didn't Work

- **Replacing vnode with FSEvents** — necessary for subdirectory coverage
  (vnode `.write` only fires on direct-child changes of the watched
  directory), but did not fix notifications because the replacement watcher
  died the same death.
- **Passing a concurrent queue to `FSEventStreamSetDispatchQueue`** — the API
  requires a serial queue; a concurrent queue is undefined behavior.
- **Existing unit tests** — the watcher-triggered-refresh test passed because
  the test itself held a strong reference to the watcher it passed in,
  masking the production ownership bug entirely.

## Solution

Two changes in `Sources/KeryxKit/InboxController.swift` and
`Sources/KeryxKit/FSEventsInboxWatcher.swift`:

1. The controller now **strongly owns** its watcher (previously `weak var`):

```swift
// Before: the factory-created watcher was deallocated immediately — the
// controller's weak var was the only (non-)reference.
private weak var watcher: (any InboxWatcher)?

// After: strong ownership; no cycle because the watcher holds the
// controller's delegate weakly.
private var watcher: (any InboxWatcher)?
```

2. `init` now creates the watcher via the factory when none is supplied,
   instead of deferring creation to `apply(settings:)`:

```swift
self.watcher = watcher ?? watcherFactory(scanner.directory)
```

3. The FSEvents stream is scheduled on a dedicated **serial** queue:

```swift
private let streamQueue = DispatchQueue(label: "keryx.fsevents", qos: .utility)
FSEventStreamSetDispatchQueue(stream, streamQueue)
```

Locked in by an integration test that exercises the factory path (the path
production uses) rather than an externally constructed watcher:

```swift
@Test("factory-created watcher is retained and triggers refresh")
func factoryWatcherRetained() async throws {
    let controller = InboxController(
        scanner: DirectoryScanner(directory: dir),
        watcherFactory: { url in PollingInboxWatcher(directory: url, interval: 0.05) }
    )
    await try confirmation("factory-created watcher delivers changes",
                           expectedCount: 1...) { confirm in
        controller.onChange = { confirm() }
        controller.start()
        // write a file, await the confirmation
    }
}
```

## Why This Works

`InboxController` stored its watcher as `weak var` while creating it through a
factory closure — a classic lost-reference bug. The factory returns the only
strong reference to the new watcher; assigning it to a weak property retains
nothing, so ARC destroyed the watcher the moment `apply(settings:)` returned.
Its dispatch source/timer died with it, so file events were silently dropped
forever. The delegate was already weak (correct — that's what avoids a
reference cycle), which made the watcher the *sole* owner-able object, and
nobody owned it.

The tests missed it because they construct watchers themselves and hold them
in local variables — the test *was* the strong owner that production lacked.
The launch scan worked because `apply()` also performs a direct `refresh()`,
decoupled from the watcher, which made the app look half-alive and delayed
diagnosis.

`FSEventStreamSetDispatchQueue` has its own contract (serial queue only); the
global concurrent queue silently misbehaved on top of the ownership bug.

## Prevention

- **Test object creation through the production factory path.** Any test that
  constructs the object-under-test itself and hands it to the system can mask
  an ownership bug: the test's local strong reference substitutes for the
  production owner. The regression test here deliberately creates nothing —
  it lets the controller's factory produce the watcher and then verifies
  events still arrive.
- **When a class stores a delegate weakly, ask who strongly owns the delegate
  side.** Weak-delegate patterns are safe only when the object is strongly
  retained elsewhere; a factory + weak field combination is a red flag.
- **CI on the real platform catches what Linux tests cannot.** The Darwin CI
  job compile-checks the AppKit/FSEvents surface on every push; runtime bugs
  like this still need one manual end-to-end check on a Mac per release
  (drop a file, expect a notification).
- **Check API contracts, not just signatures**: `FSEventStreamSetDispatchQueue`
  documents a serial-queue requirement that no compiler will enforce.

## Related Issues

- GitHub issue #1 (notarization) — unrelated surface, still open.
- The subdir blind spot (vnode watcher only saw direct children) was fixed in
  the same release (v0.5.3) by replacing vnode watching with FSEvents
  file-events over the whole subtree.