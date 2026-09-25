#if os(macOS)
import Foundation
import CoreServices

/// Push-based watcher over the entire inbox subtree using FSEvents with
/// file-level events. Replaces the vnode watcher, which only fired for
/// direct-child changes of the watched directory and silently missed files
/// written into subdirectories.
///
/// Events are lightly debounced (~150ms) so a job writing several files
/// triggers a single refresh. If stream creation fails, the watcher falls
/// back to interval polling rather than silently not watching.
public final class FSEventsInboxWatcher: InboxWatcher {
    public weak var delegate: InboxWatcherDelegate?

    private let directory: URL
    private var stream: FSEventStreamRef?
    /// FSEventStreamSetDispatchQueue requires a serial queue.
    private let streamQueue = DispatchQueue(label: "keryx.fsevents", qos: .utility)
    private var pendingWorkItem: DispatchWorkItem?
    private var fallbackPoller: PollingInboxWatcher?

    public init(directory: URL) {
        self.directory = directory
    }

    public func start() {
        stop()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FSEventsInboxWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.scheduleInboxChange()
        }

        let paths = [directory.path] as CFArray
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.1, flags
        ) else {
            FileHandle.standardError.write(
                "keryx: FSEventStreamCreate failed; falling back to polling\n".data(using: .utf8)!)
            let poller = PollingInboxWatcher(directory: directory, interval: 2.0)
            poller.delegate = delegate
            poller.start()
            fallbackPoller = poller
            return
        }

        FSEventStreamSetDispatchQueue(stream, streamQueue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    public func stop() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        fallbackPoller?.stop()
        fallbackPoller = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        self.stream = nil
    }

    deinit {
        stop()
    }

    /// Coalesces bursts of events (multi-file writes) into one refresh.
    private func scheduleInboxChange() {
        pendingWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.delegate?.inboxDidChange()
        }
        pendingWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + 0.15, execute: work)
    }
}
#endif