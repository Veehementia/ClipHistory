import AppKit
import Carbon.HIToolbox
import ServiceManagement

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let history = ClipboardHistory()
    private lazy var picker = Picker(history: history)
    private var hotKey: HotKey?
    private var trustTimer: Timer?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipHistory")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        history.start()
        hotKey = HotKey(keyCode: kVK_ANSI_V, modifiers: optionKey) { [unowned self] in picker.show() }
        picker.couldNotPaste = { [unowned self] in explainMissingAccess() }
        // Needed to paste into other apps and to find their text cursor. Without it, picking an
        // item only copies it.
        askForAccess()
        // macOS can give or take away access at any time, so keep the icon up to date.
        updateIcon()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateIcon() }
        }
    }

    private func askForAccess() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }

    private func updateIcon() {
        statusItem?.button?.appearsDisabled = !AXIsProcessTrusted()
    }

    /// Picking an item without access only copies it, which is easy to mistake for a bug.
    private func explainMissingAccess() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("ClipHistory can't paste without Accessibility access", comment: "Alert")
        alert.informativeText = NSLocalizedString(
            "The item is on the clipboard, so ⌘V pastes it. If ClipHistory is already on in System Settings, that permission was for an earlier build: ask again and turn it on once more.",
            comment: "Alert"
        )
        alert.addButton(withTitle: NSLocalizedString("Ask for Access Again", comment: "Alert button"))
        alert.addButton(withTitle: NSLocalizedString("Not Now", comment: "Alert button"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { resetAccess() }
    }

    // MARK: Status menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !AXIsProcessTrusted() {
            let warning = NSMenuItem(title: NSLocalizedString("ClipHistory needs Accessibility access to paste", comment: "Menu status"), action: nil, keyEquivalent: "")
            warning.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            warning.isEnabled = false
            menu.addItem(warning)
            menu.addItem(item(NSLocalizedString("Allow in System Settings…", comment: "Menu item"), #selector(openAccessibilitySettings)))
            let reset = item(NSLocalizedString("Reset Permission and Ask Again", comment: "Menu item"), #selector(resetAccess))
            reset.toolTip = NSLocalizedString(
                "Use this if ClipHistory is already on in System Settings but still asks for access.",
                comment: "Tooltip"
            )
            menu.addItem(reset)
            menu.addItem(.separator())
        }
        if hotKey?.isRegistered == false {
            let taken = NSMenuItem(title: NSLocalizedString("Another app is already using ⌥V", comment: "Menu status"), action: nil, keyEquivalent: "")
            taken.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            taken.isEnabled = false
            menu.addItem(taken)
            menu.addItem(.separator())
        }

        // Shown for the hint only: the shortcut itself works through the hot key.
        let show = item(NSLocalizedString("Show Clipboard History", comment: "Menu item"), #selector(showPicker), key: "v")
        show.keyEquivalentModifierMask = .option
        menu.addItem(show)
        let clear = item(NSLocalizedString("Clear History", comment: "Menu item"), #selector(clearHistory))
        clear.isEnabled = !history.items.isEmpty
        menu.addItem(clear)
        menu.addItem(.separator())

        let login = item(NSLocalizedString("Open at Login", comment: "Menu item"), #selector(toggleOpenAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item(NSLocalizedString("Quit ClipHistory", comment: "Menu item"), #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    @objc private func showPicker() {
        // Let the status menu finish closing first.
        DispatchQueue.main.async { [self] in picker.show() }
    }

    @objc private func clearHistory() {
        history.clear()
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// macOS can keep showing the app as allowed while no longer trusting it, and then never asks
    /// again. Clearing the entry lets the app ask afresh.
    @objc private func resetAccess() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Accessibility", id]
        try? reset.run()
        reset.waitUntilExit()
        askForAccess()
    }

    @objc private func toggleOpenAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }
}
