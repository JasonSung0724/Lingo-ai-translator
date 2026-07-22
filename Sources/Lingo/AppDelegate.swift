import Cocoa
import SwiftUI
import Carbon
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    static var shared: AppDelegate?
    static var isOfficialBuild: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "LingoOfficialBuild") as? Bool) == true
    }

    private var statusItem: NSStatusItem!
    private let model = TranslatorModel()
    private var window: NSWindow!
    private lazy var updater = SPUStandardUpdaterController(startingUpdater: true,
                                                            updaterDelegate: self, userDriverDelegate: self)
    private var pendingUpdateInstall: (() -> Void)?
    private var idleInstallTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        // Single instance: terminate any other copies (e.g. a stray build-folder copy).
        let me = NSRunningApplication.current
        let bundleID = Bundle.main.bundleIdentifier ?? "io.github.jasonsung0724.lingo"
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) where other != me {
            other.forceTerminate()
        }
        Appearance.apply(Prefs.appearance)
        buildMainMenu()
        buildWindow()
        buildMenuBar()
        HotKeyManager.shared.configure { [weak self] id in self?.handleHotKey(id: id) }
        AXWatcher.shared.start()   // re-registers hotkeys the moment Accessibility is granted
        // Sparkle only runs in official releases (CI stamps LingoOfficialBuild):
        // a from-source build would get overwritten by the release feed and its
        // differing signature would make Sparkle refuse the update anyway.
        if Self.isOfficialBuild {
            _ = updater   // lazy so it can take self as delegate
            updater.updater.automaticallyChecksForUpdates = true
            setAutoUpdate(Prefs.autoUpdate)
        }
        // Users who set up a pre-guide version never saw the wizard — don't
        // spring it on them after an update. onboardingSeen separates them from
        // someone who quit halfway through the guide on a fresh install (who
        // should get it again).
        if Prefs.hasLaunchedBefore && !Prefs.onboardingSeen {
            Prefs.onboardingDone = true
        }
        Prefs.hasLaunchedBefore = true
        if !Prefs.onboardingDone {
            Prefs.onboardingSeen = true
            model.startOnboarding()   // first launch: walk through permissions, hotkeys, AI sign-in
        }
        checkInstallHealth()
        // Warm the CLI-path cache so the slow login-shell fallback never runs
        // on the main thread when the first translation fires.
        DispatchQueue.global(qos: .utility).async {
            for provider in Providers.all { _ = provider.executablePath }
        }
    }

    // Scheduled update alerts from a menu-bar (LSUIElement) app can appear behind
    // other windows unless we activate first.
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        NSApp.activate(ignoringOtherApps: true)
    }

    // Silent updates normally install "on quit" — but a menu-bar app is never
    // quit, so downloaded updates sat unapplied forever. Take the installation
    // block and fire it ourselves once the user has been idle for a while.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock: @escaping () -> Void) -> Bool {
        pendingUpdateInstall = immediateInstallationBlock
        idleInstallTimer?.invalidate()
        idleInstallTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.installUpdateIfIdle()
        }
        return true
    }

    private func installUpdateIfIdle() {
        guard let install = pendingUpdateInstall,
              !model.busy, !model.explainBusy, !model.showingOnboarding,
              window?.isVisible != true,
              Date().timeIntervalSince(model.lastActivity) > 600 else { return }
        pendingUpdateInstall = nil
        idleInstallTimer?.invalidate(); idleInstallTimer = nil
        install()   // Sparkle installs the downloaded update and relaunches
    }

    private func checkInstallHealth() {
        if Bundle.main.bundlePath.contains("/AppTranslocation/") {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Move Lingo to Applications"
            alert.informativeText = "Lingo is running from a temporary location (probably inside the downloaded DMG). Drag Lingo.app into your Applications folder and launch it from there — otherwise automatic updates can't work."
            alert.runModal()
        }
        // Ad-hoc signed updates get a new code hash, which makes macOS silently
        // forget the Accessibility grant. Detect the regression and tell the user.
        if AXIsProcessTrusted() {
            Prefs.axGranted = true
        } else if Prefs.axGranted {
            Prefs.axGranted = false
            // No alert during onboarding — the wizard's permission step covers it.
            if model.showingOnboarding { return }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Re-grant Accessibility to Lingo"
            alert.informativeText = "After an update, macOS forgets Lingo's Accessibility permission. Remove Lingo from System Settings → Privacy & Security → Accessibility and add it again, or selection hotkeys won't grab text."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                openAccessibilitySettings()
            }
        }
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        if Self.isOfficialBuild {
            let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
            updateItem.target = self
            appMenu.addItem(updateItem)
            appMenu.addItem(.separator())
        }
        appMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit Lingo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }


    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Lingo"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .windowBackgroundColor
        window.level = Prefs.floatOnTop ? .floating : .normal
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("LingoWindow")
        // Only center on the very first run — centering after restore defeated the autosave.
        if UserDefaults.standard.string(forKey: "NSWindow Frame LingoWindow") == nil {
            window.center()
        }
        // Recover from a deformed autosaved frame (0.1.2's guide could blow the
        // height up to the content's ideal size and autosave persisted it).
        let visible = NSScreen.main?.visibleFrame.height ?? 900
        if window.frame.height > visible {
            window.setContentSize(NSSize(width: 560, height: 520))
            window.center()
        }
        window.contentView = NSHostingView(rootView: RootView(model: model))
        model.window = window
        // Closing the window mid-guide counts as skipping it — otherwise the
        // guide would silently keep the hotkeys paused with no UI on screen.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                               object: window, queue: .main) { [weak self] _ in
            self?.model.dismissOnboarding()
        }
    }

    @objc func openSetup() {
        model.dismissOnboarding()   // Setup replaces the guide, not hides behind it
        model.showingSettings = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }


    private func buildMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Lingo")
        refreshStatusMenu()
    }

    // Rebuilt whenever hotkeys change so the labels stay accurate.
    func refreshStatusMenu() {
        guard statusItem != nil else { return }
        let menu = NSMenu()
        addItem(menu, "Translate Selection  (\(HotKeyAction.translate.combo))", #selector(menuTranslate))
        addItem(menu, "Quick Popup Translate  (\(HotKeyAction.popup.combo))", #selector(menuPopup))
        addItem(menu, "Translate Screenshot  (\(HotKeyAction.screenshot.combo))", #selector(menuScreenshot))
        addItem(menu, "Translate & Replace  (\(HotKeyAction.replace.combo))", #selector(menuReplace))
        addItem(menu, "Explain Selection  (\(HotKeyAction.explain.combo))", #selector(menuExplain))
        addItem(menu, "Open Translator  (\(HotKeyAction.open.combo))", #selector(menuOpen))
        addItem(menu, "Translate Document…", #selector(menuDocument))
        menu.addItem(.separator())
        addItem(menu, "Setup…", #selector(openSetup))
        addItem(menu, "Welcome Guide…", #selector(openWelcomeGuide))
        if Self.isOfficialBuild { addItem(menu, "Check for Updates…", #selector(checkForUpdates)) }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Lingo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func addItem(_ menu: NSMenu, _ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func openWelcomeGuide() {
        model.startOnboarding()
    }

    // Silent background download + install (applied on relaunch/quit); the
    // Setup toggle switches back to ask-first at any time.
    func setAutoUpdate(_ on: Bool) {
        guard Self.isOfficialBuild else { return }
        updater.updater.automaticallyDownloadsUpdates = on
    }

    @objc private func checkForUpdates() {
        guard Self.isOfficialBuild else { return }
        NSApp.activate(ignoringOtherApps: true)
        updater.checkForUpdates(nil)
    }

    @objc private func menuTranslate() { model.startFromSelection() }
    @objc private func menuPopup() { model.quickTranslatePopup() }
    @objc private func menuScreenshot() { model.translateScreenshot() }
    @objc private func menuReplace() { model.replaceSelection() }
    @objc private func menuExplain() { model.startExplainFromSelection() }
    @objc private func menuOpen() { model.openEmpty() }
    @objc private func menuDocument() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { model.translateDocument(url: url) }
    }

    func handleHotKey(id: UInt32) {
        model.touch()
        model.showingSettings = false
        // Hotkeys are paused while the guide shows; if one fires anyway,
        // dismiss quietly — never present() before the action grabs its selection.
        model.dismissOnboarding()
        switch id {
        case 1: model.startFromSelection()
        case 2: model.openEmpty()
        case 3: model.translateScreenshot()
        case 4: model.replaceSelection()
        case 5: model.quickTranslatePopup()
        case 6: model.startExplainFromSelection()
        default: break
        }
    }
}
