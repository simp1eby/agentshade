import AppKit

public final class ShadeController {
    public enum Trigger { case manual, lidAngle }
    private let mediaStore: MediaStore
    private let preferences: ShadePreferences
    private let session = ShadeSession()
    private let lidPolicy = LidAnglePolicy()
    private let snapshots: ScreenSnapshotProviding
    public var onSnapshotStatusChange: ((ScreenCaptureVerification) -> Void)?
    private var captureGeneration = 0
    private var displayWindows: [CGDirectDisplayID: ShadeWindow] = [:]
    private var lastAngle: Double?
    private var displaySleeping = false
    private var windowEnhancementMode: Bool?
    private var windowPresentationMode: FrostedPresentationMode?
    public var automationPaused = false {
        didSet {
            if automationPaused {
                suspendAutomation()
                lidPolicy.userDismissed()
            } else if oldValue {
                // Settings are a temporary pause, not dismissal of a lid cycle.
                lidPolicy.reset()
            }
        }
    }
    public private(set) var activeTrigger: Trigger?
    private var keyboardMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var focusObserver: NSObjectProtocol?
    private var previousApplication: NSRunningApplication?
    private var cursorHidden = false

    public init(mediaStore: MediaStore, preferences: ShadePreferences = ShadePreferences(), snapshots: ScreenSnapshotProviding = ScreenSnapshotProvider()) {
        self.mediaStore = mediaStore
        self.preferences = preferences
        self.snapshots = snapshots
    }

    deinit {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
        if cursorHidden {
            NSCursor.unhide()
        }
    }

    public var isActive: Bool { session.isActive }

    public func toggle() {
        isActive ? deactivate() : activate()
    }

    public func activate() {
        // A manual request owns its shade even if automation originally opened it.
        if isActive {
            activeTrigger = .manual
            lidPolicy.userDismissed()
            rebuildWindowsForCurrentScreens()
            return
        }
        _ = activate(trigger: .manual)
    }

    public func updateLidAngle(_ angle: Double?, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        lastAngle = angle
        guard preferences.automaticEnabled, !automationPaused, !displaySleeping else { return }
        guard let angle else {
            suspendAutomation()
            return
        }
        guard activeTrigger != .manual else { return }
        switch lidPolicy.update(angle: angle, at: time, triggerAngle: preferences.triggerAngle) {
        case .activate:
            if !activate(trigger: .lidAngle) { lidPolicy.reset() }
        case .deactivate:
            if activeTrigger == .lidAngle { deactivate(isUserInitiated: false, animated: true) }
        case .none:
            break
        }
        updateFrosting()
    }

    public func suspendAutomation(resetSuppression: Bool = false) {
        if resetSuppression { lidPolicy.reset() } else { lidPolicy.suspend() }
        if activeTrigger == .lidAngle { deactivate(isUserInitiated: false) }
    }

    public func refreshPreferences() {
        if !preferences.automaticEnabled { suspendAutomation() }
        rebuildWindowsForCurrentScreens()
    }

    /// Display sleep is not dismissal. Keep the last rendered cover in place so
    /// waking does not first reveal the desktop while HID/capture restarts.
    public func displayWillSleep() {
        guard !displaySleeping else { return }
        displaySleeping = true
        captureGeneration += 1
        snapshots.cancel()
        for window in displayWindows.values { window.setRenderingPaused(true) }
    }

    public func displayDidWake() {
        guard displaySleeping else { return }
        displaySleeping = false
        for window in displayWindows.values { window.setRenderingPaused(false) }
        if isActive { rebuildWindowsForCurrentScreens() }
    }

    @discardableResult
    private func activate(trigger: Trigger) -> Bool {
        guard !isActive else { return false }
        activeTrigger = trigger
        let windows = makeWindows()
        guard !windows.isEmpty, session.activate(with: windows) else {
            activeTrigger = nil
            return false
        }

        let currentApplication = NSWorkspace.shared.frontmostApplication
        if currentApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = currentApplication
        }

        installKeyboardMonitor()
        installScreenObserver()
        focusObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main
        ) { [weak self] _ in
            guard let self, !self.displaySleeping, self.currentDisplayScope == .builtIn else { return }
            guard !self.requiresShortcutToDismiss else { return }
            // The uncovered display remains usable: restore on leaving our app instead
            // of retaining an overlay that can no longer receive the restoring key.
            self.deactivate(restoreFocus: false)
        }
        NSCursor.hide()
        cursorHidden = true

        NSApp.activate(ignoringOtherApps: true)
        show(windows, animated: true)
        return true
    }

    public func deactivate(isUserInitiated: Bool = true, restoreFocus: Bool = true, animated: Bool = false) {
        guard isActive else { return }
        if isUserInitiated { lidPolicy.userDismissed() }
        activeTrigger = nil
        captureGeneration += 1
        snapshots.cancel()
        for window in displayWindows.values { window.animatesNextClose = animated }
        displayWindows.removeAll()

        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        if let focusObserver {
            NotificationCenter.default.removeObserver(focusObserver)
            self.focusObserver = nil
        }

        _ = session.deactivate()
        if cursorHidden {
            NSCursor.unhide()
            cursorHidden = false
        }

        let applicationToRestore = previousApplication
        previousApplication = nil
        guard restoreFocus else { return }
        DispatchQueue.main.async { [weak self] in
            // A queued restore must not take focus from a new shade or settings.
            guard let self, !self.isActive, !self.automationPaused else { return }
            _ = applicationToRestore?.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func makeWindows() -> [ShadeWindow] {
        let previousWindows = displayWindows
        let canReuseMode = windowEnhancementMode == preferences.enhancedFrostingEnabled && windowPresentationMode == currentPresentationMode
        windowEnhancementMode = preferences.enhancedFrostingEnabled
        windowPresentationMode = currentPresentationMode
        displayWindows.removeAll()
        let scene = activeTrigger == .lidAngle ? preferences.automaticScene : preferences.scene
        let image: NSImage?
        if activeTrigger == .manual, scene == .media, let mediaURL = mediaStore.selectedMediaURL {
            image = NSImage(contentsOf: mediaURL)
            if image == nil {
                mediaStore.useBlack()
            }
        } else {
            image = nil
        }

        let screens = NSScreen.screens.filter { screen in
            guard currentDisplayScope == .builtIn else { return true }
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        }
        return screens.map { screen in
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            let window: ShadeWindow
            if canReuseMode, let displayID, let existing = previousWindows[displayID], existing.scene == scene, scene != .media {
                window = existing
                if window.frame != screen.frame { window.setFrame(screen.frame, display: false) }
            } else {
                window = ShadeWindow(screen: screen, image: image, scene: scene) { [weak self] in
                    self?.dismissFromOrdinaryKey()
                }
            }
            window.updateFrosting(appearance: currentAppearance, progress: frostProgress, mode: currentPresentationMode)
            window.setRenderingPaused(displaySleeping)
            if let displayID {
                displayWindows[displayID] = window
            }
            return window
        }
    }

    private var frostProgress: Double {
        if activeTrigger == .manual { return preferences.manualFrostStrength }
        guard activeTrigger == .lidAngle, preferences.angleAnimationEnabled, let lastAngle else { return 1 }
        return FrostedAppearance.progress(angle: lastAngle, triggerAngle: preferences.triggerAngle)
    }

    private var currentDisplayScope: ShadeDisplayScope {
        activeTrigger == .lidAngle ? preferences.automaticDisplayScope : preferences.displayScope
    }

    private var currentAppearance: FrostedAppearance {
        activeTrigger == .lidAngle ? preferences.automaticAppearance : preferences.appearance
    }

    private var currentPresentationMode: FrostedPresentationMode {
        activeTrigger == .manual ? .manual : .lidAngle
    }

    private func updateFrosting() {
        for window in displayWindows.values {
            window.updateFrosting(appearance: currentAppearance, progress: frostProgress, mode: currentPresentationMode)
        }
    }

    private func show(_ windows: [ShadeWindow], animated: Bool = false) {
        for window in windows {
            window.present(animated: animated)
        }
        windows.first?.makeKeyAndOrderFront(nil)
    }

    private func installKeyboardMonitor() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.dismissFromOrdinaryKey()
            }
            return nil
        }
    }

    private var requiresShortcutToDismiss: Bool {
        activeTrigger == .manual && preferences.manualDismissRequiresShortcut
    }

    private func dismissFromOrdinaryKey() {
        guard !requiresShortcutToDismiss else { return }
        deactivate()
    }

    private func installScreenObserver() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildWindowsForCurrentScreens()
        }
    }

    private func rebuildWindowsForCurrentScreens() {
        guard isActive, !displaySleeping else { return }
        let windows = makeWindows()
        guard !windows.isEmpty else {
            lidPolicy.reset()
            deactivate(isUserInitiated: false)
            return
        }
        // Cover any changed display before closing replaced windows. Unchanged
        // windows retain their snapshots and animation state.
        show(windows)
        session.replace(with: windows)
    }
}
