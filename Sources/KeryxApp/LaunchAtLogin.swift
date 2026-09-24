#if os(macOS)
import Foundation
import ServiceManagement

/// Wraps SMAppService for the "Launch at Login" toggle. Availability and
/// errors are surfaced to the caller so the shell can show meaningful UI.
@MainActor
enum LaunchAtLogin {
    /// Login items require the app to run from a bundle (a bare
    /// `.build/release/KeryxApp` binary has no bundle identity).
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func enable() throws {
        try SMAppService.mainApp.register()
    }

    static func disable() throws {
        try SMAppService.mainApp.unregister()
    }
}
#endif