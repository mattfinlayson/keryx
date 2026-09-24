import Foundation

/// Glues the scanner, watcher, and state together. The macOS shell observes
/// `state` (via `onChange`) and renders badge + menu from it.
///
/// Thread-safety: all state access is serialized on an internal queue, so
/// `refresh()` may be called from the watcher's background queue while the
/// UI thread reads `state`.
public final class InboxController {
    /// Snapshot of the current state; safe to read from any thread.
    public var state: InboxState { queue.sync { _state } }

    /// Called whenever state may have changed. Invoked on the caller's
    /// thread of the last mutation (usually the watcher's queue); the shell
    /// should hop to the main thread before touching AppKit.
    public var onChange: (() -> Void)?

    private let scanner: DirectoryScanner
    private weak var watcher: (any InboxWatcher)?
    private let queue = DispatchQueue(label: "keryx.inbox.controller", qos: .utility)
    private var _state = InboxState()

    public init(scanner: DirectoryScanner, watcher: (any InboxWatcher)? = nil) {
        self.scanner = scanner
        self.watcher = watcher
    }

    /// Starts watching; the inbox is scanned immediately.
    public func start() {
        watcher?.delegate = self
        watcher?.start()
    }

    /// Stops watching.
    public func stop() {
        watcher?.stop()
        watcher?.delegate = nil
    }

    /// Re-scans the inbox directory and reconciles state.
    public func refresh() throws {
        var changed = false
        var updated = InboxState()
        let files = try scanner.scan()

        queue.sync {
            updated = _state
            for file in files {
                changed = updated.insert(file) || changed
            }
            changed = updated.sync(existingPaths: files.map(\.id)) || changed
            if changed {
                _state = updated
            }
        }

        if changed {
            onChange?()
        }
    }

    /// Marks an entry as opened (seen).
    public func open(_ entry: FileEntry) {
        let changed: Bool = queue.sync {
            if _state.markOpened(path: entry.id) {
                return true
            }
            return false
        }
        if changed {
            onChange?()
        }
    }
}

extension InboxController: InboxWatcherDelegate {
    public func inboxDidChange() {
        try? refresh()
    }
}