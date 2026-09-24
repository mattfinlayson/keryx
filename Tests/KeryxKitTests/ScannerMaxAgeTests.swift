import Testing
import Foundation
@testable import KeryxKit

@Suite("DirectoryScanner maxFileAge")
struct ScannerMaxAgeTests {

    private let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("keryx-age-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func touch(_ name: String, daysAgo: Double) throws {
        let url = dir.appendingPathComponent(name)
        try "hello".data(using: .utf8)!.write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-daysAgo * 86400)],
            ofItemAtPath: url.path
        )
    }

    @Test("nil maxFileAge shows all files")
    func noFilterShowsAll() throws {
        try touch("old.md", daysAgo: 30)
        try touch("fresh.md", daysAgo: 0)

        let files = try DirectoryScanner(directory: dir).scan()

        #expect(files.map(\.name).sorted() == ["fresh.md", "old.md"])
    }

    @Test("files older than maxFileAge are excluded")
    func excludesOldFiles() throws {
        try touch("ancient.md", daysAgo: 30)
        try touch("yesterday.md", daysAgo: 1)
        try touch("fresh.md", daysAgo: 0)

        let scanner = DirectoryScanner(directory: dir, maxFileAge: 2 * 86400)
        let files = try scanner.scan()

        #expect(files.map(\.name) == ["fresh.md", "yesterday.md"])
    }

    @Test("a re-touched old file reappears (new mtime)")
    func retouchedReappears() throws {
        let url = dir.appendingPathComponent("old.md")
        try "v1".data(using: .utf8)!.write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-30 * 86400)],
            ofItemAtPath: url.path
        )
        let scanner = DirectoryScanner(directory: dir, maxFileAge: 86400)
        #expect(try scanner.scan().isEmpty)

        // Agent rewrites the old file with fresh output.
        try "v2".data(using: .utf8)!.write(to: url)

        #expect(try scanner.scan().map(\.name) == ["old.md"])
    }
}