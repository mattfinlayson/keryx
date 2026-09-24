import Foundation

/// State machine for the inbox: which files are present and which have not
/// been seen (opened) yet. Drives the menubar badge and menu highlighting.
/// `seenPaths` tracks files opened at least once so read state can be
/// persisted across relaunches; a rewritten file re-enters the unseen set
/// via its newer modification date.
public struct InboxState: Sendable {
    public private(set) var entries: [FileEntry] = []
    public private(set) var unseenPaths: Set<String> = []
    public private(set) var seenPaths: Set<String> = []

    public init(seenPaths: Set<String> = []) {
        self.seenPaths = seenPaths
    }

    /// Number of unseen files; used for the menubar badge.
    public var badgeCount: Int { unseenPaths.count }

    /// The most recently modified entry, or nil when the inbox is empty.
    public var latestEntry: FileEntry? { entries.first }

    /// Adds or updates an entry. A brand-new path is marked unseen unless it
    /// is already in the seen set (persisted read state). A path with a
    /// newer modification date is re-marked unseen (new content counts as
    /// new). Returns true if the state changed.
    @discardableResult
    public mutating func insert(_ entry: FileEntry) -> Bool {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            let isUpdate = entries[index].modificationDate < entry.modificationDate
            guard isUpdate else { return false }
            entries[index] = entry
            // New content counts as new: re-flag it unseen.
            unseenPaths.insert(entry.id)
            seenPaths.remove(entry.id)
        } else {
            entries.append(entry)
            if !seenPaths.contains(entry.id) {
                unseenPaths.insert(entry.id)
            }
        }
        entries.sort { $0.modificationDate > $1.modificationDate }
        return true
    }

    /// Marks every file as seen (opened). Returns true if the state changed.
    @discardableResult
    public mutating func markAllOpened() -> Bool {
        guard !unseenPaths.isEmpty else { return false }
        seenPaths.formUnion(unseenPaths)
        unseenPaths.removeAll()
        return true
    }

    /// Marks a file as seen (opened). Returns true if the state changed.
    @discardableResult
    public mutating func markOpened(path: String) -> Bool {
        guard entries.contains(where: { $0.id == path }), unseenPaths.remove(path) != nil else {
            return false
        }
        seenPaths.insert(path)
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