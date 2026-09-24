import Testing
import Foundation
@testable import KeryxKit

@Suite("InboxState")
struct InboxStateTests {

    private func entry(_ name: String, modified: Date) -> FileEntry {
        FileEntry(url: URL(fileURLWithPath: "/tmp/inbox/\(name)"), modificationDate: modified)
    }

    @Test("new file is unseen and contributes to badge count")
    mutating func newFileIsUnseen() {
        var state = InboxState()
        state.insert(entry("report.md", modified: Date(timeIntervalSince1970: 100)))

        #expect(state.badgeCount == 1)
        #expect(state.unseenPaths.contains("/tmp/inbox/report.md"))
    }

    @Test("re-inserting a known file does not re-mark it unseen")
    mutating func reinsertIsIdempotent() {
        var state = InboxState()
        let when = Date(timeIntervalSince1970: 100)
        state.insert(entry("report.md", modified: when))
        state.markOpened(path: "/tmp/inbox/report.md")

        // Same file re-scanned: still seen.
        state.insert(entry("report.md", modified: when))

        #expect(state.badgeCount == 0)
        #expect(state.entries.count == 1)
    }

    @Test("re-inserting a file with a newer modification date re-marks it unseen")
    mutating func updatedFileIsUnseenAgain() {
        var state = InboxState()
        state.insert(entry("report.md", modified: Date(timeIntervalSince1970: 100)))
        state.markOpened(path: "/tmp/inbox/report.md")

        // Agent overwrote the file with new output.
        state.insert(entry("report.md", modified: Date(timeIntervalSince1970: 200)))

        #expect(state.badgeCount == 1)
        #expect(state.unseenPaths.contains("/tmp/inbox/report.md"))
    }

    @Test("markOpened clears the unseen flag and the badge")
    mutating func openClearsUnseen() {
        var state = InboxState()
        state.insert(entry("a.md", modified: Date(timeIntervalSince1970: 100)))
        state.insert(entry("b.md", modified: Date(timeIntervalSince1970: 200)))

        let changed = state.markOpened(path: "/tmp/inbox/a.md")

        #expect(changed)
        #expect(state.badgeCount == 1)
        #expect(state.unseenPaths == ["/tmp/inbox/b.md"])
    }

    @Test("markOpened on an unknown path is a no-op")
    mutating func openUnknownPathIsNoOp() {
        var state = InboxState()
        state.insert(entry("a.md", modified: Date(timeIntervalSince1970: 100)))

        let changed = state.markOpened(path: "/tmp/inbox/ghost.md")

        #expect(!changed)
        #expect(state.badgeCount == 1)
    }

    @Test("sync removes entries for files that disappeared from disk")
    mutating func syncRemovesMissingFiles() {
        var state = InboxState()
        state.insert(entry("a.md", modified: Date(timeIntervalSince1970: 100)))
        state.insert(entry("b.md", modified: Date(timeIntervalSince1970: 200)))

        let changed = state.sync(existingPaths: ["/tmp/inbox/b.md"])

        #expect(changed)
        #expect(state.entries.map(\.name) == ["b.md"])
        #expect(state.badgeCount == 1)
    }

    @Test("entries are sorted newest first")
    mutating func sortedNewestFirst() {
        var state = InboxState()
        state.insert(entry("old.md", modified: Date(timeIntervalSince1970: 100)))
        state.insert(entry("new.md", modified: Date(timeIntervalSince1970: 200)))
        state.insert(entry("mid.md", modified: Date(timeIntervalSince1970: 150)))

        #expect(state.entries.map(\.name) == ["new.md", "mid.md", "old.md"])
    }
}