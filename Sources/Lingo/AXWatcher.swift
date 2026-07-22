import AppKit
import ApplicationServices

// Watches the Accessibility (TCC) grant while the app runs. macOS does not
// restart the app after the user flips the toggle in System Settings, so
// without this the selection hotkeys stay dead until a relaunch — the classic
// first-install "shortcut is set but nothing happens" trap.
final class AXWatcher: NSObject, ObservableObject {
    static let shared = AXWatcher()
    @Published private(set) var trusted = AXIsProcessTrusted()
    private var timer: Timer?

    func start() {
        // Note: Prefs.axGranted is NOT synced here — checkInstallHealth compares
        // it against the live state to detect a grant lost after an update.
        trusted = AXIsProcessTrusted()
        // Fires on any Accessibility-list change (undocumented but stable name).
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(recheck),
            name: NSNotification.Name("com.apple.accessibility.api"), object: nil)
        // Coming back from System Settings re-activates the app.
        NotificationCenter.default.addObserver(
            self, selector: #selector(recheck),
            name: NSApplication.didBecomeActiveNotification, object: nil)
        if !trusted { startPolling() }
    }

    // Poll only while the grant is missing — the transition a fresh install is
    // waiting on. Revocation is caught by the two notifications above.
    private func startPolling() {
        guard timer == nil else { return }
        let poll = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.check()
        }
        poll.tolerance = 1.0
        timer = poll
    }

    @objc private func recheck() {
        // The TCC database write can lag the notification — check now and again shortly after.
        DispatchQueue.main.async { self.check() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.check() }
    }

    private func check() {
        let now = AXIsProcessTrusted()
        if now { timer?.invalidate(); timer = nil } else { startPolling() }
        guard now != trusted else { return }
        trusted = now
        Prefs.axGranted = now
        // Idempotent re-install of the hotkeys. No relaunch anywhere: the grab
        // itself reads the selection via the AX API (see Selection.swift),
        // which honors the grant instantly — only CGEvent posting doesn't.
        HotKeyManager.shared.reload()
    }
}

func openAccessibilitySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
        NSWorkspace.shared.open(url)
    }
}

func requestAccessibility() {
    // The system permission dialog only ever appears on the first request; after
    // that the deep link is the only path that leads anywhere. Never do both at
    // once — two permission UIs fighting for focus reads as a glitch.
    let defaults = UserDefaults.standard
    let prompted = defaults.bool(forKey: "axPrompted")
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    if prompted { openAccessibilitySettings() }
    defaults.set(true, forKey: "axPrompted")
}
