import Foundation

/// Notified when the watched directory may have changed.
public protocol InboxWatcherDelegate: AnyObject {
    func inboxDidChange()
}

/// Watches the inbox directory for changes. The macOS shell can back this
/// with FSEvents/DispatchSource; tests and Linux use the polling
/// implementation.
public protocol InboxWatcher: AnyObject {
    var delegate: InboxWatcherDelegate? { get set }
    func start()
    func stop()
}

/// Simple cross-platform watcher that polls the directory at a fixed
/// interval. Stable and dependency-free; good enough for scheduled job
/// output that lands every few seconds or minutes.
public final class PollingInboxWatcher: InboxWatcher {
    public weak var delegate: InboxWatcherDelegate?

    private let directory: URL
    private let interval: TimeInterval
    private var timer: DispatchSourceTimer?

    public init(directory: URL, interval: TimeInterval = 2.0) {
        self.directory = directory
        self.interval = interval
    }

    public func start() {
        stop()
        let source = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        source.schedule(deadline: .now() + interval, repeating: interval)
        source.setEventHandler { [weak self] in
            self?.delegate?.inboxDidChange()
        }
        source.resume()
        timer = source
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }
}