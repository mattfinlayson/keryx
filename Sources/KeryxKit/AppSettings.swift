import Foundation

/// User-configurable app settings.
public struct AppSettings: Equatable, Sendable {
    public let inboxURL: URL?
    public let scanInterval: TimeInterval

    /// Fallback scan interval floor, in seconds (only used by polling
    /// watchers; event-driven watchers push immediately).
    public static let minimumScanInterval: TimeInterval = 0.5

    public static let `default` = AppSettings(inboxURL: nil, scanInterval: 2.0)

    public init(inboxURL: URL?, scanInterval: TimeInterval) {
        self.inboxURL = inboxURL
        self.scanInterval = max(AppSettings.minimumScanInterval, scanInterval)
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
    private static let scanIntervalKey = "scanInterval"

    public init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
    }

    public var settings: AppSettings {
        var inboxURL: URL?
        if let path = defaults.string(forKey: Self.inboxPathKey) {
            inboxURL = URL(fileURLWithPath: path)
        }
        var interval = AppSettings.default.scanInterval
        if defaults.object(forKey: Self.scanIntervalKey) != nil {
            interval = defaults.double(forKey: Self.scanIntervalKey)
        }
        return AppSettings(inboxURL: inboxURL, scanInterval: interval)
    }

    public func save(_ settings: AppSettings) {
        if let url = settings.inboxURL {
            defaults.set(url.path, forKey: Self.inboxPathKey)
        } else {
            defaults.removeObject(forKey: Self.inboxPathKey)
        }
        defaults.set(settings.scanInterval, forKey: Self.scanIntervalKey)
    }
}