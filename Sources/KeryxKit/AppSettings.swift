import Foundation

/// User-configurable app settings.
public struct AppSettings: Equatable, Sendable {
    /// nil means "use the platform default inbox".
    public let inboxURL: URL?
    /// Files modified longer ago than this are ignored entirely.
    /// nil means unlimited.
    public let maxFileAge: TimeInterval?
    /// File extension (lowercased, without dot) -> application name or path
    /// used to open matching files, overriding the OS default handler.
    public let openers: [String: String]

    public static let `default` = AppSettings(inboxURL: nil, maxFileAge: nil, openers: [:])

    public init(inboxURL: URL?, maxFileAge: TimeInterval? = nil, openers: [String: String] = [:]) {
        self.inboxURL = inboxURL
        self.maxFileAge = maxFileAge
        // Normalize keys so "*.md", ".MD", and "md" are the same rule;
        // a bare "*" is kept as the all-files fallback.
        var normalized: [String: String] = [:]
        for (extension_, app) in openers {
            if let key = Self.normalizeOpenerKey(extension_) {
                normalized[key] = app
            }
        }
        self.openers = normalized
    }

    /// The app set for this extension, falling back to a `*` (all files)
    /// rule. `in` lets callers overlay additional rules (e.g. env overrides).
    public func opener(forExtension extension_: String, in extra: [String: String] = [:]) -> String? {
        let candidates: [String: String] = extra.merging(openers) { _, new in new }
        var key = extension_.lowercased()
        if key.hasPrefix(".") { key = String(key.dropFirst()) }
        guard !key.isEmpty else { return nil }
        return candidates[key] ?? candidates["*"]
    }

    private static func normalizeOpenerKey(_ raw: String) -> String? {
        var key = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if key.hasPrefix("*.") { key = String(key.dropFirst(2)) }
        else if key.hasPrefix(".") { key = String(key.dropFirst(1)) }
        if key.isEmpty || key == "*" { return raw.trimmingCharacters(in: .whitespaces) == "*" ? "*" : nil }
        return key
    }
}

/// Persists app settings.
public protocol SettingsStore: AnyObject {
    var settings: AppSettings { get }
    func save(_ settings: AppSettings)
}

/// Non-persisting store; useful for tests and previews.
public final class InMemorySettingsStore: SettingsStore {
    public private(set) var settings: AppSettings

    public init(settings: AppSettings = .default) {
        self.settings = settings
    }

    public func save(_ settings: AppSettings) {
        self.settings = settings
    }
}

/// Persists settings in `UserDefaults` under the `keryx` domain.
public final class UserDefaultsSettingsStore: SettingsStore {
    private let defaults: UserDefaults

    private static let inboxPathKey = "inboxPath"
    private static let maxFileAgeKey = "maxFileAge"
    private static let openersKey = "openers"

    public init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
    }

    public var settings: AppSettings {
        var inboxURL: URL?
        if let path = defaults.string(forKey: Self.inboxPathKey) {
            inboxURL = URL(fileURLWithPath: path)
        }
        var maxFileAge: TimeInterval?
        if defaults.object(forKey: Self.maxFileAgeKey) != nil {
            let value = defaults.double(forKey: Self.maxFileAgeKey)
            maxFileAge = value > 0 ? value : nil
        }
        var openers: [String: String] = [:]
        if let stored = defaults.dictionary(forKey: Self.openersKey) as? [String: String] {
            openers = stored
        }
        return AppSettings(inboxURL: inboxURL, maxFileAge: maxFileAge, openers: openers)
    }

    public func save(_ settings: AppSettings) {
        if let url = settings.inboxURL {
            defaults.set(url.path, forKey: Self.inboxPathKey)
        } else {
            defaults.removeObject(forKey: Self.inboxPathKey)
        }
        if let maxFileAge = settings.maxFileAge {
            defaults.set(maxFileAge, forKey: Self.maxFileAgeKey)
        } else {
            defaults.removeObject(forKey: Self.maxFileAgeKey)
        }
        if settings.openers.isEmpty {
            defaults.removeObject(forKey: Self.openersKey)
        } else {
            defaults.set(settings.openers, forKey: Self.openersKey)
        }
    }
}