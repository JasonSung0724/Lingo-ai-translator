import AppKit
import Carbon
import SwiftUI

enum HotKeyAction: String, CaseIterable, Identifiable {
    case translate, popup, screenshot, replace, open, explain
    var id: String { rawValue }

    var title: String {
        switch self {
        case .translate: return "Translate selection"
        case .popup: return "Quick popup translate"
        case .screenshot: return "Translate screenshot"
        case .replace: return "Translate & replace"
        case .open: return "Open translator"
        case .explain: return "Explain selection"
        }
    }

    var fireID: UInt32 {
        switch self {
        case .translate: return 1
        case .open: return 2
        case .screenshot: return 3
        case .replace: return 4
        case .popup: return 5
        case .explain: return 6
        }
    }

    var signature: OSType { 0x4C474F30 + fireID }

    var defaultKey: UInt32 {
        switch self {
        case .translate: return UInt32(kVK_ANSI_T)
        case .popup: return UInt32(kVK_ANSI_P)
        case .screenshot: return UInt32(kVK_ANSI_O) // O for OCR — ⇧⌘S would shadow the in-window swap
        case .replace: return UInt32(kVK_ANSI_R)
        case .open: return UInt32(kVK_ANSI_L)
        case .explain: return UInt32(kVK_ANSI_E)
        }
    }

    // Avoid system-reserved ⇧⌘3/4/5/Q/N/W and Lingo's own in-window ⇧⌘S/⇧⌘C.
    var defaultModifiers: UInt32 { UInt32(cmdKey | shiftKey) }

    var combo: String {
        let c = HotKeyStore.combo(for: self)
        return comboDisplay(key: c.key, modifiers: c.modifiers)
    }
}

func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var value: UInt32 = 0
    if flags.contains(.command) { value |= UInt32(cmdKey) }
    if flags.contains(.option) { value |= UInt32(optionKey) }
    if flags.contains(.control) { value |= UInt32(controlKey) }
    if flags.contains(.shift) { value |= UInt32(shiftKey) }
    return value
}

func comboDisplay(key: UInt32, modifiers: UInt32) -> String {
    var text = ""
    if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
    if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
    if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
    if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
    return text + keyName(key)
}

private let keyNames: [UInt32: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
    11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
    34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
    18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
    49: "Space", 36: "Return", 48: "Tab",
    122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
    101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
]

let functionKeyCodes: Set<UInt32> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113]

func keyName(_ code: UInt32) -> String { keyNames[code] ?? "Key\(code)" }

enum HotKeyStore {
    private static let d = UserDefaults.standard

    static func combo(for action: HotKeyAction) -> (key: UInt32, modifiers: UInt32) {
        let keyName = "hotkey.\(action.rawValue).key"
        let modName = "hotkey.\(action.rawValue).mods"
        if d.object(forKey: keyName) != nil, d.object(forKey: modName) != nil {
            return (UInt32(d.integer(forKey: keyName)), UInt32(d.integer(forKey: modName)))
        }
        return (action.defaultKey, action.defaultModifiers)
    }

    static func set(_ action: HotKeyAction, key: UInt32, modifiers: UInt32) {
        d.set(Int(key), forKey: "hotkey.\(action.rawValue).key")
        d.set(Int(modifiers), forKey: "hotkey.\(action.rawValue).mods")
    }

    static func reset(_ action: HotKeyAction) {
        d.removeObject(forKey: "hotkey.\(action.rawValue).key")
        d.removeObject(forKey: "hotkey.\(action.rawValue).mods")
    }
}

final class HotKeyManager {
    static let shared = HotKeyManager()
    private var refs: [EventHotKeyRef?] = []
    private var installed = false
    private var paused = false
    var onFire: ((UInt32) -> Void)?

    // The onboarding wizard pauses global hotkeys: while its recorder is up, a
    // combo that is already registered would fire the action (Carbon consumes
    // the event before the recorder's local monitor sees it) and tear the
    // guide down mid-setup.
    func setPaused(_ value: Bool) {
        guard paused != value else { return }
        paused = value
        reload()
    }

    func configure(onFire: @escaping (UInt32) -> Void) {
        self.onFire = onFire
        installHandler()
        reload()
    }

    private func installHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            var hotKey = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            DispatchQueue.main.async { HotKeyManager.shared.onFire?(hotKey.id) }
            return noErr
        }, 1, &spec, nil, nil)
    }

    func reload() {
        for ref in refs { if let ref { UnregisterEventHotKey(ref) } }
        refs.removeAll()
        guard !paused else { return }
        for action in HotKeyAction.allCases {
            let combo = HotKeyStore.combo(for: action)
            var ref: EventHotKeyRef?
            RegisterEventHotKey(combo.key, combo.modifiers,
                                EventHotKeyID(signature: action.signature, id: action.fireID),
                                GetApplicationEventTarget(), 0, &ref)
            refs.append(ref)
        }
        AppDelegate.shared?.refreshStatusMenu()
    }
}

struct KeyRecorder: View {
    let action: HotKeyAction
    @State private var recording = false
    @State private var display = ""
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Text(action.title).frame(width: 170, alignment: .leading)
            Button(recording ? "Press keys…" : display) { toggle() }
                .frame(width: 120)
            Button {
                HotKeyStore.reset(action); refresh(); HotKeyManager.shared.reload()
            } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Reset to default")
        }
        .onAppear(perform: refresh)
        .onDisappear(perform: stop)   // never leave the key monitor behind
    }

    private func refresh() {
        let combo = HotKeyStore.combo(for: action)
        display = comboDisplay(key: combo.key, modifiers: combo.modifiers)
    }

    private func toggle() {
        if recording { stop(); return }
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }            // Escape cancels
            let mods = carbonModifiers(from: event.modifierFlags)
            let key = UInt32(event.keyCode)
            let isFunctionKey = functionKeyCodes.contains(key)
            guard mods != 0 || isFunctionKey else { return nil }      // modifier required, except function keys
            let taken = HotKeyAction.allCases.contains { other in
                guard other != action else { return false }
                let combo = HotKeyStore.combo(for: other)
                return combo.key == key && combo.modifiers == mods
            }
            if taken {
                display = "Already in use"
                stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { refresh() }
                return nil
            }
            HotKeyStore.set(action, key: key, modifiers: mods)
            refresh(); HotKeyManager.shared.reload(); stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
