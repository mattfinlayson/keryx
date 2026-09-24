import Foundation

/// State machine for the inbox: which files are present and which have not
/// been seen (opened) yet. Drives the menubar badge and menu highlighting.
public struct InboxState: Sendable {
    public private(set) var entries: [FileEntry] = []
    public private(set) var unseenPaths: Set<String> = []

    public init() {}

    /// Number of unseen files; used for the menubar badge.
    public var badgeCount: Int { unseenPaths.count }

    /// Adds or updates an entry. A brand-new path is marked unseen.
    /// Returns true if the state changed.
    @discardableResult
    public mutating func insert(_ entry: FileEntry) -> Bool {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            let isUpdate = entries[index].modificationDate < entry.modificationDate
            guard isUpdate else { return false }
            entries[index] = entry
            // New content counts as new: re-flag it unseen.
            unseenPaths.insert(entry.id)
        } else {
            entries.append(entry)
            unseenPaths.insert(entry.id)
        }
        entries.sort { $0.modificationDate > $1.modificationDate }
        return true
    }

    /// Marks every file as seen (opened). Returns true if the state changed.
    @discardableResult
    public mutating func markAllOpened() -> Bool {
        guard !unseenPaths.isEmpty else { return false }
        unseenPaths.removeAll()
        return true
    }

    /// Marks a file as seen (opened). Returns true if the state changed.
    @discardableResult
    public mutating func markOpened(path: String) -> Bool {
        guard entries.contains(where: { $0.id == path }), unseenPaths.remove(path) != nil else {
            return false
        }
        return true
    }

    /// Drops entries whose paths are no longer present on disk.
    /// Returns true if the state changed.
    @discardableResult
    public mutating func sync(existingPaths: [String]) -> Bool {
        let present = Set(existingPaths)
        let before = entries
        entries = entries.filter { present.contains($0.id) }
        unseenPaths.formIntersection(present)
        return before.count != entries.count
    }
}