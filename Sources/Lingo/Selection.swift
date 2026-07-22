import Cocoa
import Carbon
import ApplicationServices

// The focused UI element, via the Accessibility API. Unlike synthetic ⌘C/⌘V
// (CGEvent posting stays blocked for an already-running process even after the
// permission is granted — macOS only re-evaluates it on relaunch), AX calls
// honor the grant the moment it lands. So AX read/write is the primary path
// and key simulation is only the fallback for apps with poor AX support.
private func axFocusedElement() -> AXUIElement? {
    let system = AXUIElementCreateSystemWide()
    var focused: CFTypeRef?
    guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
          let value = focused, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

private func axSelectedText() -> String? {
    guard let element = axFocusedElement() else { return nil }
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
          let text = value as? String, !text.isEmpty else { return nil }
    return text
}

// Screen anchor just below the actual selection (AppKit coordinates) — the
// mouse pointer can be nowhere near a keyboard-made selection.
func selectionAnchorPoint() -> NSPoint? {
    guard AXIsProcessTrusted(), let element = axFocusedElement() else { return nil }
    var rangeValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
          let range = rangeValue, CFGetTypeID(range) == AXValueGetTypeID() else { return nil }
    var boundsValue: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                     range, &boundsValue) == .success,
          let bounds = boundsValue, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
    var rect = CGRect.zero
    guard AXValueGetValue((bounds as! AXValue), .cgRect, &rect),
          rect.width > 0, rect.height > 0 else { return nil }
    // AX rects use top-left-origin global coordinates; AppKit uses bottom-left.
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return NSPoint(x: rect.minX, y: primaryHeight - rect.maxY - 4)
}

private func axReplaceSelectedText(_ text: String) -> Bool {
    guard let element = axFocusedElement() else { return false }
    // The selection must still exist (it can collapse while the translation
    // runs) — otherwise let ⌘V handle insertion at the caret instead.
    var current: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &current) == .success,
          let selected = current as? String, !selected.isEmpty else { return false }
    var settable = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
          settable.boolValue,
          AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
    else { return false }
    // Some apps (Electron, web views) answer .success without applying —
    // read back and only trust the write if the selection actually changed.
    var after: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &after) == .success else { return true }
    let now = (after as? String) ?? ""
    return now != selected
}

// Full-fidelity pasteboard snapshot — images, files, rich text — so grab/replace
// can restore exactly what the user had, not just a plain string.
private func backupPasteboard(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
    (pasteboard.pasteboardItems ?? []).map { item in
        let copy = NSPasteboardItem()
        for type in item.types {
            if let data = item.data(forType: type) { copy.setData(data, forType: type) }
        }
        return copy
    }
}

private func restorePasteboard(_ pasteboard: NSPasteboard, items: [NSPasteboardItem]) {
    pasteboard.clearContents()
    if !items.isEmpty { pasteboard.writeObjects(items) }
}

func grabSelection() -> String {
    let pasteboard = NSPasteboard.general
    let existing = pasteboard.string(forType: .string) ?? ""

    guard AXIsProcessTrusted() else {
        return existing.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Primary: read the selection straight off the focused element — instant,
    // clipboard-untouched, and immune to the stale event-posting session.
    if let text = axSelectedText() {
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let backup = backupPasteboard(pasteboard)
    let changeCount = pasteboard.changeCount
    let source = CGEventSource(stateID: .combinedSessionState)
    let key = CGKeyCode(kVK_ANSI_C)
    let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
    down?.flags = .maskCommand
    let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
    up?.flags = .maskCommand
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)

    // Poll instead of one fixed sleep: fast apps return in ~50ms, slow apps
    // (Word, Electron) get up to 600ms before we give up.
    let deadline = Date().addingTimeInterval(0.6)
    while Date() < deadline {
        usleep(50_000)
        if pasteboard.changeCount != changeCount { break }
    }

    if pasteboard.changeCount != changeCount,
       let copied = pasteboard.string(forType: .string), !copied.isEmpty {
        // Restore the user's clipboard so grabbing the selection is non-destructive.
        restorePasteboard(pasteboard, items: backup)
        return copied.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return existing.trimmingCharacters(in: .whitespacesAndNewlines)
}

@discardableResult
func pasteText(_ text: String) -> Bool {
    guard AXIsProcessTrusted() else { return false }   // caller surfaces the missing permission
    // Primary: write the replacement straight into the focused element.
    if axReplaceSelectedText(text) { return true }
    let pasteboard = NSPasteboard.general
    let backup = backupPasteboard(pasteboard)
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    let source = CGEventSource(stateID: .combinedSessionState)
    let key = CGKeyCode(kVK_ANSI_V)
    let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
    down?.flags = .maskCommand
    let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
    up?.flags = .maskCommand
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
    // Restore the user's clipboard shortly after the paste completes.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
        restorePasteboard(pasteboard, items: backup)
    }
    return true   // events posted; delivery itself can't be observed
}
