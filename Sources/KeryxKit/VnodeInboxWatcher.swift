import Foundation
import Dispatch

/// Event-driven watcher backed by a vnode file-system source on the
/// directory descriptor. Push-based: fires the delegate the moment the
/// directory changes (file created, renamed, or deleted) — no polling.
/// macOS only (DispatchSource file-system sources are unavailable in
/// corelibs Dispatch on Linux).
#if os(macOS)
public final class VnodeInboxWatcher: InboxWatcher {
    public weak var delegate: InboxWatcherDelegate?

    private let directory: URL
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    public init(directory: URL) {
        self.directory = directory
    }

    public func start() {
        stop()
        let fd = open(directory.path, O_EVTONLY)
        guard fd != -1 else { return }
        fileDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .link],
            queue: .global(qos: .utility)
        )
        // The watched directory itself being moved/removed stops the stream;
        // re-arm so a recreated inbox is picked up again.
        source.setCancelHandler { [fd] in close(fd) }
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let mask = source.data
            self.delegate?.inboxDidChange()
            if mask.contains(.delete) || mask.contains(.rename) {
                self.restart()
            }
        }
        source.resume()
        self.source = source
    }

    public func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    private func restart() {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.stop()
            self?.start()
        }
    }
}
#endif