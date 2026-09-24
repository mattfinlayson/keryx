#if os(macOS)
import AppKit
import KeryxKit

// MARK: - Configuration

let inboxURL: URL = {
    if let custom = ProcessInfo.processInfo.environment["KERYX_INBOX"], !custom.isEmpty {
        return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
    }
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("keryx-inbox", isDirectory: true)
}()

let viewerAppName: String? = ProcessInfo.processInfo.environment["KERYX_OPEN_APP"]

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = InboxController(
        scanner: DirectoryScanner(directory: inboxURL),
        watcher: PollingInboxWatcher(directory: inboxURL, interval: 2.0)
    )
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "✉"

        controller.onChange = { [weak self] in
            DispatchQueue.main.async { [weak self] in self?.render() }
        }
        controller.start()
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

    @objc func openInboxFolder() {
        NSWorkspace.shared.open(inboxURL)
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