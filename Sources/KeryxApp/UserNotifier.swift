#if os(macOS)
import AppKit
import UserNotifications
import KeryxKit

/// Presents macOS user notifications for new inbox files.
final class UserNotifier: NSObject {
    private let center = UNUserNotificationCenter.current()

    func activate() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyNewFiles(_ files: [FileEntry]) {
        guard Bundle.main.bundleIdentifier != nil else { return } // no bundle: skip
        let content = UNMutableNotificationContent()
        content.title = files.count == 1 ? "New file in inbox" : "\(files.count) new files in inbox"
        content.body = files.map(\.name).joined(separator: ", ")
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
}

extension UserNotifier: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
#endif