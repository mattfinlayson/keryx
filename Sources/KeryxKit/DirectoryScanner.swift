import Foundation

/// Scans the inbox directory and returns the files in it, newest first.
/// Hidden files (dotfiles) and subdirectories are skipped. When `maxFileAge`
/// is set, files whose modification date is older than the cutoff are
/// excluded (useful when pointing the inbox at a directory that already
/// contains a long history of output).
public struct DirectoryScanner {
    public let directory: URL
    public let maxFileAge: TimeInterval?

    public init(directory: URL, maxFileAge: TimeInterval? = nil) {
        self.directory = directory
        self.maxFileAge = maxFileAge
    }

    public func scan() throws -> [FileEntry] {
        let attributes: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CocoaError(.fileReadNoSuchFile,
                             userInfo: [NSFilePathErrorKey: directory.path])
        }
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: attributes,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        guard let enumerator else { return [] }

        var entries: [FileEntry] = []
        let cutoff = maxFileAge.map { Date().addingTimeInterval(-$0) }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(attributes))
            if values.isDirectory == true { continue }
            let modified = values.contentModificationDate ?? Date.distantPast
            if let cutoff, modified < cutoff { continue }
            entries.append(FileEntry(url: url, modificationDate: modified))
        }
        entries.sort { $0.modificationDate > $1.modificationDate }
        return entries
    }
}