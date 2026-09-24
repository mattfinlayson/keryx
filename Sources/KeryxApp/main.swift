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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UserDefaultsSettingsStore()
    let notifier = UserNotifier()
    let controller: InboxController
    lazy var settingsWindow = SettingsWindowController(store: store)
    var statusItem: NSStatusItem!

    override init() {
        let settings = store.settings
        let inbox = effectiveInboxURL(for: settings)
        controller = InboxController(
            scanner: DirectoryScanner(directory: inbox),
            watcherFactory: InboxWatchers.platformDefault,
            seenStore: UserDefaultsSeenStore()
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(
            at: effectiveInboxURL(for: store.settings), withIntermediateDirectories: true)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        notifier.activate()
        notifier.onNotificationOpen = { [weak self] url in
            DispatchQueue.main.async { [weak self] in self?.openAndMarkRead(url) }
        }
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
        controller.apply(settings: AppSettings(inboxURL: inbox, maxFileAge: settings.maxFileAge, openers: settings.openers))
        render()
    }

    func render() {
        renderMenuBarIcon()
        renderMenu()
    }

    private func renderMenuBarIcon() {
        let state = controller.state
        guard let button = statusItem.button else { return }
        let symbolName = state.badgeCount > 0 ? "tray.full" : "tray"
        let icon = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Keryx inbox")
        icon?.isTemplate = true
        button.image = icon
        button.imageHugsTitle = true
        if state.badgeCount > 0 {
            button.title = String(state.badgeCount)
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        } else {
            button.title = ""
        }
    }

    private func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private func accentDot() -> NSImage? {
        let size = NSSize(width: 9, height: 9)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.controlAccentColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Same footprint as the unseen dot, invisible — keeps read/unread rows
    /// text-aligned in the menu (items without images shift left).
    private func blankDot() -> NSImage? {
        NSImage(size: NSSize(width: 9, height: 9), flipped: false) { _ in true }
    }

    private func relativeTime(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func renderMenu() {
        let state = controller.state

        let menu = NSMenu()
        if let latest = state.latestEntry {
            let preview = NSMenuItem(
                title: "Latest: \(latest.name) · \(relativeTime(for: latest.modificationDate))",
                action: nil,
                keyEquivalent: ""
            )
            preview.isEnabled = false
            menu.addItem(preview)
        } else {
            let empty = NSMenuItem(title: "Inbox empty", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        menu.addItem(.separator())
        for entry in state.entries {
            let item = NSMenuItem(
                title: entry.name,
                action: #selector(openFile(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.image = state.unseenPaths.contains(entry.id) ? accentDot() : blankDot()
            item.representedObject = entry
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let markAll = NSMenuItem(
            title: "Mark All Read", action: #selector(markAllRead(_:)), keyEquivalent: "k"
        )
        markAll.keyEquivalentModifierMask = [.command, .shift]
        markAll.target = self
        markAll.image = symbol("checkmark.circle")
        markAll.isEnabled = state.badgeCount > 0
        menu.addItem(markAll)
        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.image = symbol("gearshape")
        menu.addItem(settingsItem)
        let aboutItem = NSMenuItem(
            title: "About Keryx", action: #selector(showAbout(_:)), keyEquivalent: ""
        )
        aboutItem.target = self
        aboutItem.image = symbol("info.circle")
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem(title: "Open Inbox Folder", action: #selector(openInboxFolder), keyEquivalent: "o"))
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Keryx", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.image = symbol("power")
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc func showAbout(_ sender: Any) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let alert = NSAlert()
        alert.messageText = "Keryx"
        alert.informativeText = """
        A native menubar inbox for agent and scheduled-job output.\n\n        Keryx watches a directory for new files, flags them unread, and opens them in your viewer with a click.\n\n        \(version.map { "Version \($0)" } ?? "Development build") · © 2026 Matthew Finlayson\n        github.com/mattfinlayson/keryx
        """
        alert.runModal()
    }

    @objc func openFile(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? FileEntry else { return }
        openAndMarkRead(entry.url)
        render()
    }

    /// Single source of truth for opening an inbox file: resolve the opener
    /// (extension rule → * rule → env override → OS default) and mark read.
    func openAndMarkRead(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        let opener = store.settings.opener(forExtension: ext, in: viewerAppName.map { ["*": $0] } ?? [:])
        if let appName = opener {
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = ["-a", appName, url.path]
            try? open.run()
        } else {
            NSWorkspace.shared.open(url)
        }
        if let entry = controller.state.entries.first(where: { $0.url == url }) {
            controller.open(entry)
        }
        render()
    }

    @objc func markAllRead(_ sender: Any) {
        controller.markAllAsRead()
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