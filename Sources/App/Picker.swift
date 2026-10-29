import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// The menu that opens at the text cursor, and pastes the item picked from it into the app the
/// user was typing in.
@MainActor
final class Picker: NSObject {
    private static let previewLength = 60

    private let history: ClipboardHistory
    private var isOpen = false
    private var picked: Clip?
    /// Called when an item was picked but could only be copied, for lack of Accessibility access.
    var couldNotPaste: (() -> Void)?

    init(history: ClipboardHistory) {
        self.history = history
    }

    func show() {
        guard !isOpen else { return }
        isOpen = true
        // Both have to be read before coming forward, after which the focus is ours.
        let target = NSWorkspace.shared.frontmostApplication
        let location = Self.textCursorLocation() ?? NSEvent.mouseLocation
        let menu = makeMenu()

        // Come forward so the menu gets the arrow keys, Return and Escape.
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [self] in
            picked = nil
            menu.popUp(positioning: nil, at: location, in: nil)
            isOpen = false
            if let target, target != .current { target.activate(options: []) }
            if let picked { paste(picked, into: target) }
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        guard !history.items.isEmpty else {
            let empty = NSMenuItem(title: NSLocalizedString("Nothing copied yet", comment: "Picker"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return menu
        }

        for (index, clip) in history.items.enumerated() {
            // 1–9 then 0 pick the first ten items straight away.
            let key = index < 9 ? String(index + 1) : index == 9 ? "0" : ""
            let item = NSMenuItem(title: "", action: #selector(pick(_:)), keyEquivalent: key)
            item.keyEquivalentModifierMask = []
            item.target = self
            item.representedObject = clip
            describe(clip, in: item)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: NSLocalizedString("Clear History", comment: "Menu item"), action: #selector(clear), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        return menu
    }

    private func describe(_ clip: Clip, in item: NSMenuItem) {
        // The same number of dots for every password, so its length doesn't show either.
        if clip.isConcealed {
            item.title = String(repeating: "•", count: 10)
            return
        }
        switch clip.content {
        case .text(let text):
            item.title = Self.preview(text)
            if item.title != text { item.toolTip = String(text.prefix(2000)) }
        case let .image(thumbnail, pixelSize):
            item.image = thumbnail
            item.title = String(
                format: NSLocalizedString("Image, %d × %d", comment: "Picker; width and height in pixels"),
                Int(pixelSize.width), Int(pixelSize.height)
            )
        case .files(let urls):
            item.image = NSWorkspace.shared.icon(forFile: urls[0].path)
            item.image?.size = NSSize(width: 16, height: 16)
            item.title = urls.count == 1 ? urls[0].lastPathComponent : String(
                format: NSLocalizedString("%@ and %d more", comment: "Picker; a file name and how many other files"),
                urls[0].lastPathComponent, urls.count - 1
            )
            item.toolTip = urls.map(\.path).joined(separator: "\n")
        }
    }

    /// The text on one line, shortened to fit a menu item.
    private static func preview(_ text: String) -> String {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return line.count > previewLength ? line.prefix(previewLength) + "…" : line
    }

    @objc private func pick(_ sender: NSMenuItem) {
        picked = sender.representedObject as? Clip
    }

    @objc private func clear() {
        history.clear()
    }

    // MARK: Pasting

    private func paste(_ clip: Clip, into target: NSRunningApplication?) {
        history.copy(clip)
        // Without Accessibility access the item is only copied, ready for ⌘V.
        guard AXIsProcessTrusted() else {
            couldNotPaste?()
            return
        }
        pressCommandV(whenActive: target, triesLeft: 20)
    }

    /// Waits for the app to be back in front first, so it's the one that gets the keystroke.
    private func pressCommandV(whenActive app: NSRunningApplication?, triesLeft: Int) {
        guard let app, !app.isActive, triesLeft > 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { Self.pressCommandV() }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [self] in
            pressCommandV(whenActive: app, triesLeft: triesLeft - 1)
        }
    }

    private static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: isDown)
            // Set outright, so an Option key still held from ⌥V doesn't turn this into ⌥⌘V.
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    // MARK: Text cursor

    /// The bottom left of the text cursor in the focused text field, in screen coordinates.
    /// Many apps don't report it (Electron apps and some browsers among them), and the menu then
    /// opens at the mouse pointer instead.
    private static func textCursorLocation() -> NSPoint? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement

        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range else { return nil }
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds
        ) == .success, let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.height > 0 else { return nil }

        // Accessibility measures from the top left of the main screen, AppKit from the bottom left.
        guard let mainScreen = NSScreen.screens.first else { return nil }
        let point = NSPoint(x: rect.minX, y: mainScreen.frame.maxY - rect.maxY)
        // Some apps report a made-up spot; only trust one that's on a screen.
        return NSScreen.screens.contains { $0.frame.contains(point) } ? point : nil
    }
}
