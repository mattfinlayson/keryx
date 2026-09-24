import Testing
import Foundation
@testable import KeryxKit

@Suite("DirectoryScanner")
struct DirectoryScannerTests {

    private let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("keryx-scanner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func touch(_ name: String, daysAgo: Double = 0) throws {
        let url = dir.appendingPathComponent(name)
        try "hello".data(using: .utf8)!.write(to: url)
        let date = Date().addingTimeInterval(-daysAgo * 86400)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    @Test("returns markdown files, newest first")
    func newestFirst() throws {
        try touch("old.md", daysAgo: 3)
        try touch("new.md", daysAgo: 0)
        try touch("mid.md", daysAgo: 1)

        let scanner = DirectoryScanner(directory: dir)
        let files = try scanner.scan()

        #expect(files.map(\.name) == ["new.md", "mid.md", "old.md"])
    }

    @Test("skips hidden files and directories")
    func skipsHidden() throws {
        try touch(".hidden.md")
        try touch("report.md")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: false)

        let files = try DirectoryScanner(directory: dir).scan()

        #expect(files.map(\.name) == ["report.md"])
    }

    @Test("includes files inside subdirectories (agents write to job folders)")
    func includesSubdirectoryFiles() throws {
        let subdir = dir.appendingPathComponent("job-2026-09-24")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "output".data(using: .utf8)!.write(to: subdir.appendingPathComponent("report.md"))
        try "root".data(using: .utf8)!.write(to: dir.appendingPathComponent("top.md"))

        let files = try DirectoryScanner(directory: dir).scan()

        #expect(files.map(\.name).sorted() == ["report.md", "top.md"])
    }

    @Test("scanning a nonexistent directory throws")
    func nonexistentThrows() throws {
        let scanner = DirectoryScanner(directory: dir.appendingPathComponent("nope"))

        #expect(throws: (any Error).self) {
            try scanner.scan()
        }
    }
}