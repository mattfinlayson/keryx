#if os(macOS)
import AppKit
import UserNotifications
import KeryxKit

/// Presents macOS user notifications for new inbox files and routes
/// notification taps back into the app (open + mark read).
final class UserNotifier: NSObject {
    static let payloadPathsKey = "keryx.filePaths"

    private let center = UNUserNotificationCenter.current()

    /// Called with the newest file path from the clicked notification.
    /// Invoked on the notification center's callback queue.
    var onNotificationOpen: ((URL) -> Void)?

    func activate() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyNewFiles(_ files: [FileEntry]) {
        guard Bundle.main.bundleIdentifier != nil, !files.isEmpty else { return } // no bundle: skip
        let content = UNMutableNotificationContent()
        content.title = files.count == 1 ? "New file in inbox" : "\(files.count) new files in inbox"
        content.body = files.map(\.name).joined(separator: ", ")
        content.sound = .default
        // Newest first so a tap opens the most recent file (origin AE2).
        content.userInfo = [Self.payloadPathsKey: files.map(\.url.path)]
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let paths = response.notification.request.content
            .userInfo[Self.payloadPathsKey] as? [String] ?? []
        if let newest = paths.first {
            onNotificationOpen?(URL(fileURLWithPath: newest))
        }
        completionHandler()
    }
}
#endif