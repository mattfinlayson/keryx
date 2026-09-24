import Foundation

/// Scans the inbox directory and returns the files in it, newest first.
/// Hidden files (dotfiles) and subdirectories are skipped.
public struct DirectoryScanner {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
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

        var entries: [FileEntry] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(attributes))
            if values.isDirectory == true { continue }
            let modified = values.contentModificationDate ?? Date.distantPast
            entries.append(FileEntry(url: url, modificationDate: modified))
        }
        entries.sort { $0.modificationDate > $1.modificationDate }
        return entries
    }
}