import Testing
import Foundation
@testable import KeryxKit

@Suite("InboxController")
struct InboxControllerTests {

    private let dir: URL
    private let watcher: PollingInboxWatcher
    private let controller: InboxController

    init() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("keryx-ctl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        watcher = PollingInboxWatcher(directory: dir, interval: 0.05)
        controller = InboxController(
            scanner: DirectoryScanner(directory: dir),
            watcher: watcher
        )
    }

    private func touch(_ name: String) throws {
        try "output".data(using: .utf8)!.write(to: dir.appendingPathComponent(name))
    }

    @Test("refresh pulls files from disk with unseen badge")
    func refreshScans() throws {
        try touch("job-1.md")

        try controller.refresh()

        #expect(controller.state.entries.map(\.name) == ["job-1.md"])
        #expect(controller.state.badgeCount == 1)
    }

    @Test("watcher change triggers refresh and onChange")
    func watcherTriggersRefresh() async throws {
        try controller.refresh()

        await try confirmation("onChange called with new file seen", expectedCount: 1...) { confirm in
            controller.onChange = { confirm() }
            controller.start()
            defer { controller.stop() }

            try touch("job-2.md")
            try await Task.sleep(for: .milliseconds(300))
        }

        #expect(controller.state.entries.map(\.name).contains("job-2.md"))
    }

    @Test("open marks the entry seen and drops the badge")
    func openDropsBadge() throws {
        try touch("job-1.md")
        try controller.refresh()
        let entry = try #require(controller.state.entries.first)

        controller.open(entry)

        #expect(controller.state.badgeCount == 0)
        #expect(controller.state.entries.count == 1)
    }

    @Test("files removed from disk disappear on next refresh")
    func deletedFilesDisappear() throws {
        try touch("job-1.md")
        try controller.refresh()
        try FileManager.default.removeItem(at: dir.appendingPathComponent("job-1.md"))

        try controller.refresh()

        #expect(controller.state.entries.isEmpty)
        #expect(controller.state.badgeCount == 0)
    }
}

