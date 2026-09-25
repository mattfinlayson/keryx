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
        let icon = caduceusImage()
        button.image = icon
        button.imageHugsTitle = true
        if state.badgeCount > 0 {
            button.title = String(state.badgeCount)
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        } else {
            button.title = ""
        }
    }

    /// Caduceus drawn as a monochrome template image (tints with the menu
    /// bar). Geometry designed in a 16×16 unit space, y-down; validated by
    /// rendering the same paths off-platform before porting.
    private func caduceusImage() -> NSImage? {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: true) { _ in
            self.drawCaduceus(px: 16, color: .black)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Keryx inbox"
        return image
    }

    private func drawCaduceus(px: CGFloat, color: NSColor) {
        let s = px / 16.0
        color.setStroke()
        color.setFill()

        func path(_ points: [(CGFloat, CGFloat)], _ width: CGFloat) {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: points[0].0 * s, y: points[0].1 * s))
            for point in points.dropFirst() {
                p.line(to: NSPoint(x: point.0 * s, y: point.1 * s))
            }
            p.lineWidth = width * s
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            p.stroke()
        }
        func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
            NSBezierPath(ovalIn: NSRect(x: (x - r) * s, y: (y - r) * s,
                                        width: 2 * r * s, height: 2 * r * s)).fill()
        }
        func snake(phase: Double) -> [(CGFloat, CGFloat)] {
            let n = 40
            return (0...n).map { i in
                let t = Double(i) / Double(n)
                let y = 5.4 + t * 7.6
                let x = 8.0 + 2.1 * sin(t * .pi * 2.1 + phase)
                return (CGFloat(x), CGFloat(y))
            }
        }

        dot(8, 1.7, 1.05)                       // ball
        path([(8, 2.9), (8, 15.1)], 1.35)       // staff
        for side in [-1.0, 1.0] {               // wings
            path([(8 + side * 0.6, 3.6), (8 + side * 3.4, 2.2), (8 + side * 4.9, 1.5)], 1.1)
            path([(8 + side * 0.6, 4.8), (8 + side * 2.9, 3.9), (8 + side * 4.3, 3.9)], 1.1)
        }
        let snakeA = snake(phase: 0)            // two snakes, mirrored weaves
        let snakeB = snake(phase: .pi)
        path(snakeA, 1.15)
        path(snakeB, 1.15)
        dot(snakeA.last!.0 + 0.35, snakeA.last!.1 + 0.1, 0.8)  // heads
        dot(snakeB.last!.0 - 0.35, snakeB.last!.1 + 0.1, 0.8)
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
                title: displayName(for: entry),
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

    /// Files in inbox subdirectories display as relative paths so nested
    /// files from different jobs are distinguishable.
    private func displayName(for entry: FileEntry) -> String {
        let inboxPath = effectiveInboxURL(for: store.settings).path
        let path = entry.url.path
        guard path.hasPrefix(inboxPath + "/") else { return entry.name }
        return String(path.dropFirst(inboxPath.count + 1))
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