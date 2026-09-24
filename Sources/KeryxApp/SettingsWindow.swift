#if os(macOS)
import AppKit
import UniformTypeIdentifiers
import KeryxKit

/// Trashcan button for an opener-rule row; carries the rule's key.
@MainActor
private final class RuleTrashButton: NSButton {
    var ruleKey: String = ""
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

/// Settings window: pick the inbox directory, hide files older than a
/// cutoff, map file extensions to specific applications, and toggle
/// launch-at-login. Changes apply live (no OK/Cancel), matching macOS
/// conventions.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onApply: ((AppSettings) -> Void)?

    private let store: SettingsStore
    private let pathField = NSTextField()
    private let agePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let extensionField = NSTextField()
    private let rulesStack = NSStackView()
    private let rulesEmptyLabel = NSTextField(labelWithString: "")
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: nil, action: nil)

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
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 310),
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

        // Opener add-rule row
        let openersHeader = sectionHeader("Opening files")
        let openersTitle = NSTextField(labelWithString: "Open files ending in:")
        extensionField.placeholderString = "e.g. md or *.md"
        let chooseAppButton = NSButton(title: "Choose App…", target: self, action: #selector(chooseOpenerApp(_:)))
        chooseAppButton.bezelStyle = .rounded
        let openersRow = row(views: [openersTitle, extensionField, chooseAppButton])

        // Rule rows (one per opener rule, each with a trashcan button)
        rulesStack.orientation = .vertical
        rulesStack.alignment = .leading
        rulesStack.spacing = 4

        rulesEmptyLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        rulesEmptyLabel.textColor = .secondaryLabelColor

        // Launch at login
        let generalHeader = sectionHeader("General")
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginToggled(_:))
        let launchRow = row(views: [launchAtLoginCheckbox])

        let footerLabel = NSTextField(labelWithString: "Keryx \(appVersion)")
        footerLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        footerLabel.textColor = .tertiaryLabelColor

        let column = NSStackView(views: [
            sectionHeader("Inbox"),
            inboxRow,
            sectionHeader("Visibility"),
            ageRow,
            openersHeader,
            openersRow,
            rulesStack,
            rulesEmptyLabel,
            generalHeader,
            launchRow,
            footerLabel,
        ])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 10
        column.setCustomSpacing(18, after: inboxRow)
        column.setCustomSpacing(18, after: ageRow)
        column.setCustomSpacing(4, after: rulesStack)
        column.setCustomSpacing(18, after: rulesEmptyLabel)
        column.setCustomSpacing(16, after: launchRow)
        column.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(column)

        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            column.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            pathField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            extensionField.widthAnchor.constraint(equalToConstant: 160),
        ])
    }

    private func row(views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 8
        return stack
    }

    private func sectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    // MARK: State sync

    private func refreshFromStore() {
        let settings = store.settings
        pathField.stringValue = effectiveInboxURL(for: settings).path

        let age = settings.maxFileAge
        let index = Self.ageOptions.firstIndex { $0.1 != nil && $0.1 == age } ?? (age == nil ? 0 : 1)
        agePopup.selectItem(at: index)

        rebuildRuleRows(with: settings)

        launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    private func rebuildRuleRows(with settings: AppSettings) {
        rulesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let rules = settings.openers.sorted { $0.key < $1.key }
        if rules.isEmpty {
            rulesEmptyLabel.stringValue = "No overrides — all files open with the OS default app."
            rulesEmptyLabel.isHidden = false
            return
        }
        rulesEmptyLabel.isHidden = true

        for (key, app) in rules {
            let display = key == "*" ? "* (all files) → \(app)" : ".\(key) → \(app)"
            let label = NSTextField(labelWithString: display)
            let trash = RuleTrashButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Remove rule")!,
                                        target: self,
                                        action: #selector(removeRule(_:)))
            trash.isBordered = false
            trash.contentTintColor = .secondaryLabelColor
            trash.ruleKey = key
            trash.setAccessibilityLabel("Remove rule for \(key)")
            let ruleRow = row(views: [label, trash])
            rulesStack.addArrangedSubview(ruleRow)
        }
        _ = rulesStack // keep alive with the view hierarchy
    }

    private func normalizedExtension() -> String {
        var ext = extensionField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        if ext.hasPrefix("*.") { ext = String(ext.dropFirst(2)) }
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

    @objc private func chooseOpenerApp(_ sender: Any) {
        let ext = {
            var value = extensionField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
            if value.hasPrefix("*.") { value = String(value.dropFirst(2)) }
            if value.hasPrefix(".") { value = String(value.dropFirst(1)) }
            return value
        }()
        guard !ext.isEmpty || extensionField.stringValue.trimmingCharacters(in: .whitespaces) == "*" else { return }
        let key = extensionField.stringValue.trimmingCharacters(in: .whitespaces) == "*" ? "*" : ext

        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Use This App"
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            let app = url.deletingPathExtension().lastPathComponent
            var settings = self.store.settings
            settings = AppSettings(
                inboxURL: settings.inboxURL,
                maxFileAge: settings.maxFileAge,
                openers: settings.openers.merging([key: app]) { _, new in new }
            )
            self.store.save(settings)
            self.onApply?(settings)
            self.extensionField.stringValue = ""
            self.refreshFromStore()
        }
    }

    @objc private func removeRule(_ sender: RuleTrashButton) {
        let key = sender.ruleKey
        var settings = store.settings
        var openers = settings.openers
        openers.removeValue(forKey: key)
        settings = AppSettings(inboxURL: settings.inboxURL, maxFileAge: settings.maxFileAge, openers: openers)
        store.save(settings)
        onApply?(settings)
        refreshFromStore()
    }

    @objc private func launchAtLoginToggled(_ sender: Any) {
        let wantEnabled = launchAtLoginCheckbox.state == .on
        do {
            if wantEnabled != LaunchAtLogin.isEnabled {
                if wantEnabled {
                    try LaunchAtLogin.enable()
                } else {
                    try LaunchAtLogin.disable()
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not update Launch at Login"
            alert.informativeText = """
            \(error.localizedDescription)

            If the app was quarantined after download, run `xattr -cr Keryx.app`,
            or approve it manually in System Settings → General → Login Items.
            """
            alert.runModal()
        }
        launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
    }
}
#endif