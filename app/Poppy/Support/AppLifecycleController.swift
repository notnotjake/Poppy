import AppKit
import Combine

@MainActor
final class AppLifecycleController: NSObject, ObservableObject, NSWindowDelegate {
    static let hideInDockKey = "hideInDock"
    static let hideInMenuBarKey = "hideInMenuBar"
    private static let mainWindowFrameAutosaveName = "PoppyMainWindowFrame"

    @Published private(set) var hideInDock: Bool
    @Published private(set) var hideInMenuBar: Bool

    private var notificationObserversByWindow: [ObjectIdentifier: NSObjectProtocol] = [:]
    private weak var mainWindow: NSWindow?
    private var shouldBringMainWindowForward = false
    private var openMainWindow: (() -> Void)?

    init(userDefaults: UserDefaults = .standard) {
        hideInDock = userDefaults.object(forKey: Self.hideInDockKey) as? Bool ?? true
        hideInMenuBar = userDefaults.bool(forKey: Self.hideInMenuBarKey)
        super.init()
    }

    func applicationDidFinishLaunching() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func configure(openMainWindow: @escaping () -> Void) {
        self.openMainWindow = openMainWindow
    }

    func setHideInDock(_ isHidden: Bool) {
        hideInDock = isHidden
        updateActivationPolicy()
    }

    func setHideInMenuBar(_ isHidden: Bool) {
        hideInMenuBar = isHidden
    }

    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)

        if let mainWindow {
            bringMainWindowForward(mainWindow)
            return
        }

        shouldBringMainWindowForward = true
        openMainWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings(openSettings: () -> Void) {
        let windowsBeforeOpeningSettings = Set(NSApp.windows.map { ObjectIdentifier($0) })

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openSettings()

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            self.bringSettingsWindowForward(excluding: windowsBeforeOpeningSettings)
        }
    }

    func applicationShouldHandleReopen(hasVisibleWindows: Bool) -> Bool {
        showMainWindow()
        return false
    }

    func observeMainWindow(_ window: NSWindow) {
        if let mainWindow, mainWindow !== window {
            bringMainWindowForward(mainWindow)
            window.close()
            return
        }

        if mainWindow === window {
            window.delegate = self
            if shouldBringMainWindowForward {
                bringMainWindowForward(window)
            }
            return
        }

        mainWindow = window
        window.delegate = self
        configureMainWindow(window)
        NSApp.setActivationPolicy(.regular)

        if shouldBringMainWindowForward {
            bringMainWindowForward(window)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === mainWindow else {
            return true
        }

        sender.orderOut(nil)
        applyActivationPolicyAfterMainWindowHides()
        return false
    }

    func observeSettingsWindow(_ window: NSWindow) {
        configureSettingsWindow(window)
        observePresentedWindow(window)
    }

    private func observePresentedWindow(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        guard window !== mainWindow, notificationObserversByWindow[id] == nil else { return }

        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self, id] _ in
            guard let self else { return }

            Task { @MainActor in
                if let observer = self.notificationObserversByWindow.removeValue(forKey: id) {
                    NotificationCenter.default.removeObserver(observer)
                }
            }
        }

        notificationObserversByWindow[id] = observer
    }

    private func updateActivationPolicy() {
        if hideInDock && mainWindow?.isVisible != true {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
        }
    }

    private func applyActivationPolicyAfterMainWindowHides() {
        if hideInDock {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
        }
    }

    private func configureSettingsWindow(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = false
    }

    private func configureMainWindow(_ window: NSWindow) {
        window.setFrameAutosaveName(Self.mainWindowFrameAutosaveName)
        window.setFrameUsingName(Self.mainWindowFrameAutosaveName)
    }

    private func bringMainWindowForward(_ window: NSWindow) {
        shouldBringMainWindowForward = false
        NSApp.setActivationPolicy(.regular)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func bringSettingsWindowForward(excluding previousWindowIDs: Set<ObjectIdentifier>) {
        let settingsWindow = newlyPresentedSettingsWindow(excluding: previousWindowIDs) ?? existingPresentedSettingsWindow()

        if let settingsWindow {
            observePresentedWindow(settingsWindow)
            settingsWindow.makeKeyAndOrderFront(nil)
        }
    }

    private func newlyPresentedSettingsWindow(excluding previousWindowIDs: Set<ObjectIdentifier>) -> NSWindow? {
        NSApp.windows.first { window in
            isSettingsWindowCandidate(window) && !previousWindowIDs.contains(ObjectIdentifier(window))
        }
    }

    private func existingPresentedSettingsWindow() -> NSWindow? {
        NSApp.windows.first { window in
            isSettingsWindowCandidate(window)
                && window !== mainWindow
                && !(window is NSPanel)
        }
    }

    private func isSettingsWindowCandidate(_ window: NSWindow) -> Bool {
        window.isVisible && window.canBecomeKey
    }
}
