import Foundation

/// Glues the scanner, watcher, and state together. The macOS shell observes
/// `state` (via `onChange`) and renders badge + menu from it.
public final class InboxController: InboxWatcherDelegate {
    public private(set) var state: InboxState

    /// Called whenever state may have changed. Invoked on the watcher's
    /// queue (background); the shell should hop to the main thread.
    public var onChange: (() -> Void)?

    private let scanner: DirectoryScanner
    private weak var watcher: (any InboxWatcher)?

    public init(scanner: DirectoryScanner, watcher: (any InboxWatcher)? = nil) {
        self.scanner = scanner
        self.watcher = watcher
        self.state = InboxState()
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
        let files = try scanner.scan()
        var changed = false
        for file in files {
            changed = state.insert(file) || changed
        }
        changed = state.sync(existingPaths: files.map(\.id)) || changed
        if changed {
            onChange?()
        }
    }

    /// Marks an entry as opened (seen).
    public func open(_ entry: FileEntry) {
        if state.markOpened(path: entry.id) {
            onChange?()
        }
    }

    // MARK: InboxWatcherDelegate

    public func inboxDidChange() {
        try? refresh()
    }
}