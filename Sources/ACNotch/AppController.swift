import AppKit
import ApplicationServices

/// Menu bar icon, menu, permission handling.
final class AppController: NSObject {
    private let settings = Settings.shared
    private let notch = NotchController()
    private lazy var typing = TypingController(notch: notch)
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?
    private var lastApp: NSRunningApplication?

    func start() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        typing.onToggleHotkey = { [weak self] in self?.toggleEnabled() }
        notch.onDockChange = { [weak self] in self?.refresh() }

        lastApp = NSWorkspace.shared.frontmostApplication
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        if !startTyping(prompt: true) {
            // Wait for the user to grant Accessibility access in System Preferences.
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                if self.startTyping(prompt: false) { timer.invalidate() }
            }
        }
        refresh()
    }

    @discardableResult
    private func startTyping(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options), typing.start() else { return false }
        refresh()
        return true
    }

    // MARK: - Menu

    private func refresh() {
        updateIcon()
        statusItem.menu = buildMenu()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        if let image = NSImage(systemSymbolName: "textformat.abc", accessibilityDescription: "AC Notch") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "ac"
        }
        button.appearsDisabled = !settings.enabled || !typing.isRunning
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let header = NSMenuItem(title: typing.isRunning ? "AC Notch" : "AC Notch — needs permission", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let enabled = item("Enabled  (⌃⌥Space)", #selector(toggleEnabledAction))
        enabled.state = settings.enabled ? .on : .off
        menu.addItem(enabled)

        let autocorrect = item("Correct Automatically", #selector(toggleAutocorrect))
        autocorrect.state = settings.autocorrect ? .on : .off
        menu.addItem(autocorrect)

        if notch.isFloating {
            menu.addItem(item("Dock Back to Notch", #selector(dockToNotch)))
        }

        let preview = item("Preview Notch Layout", #selector(togglePreviewNotch))
        preview.state = settings.previewNotch ? .on : .off
        menu.addItem(preview)

        if let app = lastApp, let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier {
            menu.addItem(.separator())
            let name = app.localizedName ?? id
            let exclude = item("Disable in \(name)", #selector(toggleExcluded(_:)))
            exclude.representedObject = id
            exclude.state = settings.isExcluded(id) ? .on : .off
            menu.addItem(exclude)
        }

        menu.addItem(.separator())
        if !typing.isRunning {
            menu.addItem(item("Grant Accessibility Access…", #selector(openAccessibilitySettings)))
        }
        menu.addItem(item("How It Works", #selector(showHelp)))
        menu.addItem(item("Quit AC Notch", #selector(quit), key: "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        lastApp = app
        refresh()
    }

    @objc private func toggleEnabledAction() { toggleEnabled() }

    private func toggleEnabled() {
        settings.enabled.toggle()
        typing.reset()
        notch.show([StripOption(text: settings.enabled ? "Autocorrect on" : "Autocorrect off", kind: .info)],
                   hideAfter: 1.2)
        refresh()
    }

    @objc private func toggleAutocorrect() {
        settings.autocorrect.toggle()
        refresh()
    }

    @objc private func dockToNotch() {
        notch.dock()
    }

    @objc private func togglePreviewNotch() {
        settings.previewNotch.toggle()
        notch.show([StripOption(text: settings.previewNotch ? "Notch preview on" : "Notch preview off", kind: .info)],
                   hideAfter: 1.5)
        refresh()
    }

    @objc private func toggleExcluded(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        settings.setExcluded(id, !settings.isExcluded(id))
        typing.reset()
        refresh()
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "AC Notch"
        alert.informativeText = """
        While you type, three suggestions appear at the top of the screen: \
        what you typed | the best fix | another option.

        • Press space or punctuation and a misspelled word is fixed automatically.
        • Press backspace straight after a fix to undo it.
        • Click any suggestion to use it.
        • ⌃⌥Space turns AC Notch on or off.

        Everything runs on your Mac using Apple's built-in spell checker. Nothing you type leaves your computer.
        """
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
