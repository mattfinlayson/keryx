import Testing
import Foundation
@testable import KeryxKit

@Suite("PollingInboxWatcher")
struct PollingInboxWatcherTests {

    private let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("keryx-watcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    @Test("notifies the delegate when a file appears while running")
    func notifiesOnNewFile() async throws {
        let watcher = PollingInboxWatcher(directory: dir, interval: 0.05)

        await try confirmation("delegate notified at least once", expectedCount: 1...) { confirm in
            final class Recorder: InboxWatcherDelegate {
                let confirm: Confirmation
                init(_ confirm: Confirmation) { self.confirm = confirm }
                func inboxDidChange() { confirm() }
            }

            let recorder = Recorder(confirm)
            watcher.delegate = recorder
            watcher.start()
            defer { watcher.stop() }

            try "output".data(using: .utf8)!.write(to: dir.appendingPathComponent("job-1.md"))
            try await Task.sleep(for: .milliseconds(300))
        }
    }

    @Test("stops notifying after stop()")
    func stopsAfterStop() async throws {
        let watcher = PollingInboxWatcher(directory: dir, interval: 0.05)

        final class Counter: InboxWatcherDelegate {
            private let lock = NSLock()
            private var _count = 0
            var count: Int { lock.withLock { _count } }
            func inboxDidChange() { lock.withLock { _count += 1 } }
        }

        let counter = Counter()
        watcher.delegate = counter
        watcher.start()
        try "output".data(using: .utf8)!.write(to: dir.appendingPathComponent("job-1.md"))
        try await Task.sleep(for: .milliseconds(200))
        watcher.stop()

        // Let any in-flight handler settle before taking the baseline.
        try await Task.sleep(for: .milliseconds(250))
        let stable = counter.count
        try await Task.sleep(for: .milliseconds(250))

        #expect(counter.count == stable)
        #expect(stable >= 1)
    }
}