import Testing
import Foundation
@testable import KeryxKit

@Suite("InboxController settings and notifications")
struct InboxControllerSettingsTests {

    private let dir: URL
    private let controller: InboxController
    private let settingsStore: InMemorySettingsStore

    init() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("keryx-ctl2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        settingsStore = InMemorySettingsStore(
            settings: AppSettings(inboxURL: dir)
        )
        controller = InboxController(scanner: DirectoryScanner(directory: dir))
        controller.apply(settings: settingsStore.settings)
    }

    private func touch(_ name: String) throws {
        try "output".data(using: .utf8)!.write(to: dir.appendingPathComponent(name))
    }

    @Test("apply(settings:) re-points the controller at the new inbox")
    func repointsInbox() throws {
        let newDir = dir.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        try "output".data(using: .utf8)!.write(to: newDir.appendingPathComponent("moved-job.md"))

        controller.apply(settings: AppSettings(inboxURL: newDir))
        try controller.refresh()

        #expect(controller.state.entries.map(\.name) == ["moved-job.md"])
    }

    @Test("apply(settings:) with maxFileAge drops files older than the cutoff")
    func ageFilterDropsOldFiles() throws {
        let url = dir.appendingPathComponent("ancient.md")
        try "output".data(using: .utf8)!.write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-30 * 86400)],
            ofItemAtPath: url.path
        )
        try controller.refresh()
        #expect(controller.state.entries.count == 1)

        controller.apply(settings: AppSettings(inboxURL: dir, maxFileAge: 86400))

        #expect(controller.state.entries.isEmpty)
        #expect(controller.state.badgeCount == 0)
    }

    @Test("onNewFiles fires once per newly-unseen file")
    func notifiesOnNewFiles() throws {
        var notified: [String] = []
        controller.onNewFiles = { notified.append(contentsOf: $0.map(\.name)) }

        try touch("job-1.md")
        try controller.refresh()
        // Second refresh with no changes must not re-notify.
        try controller.refresh()

        #expect(notified == ["job-1.md"])
    }

    @Test("onNewFiles fires again when a file is updated with new content")
    func notifiesAgainOnUpdate() throws {
        var notified: [String] = []
        controller.onNewFiles = { notified.append(contentsOf: $0.map(\.name)) }

        try touch("job-1.md")
        try controller.refresh()

        let url = dir.appendingPathComponent("job-1.md")
        try "updated".data(using: .utf8)!.write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)],
            ofItemAtPath: url.path
        )
        try controller.refresh()

        #expect(notified == ["job-1.md", "job-1.md"])
    }

    @Test("markAllAsRead clears the badge without firing onNewFiles")
    func markAllAsRead() throws {
        var notified: [String] = []
        controller.onNewFiles = { notified.append(contentsOf: $0.map(\.name)) }
        var changeCount = 0
        controller.onChange = { changeCount += 1 }

        try touch("job-1.md")
        try touch("job-2.md")
        try controller.refresh()
        notified.removeAll()
        let changesBefore = changeCount

        controller.markAllAsRead()

        #expect(controller.state.badgeCount == 0)
        #expect(controller.state.entries.count == 2)
        #expect(changeCount > changesBefore)
        #expect(notified.isEmpty)
    }

    @Test("opened files do not re-notify on later refreshes")
    func noNotifyAfterOpen() throws {
        var notified: [String] = []
        controller.onNewFiles = { notified.append(contentsOf: $0.map(\.name)) }

        try touch("job-1.md")
        try controller.refresh()
        controller.open(try #require(controller.state.entries.first))
        notified.removeAll()
        try controller.refresh()

        #expect(notified.isEmpty)
    }
}