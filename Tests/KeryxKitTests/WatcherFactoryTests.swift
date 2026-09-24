import Testing
import Foundation
@testable import KeryxKit

@Suite("InboxWatchers.platformDefault")
struct WatcherFactoryTests {

    private let dir = URL(fileURLWithPath: "/tmp/keryx-factory")

    #if os(Linux)
    @Test("Linux falls back to interval polling")
    func linuxUsesPolling() {
        let watcher = InboxWatchers.platformDefault(directory: dir, interval: 3.0)

        #expect(watcher is PollingInboxWatcher)
    }
    #endif
}