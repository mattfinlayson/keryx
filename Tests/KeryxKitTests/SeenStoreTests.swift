import Testing
import Foundation
@testable import KeryxKit

@Suite("UserDefaultsSeenStore")
struct SeenStoreTests {

    private func makeStore() -> UserDefaultsSeenStore {
        UserDefaultsSeenStore(userDefaults: UserDefaults(suiteName: "keryx-seen-test-\(UUID().uuidString)")!)
    }

    @Test("round-trips the seen path set")
    func roundTrip() {
        let store = makeStore()

        #expect(store.seenPaths.isEmpty)

        store.save(["/tmp/a.md", "/tmp/b.md"])

        #expect(store.seenPaths == ["/tmp/a.md", "/tmp/b.md"])
    }

    @Test("overwrites the previous set")
    func overwrite() {
        let store = makeStore()
        store.save(["/tmp/a.md"])
        store.save(["/tmp/b.md"])

        #expect(store.seenPaths == ["/tmp/b.md"])
    }

    @Test("saving an empty set clears persisted state")
    func emptyClears() {
        let store = makeStore()
        store.save(["/tmp/a.md"])

        store.save([])

        #expect(store.seenPaths.isEmpty)
    }
}

@Suite("InboxController seen persistence")
struct InboxControllerPersistenceTests {

    private let dir: URL
    private let defaults: UserDefaults
    private var store: UserDefaultsSeenStore { UserDefaultsSeenStore(userDefaults: defaults) }

    init() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("keryx-persist-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: "keryx-persist-test-\(UUID().uuidString)")!
    }

    private func touch(_ name: String) throws {
        try "output".data(using: .utf8)!.write(to: dir.appendingPathComponent(name))
    }

    private func makeController() -> InboxController {
        InboxController(scanner: DirectoryScanner(directory: dir), seenStore: store)
    }

    /// macOS resolves /var → /private/var when scanning, so persisted paths
    /// may not byte-match the constructed URL path; compare on suffixes.
    private func containsPath(_ paths: Set<String>, _ name: String) -> Bool {
        paths.contains { $0.hasSuffix("/" + name) }
    }

    @Test("new files are unseen across controller recreation")
    func newFilesUnseen() throws {
        try touch("job-1.md")
        let controller = makeController()
        try controller.refresh()
        #expect(controller.state.badgeCount == 1)

        let relaunched = makeController()
        try relaunched.refresh()

        #expect(relaunched.state.badgeCount == 1)
        #expect(containsPath(relaunched.state.unseenPaths, "job-1.md"))
    }

    @Test("opened files stay read across controller recreation")
    func openedPersists() throws {
        try touch("job-1.md")
        try touch("job-2.md")
        let controller = makeController()
        try controller.refresh()
        controller.open(controller.state.entries.first { $0.name == "job-1.md" }!)
        #expect(containsPath(store.seenPaths, "job-1.md"))

        let relaunched = makeController()
        try relaunched.refresh()

        #expect(relaunched.state.badgeCount == 1)
        #expect(containsPath(relaunched.state.unseenPaths, "job-2.md"))
        #expect(!containsPath(relaunched.state.unseenPaths, "job-1.md"))
    }

    @Test("markAllAsRead persists the seen set")
    func markAllPersists() throws {
        try touch("job-1.md")
        let controller = makeController()
        try controller.refresh()

        controller.markAllAsRead()

        #expect(controller.state.badgeCount == 0)
        #expect(containsPath(store.seenPaths, "job-1.md"))
    }

    @Test("a seeded seen path is not re-flagged unseen")
    func seededSeenStaysRead() throws {
        defaults.set(["/gone/ghost.md"], forKey: "seenPaths")
        defaults.synchronize()

        let controller = makeController()
        try controller.refresh()

        #expect(controller.state.badgeCount == 0)
        #expect(controller.state.unseenPaths.isEmpty)
    }
}