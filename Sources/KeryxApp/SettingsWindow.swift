#if os(macOS)
import AppKit
import KeryxKit

/// Settings window: pick the inbox directory and the fallback scan interval.
/// Changes apply live (no OK/Cancel), matching macOS conventions.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onApply: ((AppSettings) -> Void)?

    private let store: SettingsStore
    private let pathField = NSTextField()
    private let intervalSlider = NSSlider(value: 2.0, minValue: AppSettings.minimumScanInterval, maxValue: 30.0, target: nil, action: nil)
    private let intervalLabel = NSTextField(labelWithString: "")

    init(store: SettingsStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 150),
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

    private func buildLayout() {
        guard let content = window?.contentView else { return }

        let inboxLabel = NSTextField(labelWithString: "Inbox folder:")
        pathField.isEditable = false
        pathField.lineBreakMode = .byTruncatingHead
        let chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseInbox(_:)))
        chooseButton.bezelStyle = .rounded

        let inboxRow = NSStackView(views: [inboxLabel, pathField, chooseButton])
        inboxRow.translatesAutoresizingMaskIntoConstraints = false
        inboxRow.huggingPriority(for: .horizontal)
        pathField.setContentHuggingPriority(.init(1), for: .horizontal)

        let intervalTitle = NSTextField(labelWithString: "Fallback scan interval (event-driven watching makes this rarely relevant):")
        intervalTitle.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        intervalTitle.lineBreakMode = .byWordWrapping
        intervalTitle.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        intervalTitle.setContentHuggingPriority(.init(1), for: .horizontal)

        intervalSlider.target = self
        intervalSlider.action = #selector(intervalChanged(_:))
        intervalSlider.numberOfTickMarks = 0

        intervalLabel.alignment = .right
        intervalLabel.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)

        let intervalRow = NSStackView(views: [intervalSlider, intervalLabel])
        intervalRow.translatesAutoresizingMaskIntoConstraints = false
        intervalLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let column = NSStackView(views: [inboxRow, intervalTitle, intervalRow])
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
            intervalSlider.widthAnchor.constraint(equalToConstant: 240),
        ])
    }

    private func refreshFromStore() {
        let settings = store.settings
        let effectiveInbox = effectiveInboxURL(for: settings)
        pathField.stringValue = effectiveInbox.path
        intervalSlider.doubleValue = settings.scanInterval
        updateIntervalLabel()
    }

    private func updateIntervalLabel() {
        intervalLabel.stringValue = String(format: "%.1f s", intervalSlider.doubleValue)
    }

    private func currentSettings() -> AppSettings {
        AppSettings(
            inboxURL: URL(fileURLWithPath: pathField.stringValue, isDirectory: true),
            scanInterval: intervalSlider.doubleValue
        )
    }

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

    @objc private func intervalChanged(_ sender: Any) {
        updateIntervalLabel()
        apply()
    }

    private func apply() {
        let settings = currentSettings()
        store.save(settings)
        onApply?(settings)
    }
}
#endif