#if os(macOS)
import AppKit
import KeryxKit

// MARK: - Configuration

let envInboxOverride: URL? = ProcessInfo.processInfo.environment["KERYX_INBOX"]
    .flatMap { value in
        let expanded = (value as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

let viewerAppName: String? = ProcessInfo.processInfo.environment["KERYX_OPEN_APP"]

let defaultInbox = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("keryx-inbox", isDirectory: true)

/// The inbox the app should use given stored settings (env var wins).
func effectiveInboxURL(for settings: AppSettings) -> URL {
    envInboxOverride ?? settings.inboxURL ?? defaultInbox
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UserDefaultsSettingsStore()
    let notifier = UserNotifier()
    let controller: InboxController
    lazy var settingsWindow = SettingsWindowController(store: store)
    var statusItem: NSStatusItem!

    init() {
        let settings = store.settings
        let inbox = effectiveInboxURL(for: settings)
        controller = InboxController(
            scanner: DirectoryScanner(directory: inbox),
            watcherFactory: InboxWatchers.platformDefault
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(
            at: effectiveInboxURL(for: store.settings), withIntermediateDirectories: true)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "✉"

        notifier.activate()
        controller.onNewFiles = { [notifier] files in
            notifier.notifyNewFiles(files)
        }
        controller.onChange = { [weak self] in
            DispatchQueue.main.async { [weak self] in self?.render() }
        }
        settingsWindow.onApply = { [weak self] settings in
            self?.apply(settings)
        }

        controller.apply(settings: store.settings)
        controller.start()
        render()
    }

    func apply(_ settings: AppSettings) {
        let inbox = effectiveInboxURL(for: settings)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        controller.apply(settings: AppSettings(inboxURL: inbox, scanInterval: settings.scanInterval))
        render()
    }

    func render() {
        let state = controller.state
        statusItem.button?.title = state.badgeCount > 0 ? "✉ \(state.badgeCount)" : "✉"

        let menu = NSMenu()
        if state.entries.isEmpty {
            let empty = NSMenuItem(title: "Inbox empty", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for entry in state.entries {
                let item = NSMenuItem(
                    title: (state.unseenPaths.contains(entry.id) ? "● " : "") + entry.name,
                    action: #selector(openFile(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = entry
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem(title: "Open Inbox Folder", action: #selector(openInboxFolder), keyEquivalent: "o"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Keryx", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func openFile(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? FileEntry else { return }
        controller.open(entry)
        if let appName = viewerAppName {
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = ["-a", appName, entry.url.path]
            try? open.run()
        } else {
            NSWorkspace.shared.open(entry.url)
        }
        render()
    }

    @objc func showSettings(_ sender: Any) {
        settingsWindow.show()
    }

    @objc func openInboxFolder() {
        NSWorkspace.shared.open(effectiveInboxURL(for: store.settings))
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menubar-only, no Dock icon
app.run()
#else
print("KeryxApp is the macOS menubar shell; on Linux this target is a no-op.")
print("Run `swift test` to exercise the platform-independent core (KeryxKit).")
#endif