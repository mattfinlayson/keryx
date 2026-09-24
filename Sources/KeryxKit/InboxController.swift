import Foundation

/// Chooses the best watcher for the platform: push-based vnode watching on
/// macOS, interval polling elsewhere.
public enum InboxWatchers {
    public static func platformDefault(directory: URL, interval: TimeInterval) -> any InboxWatcher {
        PollingInboxWatcher(directory: directory, interval: interval)
    }
}

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

    /// Called with files that became unseen (new or newly modified) after a
    /// refresh. Drives user notifications.
    public var onNewFiles: (([FileEntry]) -> Void)?

    private var scanner: DirectoryScanner
    private weak var watcher: (any InboxWatcher)?
    private var inboxURL: URL?
    private var scanInterval: TimeInterval
    private var isRunning = false
    private let watcherFactory: (URL, TimeInterval) -> any InboxWatcher
    private let queue = DispatchQueue(label: "keryx.inbox.controller", qos: .utility)
    private var _state = InboxState()

    public init(
        scanner: DirectoryScanner,
        watcher: (any InboxWatcher)? = nil,
        watcherFactory: @escaping (URL, TimeInterval) -> any InboxWatcher = InboxWatchers.platformDefault
    ) {
        self.scanner = scanner
        self.watcher = watcher
        self.inboxURL = scanner.directory
        self.scanInterval = AppSettings.default.scanInterval
        self.watcherFactory = watcherFactory
    }

    /// Reconfigures the controller: swaps the watched inbox, scan interval,
    /// and watcher as needed. Safe to call while running.
    public func apply(settings: AppSettings) {
        let wasRunning = isRunning
        let url = settings.inboxURL
        let inboxChanged = (url != inboxURL)
        let intervalChanged = (settings.scanInterval != scanInterval)

        inboxURL = url
        scanInterval = settings.scanInterval

        if inboxChanged {
            stop()
            if let url {
                scanner = DirectoryScanner(directory: url)
                watcher = watcherFactory(url, scanInterval)
            } else {
                watcher = nil
            }
            if wasRunning {
                start()
            }
        } else if intervalChanged, isRunning {
            // Polling watchers need recreation to pick up the new interval;
            // event-driven watchers ignore it entirely.
            let url = self.url ?? scanner.directory
            stop()
            watcher = watcherFactory(url, scanInterval)
            start()
        }

        try? refresh()
    }

    private var url: URL? { inboxURL ?? settingsFallbackURL }

    private var settingsFallbackURL: URL? { nil }

    /// Starts watching; the inbox is scanned immediately.
    public func start() {
        isRunning = true
        watcher?.delegate = self
        watcher?.start()
    }

    /// Stops watching.
    public func stop() {
        isRunning = false
        watcher?.stop()
        watcher?.delegate = nil
    }

    /// Re-scans the inbox directory and reconciles state.
    public func refresh() throws {
        var changed = false
        var updated = InboxState()
        var newFiles: [FileEntry] = []
        let files = try scanner.scan()

        queue.sync {
            updated = _state
            for file in files {
                let previous = updated.entries.first { $0.id == file.id }
                changed = updated.insert(file) || changed
                let isUnseen = updated.unseenPaths.contains(file.id)
                if isUnseen {
                    if previous == nil || previous!.modificationDate < file.modificationDate {
                        newFiles.append(file) // brand-new file or new content
                    }
                }
            }
            changed = updated.sync(existingPaths: files.map(\.id)) || changed
            if changed {
                _state = updated
            }
        }

        if changed {
            onChange?()
        }
        if !newFiles.isEmpty {
            onNewFiles?(newFiles)
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