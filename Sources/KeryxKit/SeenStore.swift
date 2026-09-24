import Foundation

/// Persists which inbox files have been seen (opened), so read state
/// survives relaunches. Paths are kept even after the file leaves the inbox;
/// a rewritten file re-enters the unseen set via its modification date.
public protocol SeenStore: AnyObject {
    var seenPaths: Set<String> { get }
    func save(_ paths: Set<String>)
}

/// Persists the seen set in `UserDefaults` (key: `seenPaths`).
public final class UserDefaultsSeenStore: SeenStore {
    private let defaults: UserDefaults
    private static let key = "seenPaths"

    public init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
    }

    public var seenPaths: Set<String> {
        let paths = defaults.stringArray(forKey: Self.key) ?? []
        return Set(paths)
    }

    public func save(_ paths: Set<String>) {
        if paths.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else {
            defaults.set(paths.sorted(), forKey: Self.key)
        }
    }
}