#if os(macOS)
import AppKit
import UniformTypeIdentifiers
import KeryxKit

/// Settings window: pick the inbox directory, hide files older than a
/// cutoff, and map file extensions to specific applications. Changes apply
/// live (no OK/Cancel), matching macOS conventions.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onApply: ((AppSettings) -> Void)?

    private let store: SettingsStore
    private let pathField = NSTextField()
    private let agePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let openersSummary = NSTextField(labelWithString: "")
    private let extensionField = NSTextField()
    private let openerAppLabel = NSTextField(labelWithString: "default app")
    private let removeRuleButton = NSButton(title: "Remove Rule", target: nil, action: nil)

    /// (display label, seconds) pairs; seconds nil = no age limit.
    private static let ageOptions: [(String, TimeInterval?)] = [
        ("Off", nil),
        ("1 hour", 3600),
        ("3 hours", 3 * 3600),
        ("6 hours", 6 * 3600),
        ("12 hours", 12 * 3600),
        ("1 day", 86400),
        ("2 days", 2 * 86400),
        ("3 days", 3 * 86400),
        ("7 days", 7 * 86400),
        ("14 days", 14 * 86400),
    ]

    init(store: SettingsStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 210),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Keryx Settings"
        window.center()
        super.init(window: window)
        window.delegate = self
        buildLayout()
        refreshFromStore()
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        refreshFromStore()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Layout

    private func buildLayout() {
        guard let content = window?.contentView else { return }

        // Inbox row
        let inboxLabel = NSTextField(labelWithString: "Inbox folder:")
        pathField.isEditable = false
        pathField.lineBreakMode = .byTruncatingHead
        let chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseInbox(_:)))
        chooseButton.bezelStyle = .rounded
        let inboxRow = row(views: [inboxLabel, pathField, chooseButton])
        pathField.setContentHuggingPriority(.init(1), for: .horizontal)

        // Age row
        let ageLabel = NSTextField(labelWithString: "Ignore files older than:")
        for (title, seconds) in Self.ageOptions {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = seconds
            agePopup.menu?.addItem(item)
        }
        agePopup.target = self
        agePopup.action = #selector(ageChanged(_:))
        let ageRow = row(views: [ageLabel, agePopup])

        // Opener rules row
        let openersTitle = NSTextField(labelWithString: "Open files ending in:")
        extensionField.placeholderString = "e.g. md or *.md"
        extensionField.target = self
        extensionField.action = #selector(openersEdited(_:))
        openerAppLabel.lineBreakMode = .byTruncatingMiddle
        let chooseAppButton = NSButton(title: "Choose App…", target: self, action: #selector(chooseOpenerApp(_:)))
        chooseAppButton.bezelStyle = .rounded
        removeRuleButton.bezelStyle = .rounded
        removeRuleButton.target = self
        removeRuleButton.action = #selector(removeRule(_:))
        let openersRow = row(views: [openersTitle, extensionField, openerAppLabel, chooseAppButton, removeRuleButton])
        extensionField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        openersSummary.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        openersSummary.textColor = .secondaryLabelColor

        let column = NSStackView(views: [inboxRow, ageRow, openersRow, openersSummary])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(column)

        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            column.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            pathField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])
    }

    private func row(views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 8
        return stack
    }

    // MARK: State sync

    private func refreshFromStore() {
        let settings = store.settings
        pathField.stringValue = effectiveInboxURL(for: settings).path

        let age = settings.maxFileAge
        let index = Self.ageOptions.firstIndex { $0.1 != nil && $0.1 == age } ?? (age == nil ? 0 : 1)
        agePopup.selectItem(at: index)

        updateOpenersUI(with: settings)
    }

    private func updateOpenersUI(with settings: AppSettings) {
        let ext = normalizedExtension()
        if let app = settings.openers[ext] {
            openerAppLabel.stringValue = app
        } else {
            openerAppLabel.stringValue = "default app"
        }
        removeRuleButton.isEnabled = !settings.openers.isEmpty
        let summary = settings.openers
            .sorted { $0.key < $1.key }
            .map { key, app in
                key == "*" ? "* (all files) → \(app)" : ".\(key) → \(app)"
            }
            .joined(separator: "   ")
        openersSummary.stringValue = summary.isEmpty ? "No overrides — all files open with the OS default app." : summary
        // Prefill the extension field with the first rule when empty.
        if extensionField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty,
           let first = settings.openers.keys.sorted().first {
            extensionField.stringValue = first
        }
    }

    private func normalizedExtension() -> String {
        var ext = extensionField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        if ext.hasPrefix(".") { ext = String(ext.dropFirst()) }
        return ext
    }

    private func apply() {
        let settings = AppSettings(
            inboxURL: URL(fileURLWithPath: pathField.stringValue, isDirectory: true),
            maxFileAge: Self.ageOptions[min(agePopup.indexOfSelectedItem, Self.ageOptions.count - 1)].1,
            openers: store.settings.openers
        )
        store.save(settings)
        onApply?(settings)
        refreshFromStore()
    }

    // MARK: Actions

    @objc private func chooseInbox(_ sender: Any) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Inbox"
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.pathField.stringValue = url.path
            self.apply()
        }
    }

    @objc private func ageChanged(_ sender: Any) {
        apply()
    }

    @objc private func openersEdited(_ sender: Any) {
        updateOpenersUI(with: store.settings)
    }

    @objc private func chooseOpenerApp(_ sender: Any) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Use This App"
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            let app = url.deletingPathExtension().lastPathComponent
            let ext = normalizedExtension()
            guard !ext.isEmpty else { return }
            var settings = self.store.settings
            settings = AppSettings(
                inboxURL: settings.inboxURL,
                maxFileAge: settings.maxFileAge,
                openers: settings.openers.merging([ext: app]) { _, new in new }
            )
            self.store.save(settings)
            self.onApply?(settings)
            self.refreshFromStore()
        }
    }

    @objc private func removeRule(_ sender: Any) {
        let ext = normalizedExtension()
        guard !ext.isEmpty else { return }
        var settings = store.settings
        var openers = settings.openers
        openers.removeValue(forKey: ext)
        settings = AppSettings(inboxURL: settings.inboxURL, maxFileAge: settings.maxFileAge, openers: openers)
        store.save(settings)
        onApply?(settings)
        refreshFromStore()
    }
}
#endif