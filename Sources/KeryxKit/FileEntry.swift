import Foundation

/// A file in the inbox directory.
public struct FileEntry: Hashable, Identifiable, Sendable {
    public let url: URL
    public let modificationDate: Date

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }

    public init(url: URL, modificationDate: Date) {
        self.url = url
        self.modificationDate = modificationDate
    }
}