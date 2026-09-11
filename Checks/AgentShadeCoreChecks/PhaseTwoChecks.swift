import AppKit
@testable import AgentShadeCore

func runLidAnglePolicyChecks() throws {
    let policy = LidAnglePolicy()
    try expect(policy.update(angle: 98, at: 0) == .none, "An upright lid must not shade")
    try expect(policy.update(angle: 80, at: 1) == .none, "Exactly 80 degrees must not trigger")
    try expect(policy.update(angle: 79, at: 2) == .none, "A single low reading must be debounced")
    try expect(policy.update(angle: 81, at: 2.05) == .none, "A bounce must cancel the pending trigger")
    try expect(policy.update(angle: 79, at: 3) == .none, "A new low interval must start fresh")
    try expect(policy.update(angle: 79, at: 3.15) == .activate, "A stable angle below 80 must activate")
    try expect(policy.update(angle: 70, at: 4) == .none, "Continued low readings must not reactivate")
    try expect(policy.update(angle: 84, at: 5) == .none, "The hysteresis band must preserve the shade")
    try expect(policy.update(angle: 85, at: 6) == .deactivate, "Raising to 85 must restore")

    _ = policy.update(angle: 60, at: 7)
    try expect(policy.update(angle: 60, at: 7.2) == .activate, "A second lowering must work")
    policy.userDismissed()
    policy.suspend()
    try expect(policy.update(angle: 60, at: 8) == .none, "A restoring key must suppress repeated low-angle triggers")
    try expect(policy.update(angle: 84, at: 9) == .none, "Suppression must last until the lid is raised")
    try expect(policy.update(angle: 85, at: 10) == .none, "Rearming must not emit a spurious restore")
    _ = policy.update(angle: 60, at: 11)
    try expect(policy.update(angle: 60, at: 11.2) == .activate, "Raising then lowering must rearm")
    policy.reset()
    try expect(policy.update(angle: 90, at: 12) == .none, "Reset must clear an active trigger")

    _ = policy.update(angle: 60, at: 20)
    _ = policy.update(angle: .nan, at: 20.1)
    try expect(policy.update(angle: 60, at: 21) == .none, "Invalid samples must break debounce continuity")
    policy.reset()
    try expect(policy.update(angle: -1, at: 22) == .none, "Negative angles must not mean closed")
    try expect(policy.update(angle: 181, at: 23) == .none, "Out-of-range reports must be ignored")

    try expect(LidAngleMonitor.decodeReport([1, 98, 0]) == 98, "A sensor feature report must decode degrees")
    try expect(LidAngleMonitor.decodeReport([1, 0, 0]) == 0, "A valid closed-lid angle must remain zero")
    try expect(LidAngleMonitor.decodeReport([1, 98]) == nil, "Truncated reports must not produce angles")
    try expect(LidAngleMonitor.decodeReport([2, 98, 0]) == nil, "Unexpected report IDs must be rejected")
    try expect(LidAngleMonitor.decodeReport([1, 255, 255]) == nil, "Invalid raw values must not activate automation")
}

func runShadePreferencesChecks() throws {
    let suite = "AgentShadeChecks.Settings.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = ShadePreferences(defaults: defaults)
    try expect(!settings.automaticEnabled, "Lid automation must be opt-in")
    defaults.set("previous-background.gif", forKey: MediaStore.preferenceKey)
    try expect(settings.scene == .media, "Existing image selections must survive the upgrade")
    settings.scene = .frostedDark
    settings.automaticEnabled = true
    settings.displayScope = .builtIn
    let reloaded = ShadePreferences(defaults: defaults)
    try expect(reloaded.scene == .frostedDark && reloaded.automaticScene == .frostedDark, "Frosted selections must persist")
    reloaded.scene = .black
    try expect(reloaded.automaticScene == .frostedDark, "Selecting black must not turn automatic shading black")
    try expect(reloaded.automaticEnabled && reloaded.displayScope == .builtIn, "Automation and display preferences must persist")
}

func runFrostedWindowChecks() throws {
    for scene in [ShadeScene.frostedDark] {
        let window = ShadeWindow(frame: NSRect(x: 0, y: 0, width: 640, height: 480), image: nil, scene: scene, onDismiss: {})
        defer { window.close() }
        try expect(!window.isOpaque && window.backgroundColor == .clear, "Frosted windows must support a clear starting point")
        let fallback = window.contentView?.subviews.compactMap { $0 as? BuiltInFrostedView }.first
        let artwork = fallback?.subviews.compactMap { $0 as? NSImageView }.first
        try expect(fallback != nil && artwork?.image != nil, "Frosted shading must include app-owned artwork without a captured desktop")
        try expect(fallback?.isHidden == false, "Fallback artwork must be available until an enhanced frame is ready")
        try expect(window.contentView?.hitTest(NSPoint(x: 320, y: 240)) === window.contentView, "Frosted content must swallow mouse input")
        try expect(!window.isReleasedWhenClosed, "Frosted windows must retain ARC-safe lifetime management")
    }
}

/// Opt-in because this exercises actual full-screen windows and briefly takes focus.
func runLidControllerIntegrationChecks() throws {
    try expect(!NSScreen.screens.isEmpty, "A logged-in graphical session is required")
    let suite = "AgentShadeChecks.Controller.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = ShadePreferences(defaults: defaults)
    settings.scene = .frostedDark
    settings.automaticEnabled = true
    settings.enhancedFrostingEnabled = false // This check never captures the user's desktop.
    let controller = ShadeController(mediaStore: MediaStore(), preferences: settings)
    defer { controller.deactivate(isUserInitiated: false) }

    controller.updateLidAngle(79, at: 0)
    controller.updateLidAngle(79, at: 0.2)
    try expect(controller.isActive && controller.activeTrigger == .lidAngle, "Debounced sensor input must show real automatic windows")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    controller.updateLidAngle(85, at: 1)
    try expect(!controller.isActive, "Raising must close automatic windows")

    controller.activate()
    controller.updateLidAngle(85, at: 2)
    controller.updateLidAngle(nil, at: 3)
    try expect(controller.isActive && controller.activeTrigger == .manual, "Sensor recovery or failure must not dismiss manual windows")
    controller.deactivate()
    controller.updateLidAngle(nil, at: 3.5)
    controller.updateLidAngle(70, at: 4)
    controller.updateLidAngle(70, at: 4.2)
    try expect(!controller.isActive, "A user dismissal must suppress reactivation")
    controller.updateLidAngle(85, at: 5)
    controller.updateLidAngle(70, at: 6)
    controller.updateLidAngle(70, at: 6.2)
    try expect(controller.activeTrigger == .lidAngle, "A complete raise/lower cycle must rearm real windows")

    controller.activate()
    try expect(controller.activeTrigger == .manual, "A manual request must take ownership of an automatic shade")
    settings.automaticEnabled = false
    controller.refreshPreferences()
    try expect(controller.isActive, "Disabling automation must preserve a manual shade")
    controller.deactivate()
    settings.automaticEnabled = true
    controller.suspendAutomation(resetSuppression: true)
    controller.updateLidAngle(70, at: 7)
    controller.updateLidAngle(70, at: 7.2)
    settings.automaticEnabled = false
    controller.refreshPreferences()
    try expect(!controller.isActive, "Disabling automation must release its own shade")

    settings.displayScope = .all
    settings.automaticEnabled = true
    settings.triggerAngle = 60
    controller.suspendAutomation(resetSuppression: true)
    controller.updateLidAngle(70, at: 8)
    controller.updateLidAngle(70, at: 8.2)
    try expect(!controller.isActive, "Controller must use the configured threshold, not a hardcoded 80")
    controller.updateLidAngle(59, at: 9)
    controller.updateLidAngle(59, at: 9.2)
    try expect(controller.isActive, "A custom threshold must activate real windows")
    controller.automationPaused = true
    try expect(!controller.isActive, "Opening settings must remove an automatic overlay")
    controller.updateLidAngle(50, at: 10)
    controller.updateLidAngle(50, at: 10.2)
    try expect(!controller.isActive, "Preview adjustment must not trigger real overlays")
    controller.automationPaused = false
    controller.updateLidAngle(50, at: 11)
    controller.updateLidAngle(50, at: 11.2)
    try expect(controller.isActive, "Closing settings must resume the current lid cycle without requiring an extra raise")
    controller.updateLidAngle(65, at: 12)
    controller.updateLidAngle(50, at: 13)
    controller.updateLidAngle(50, at: 13.2)
    try expect(controller.isActive, "Raising after settings must rearm automation")
    controller.deactivate()
    controller.activate()
    NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
    try expect(controller.isActive, "All-display coverage must not dismiss on an unrelated focus notification")
    controller.deactivate()
    settings.displayScope = .builtIn
    controller.activate()
    if controller.isActive {
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        try expect(!controller.isActive, "Built-in-only shading must restore before input moves to an uncovered application")
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
}

/// Optional real-HID check; does not open overlay windows or change preferences.
func runLidMonitorHardwareChecks() throws {
    let monitor = LidAngleMonitor()
    var angles: [Double] = []
    monitor.onUpdate = { status in
        if case .available(let angle) = status { angles.append(angle) }
    }
    monitor.start()
    let deadline = Date(timeIntervalSinceNow: 3)
    while angles.count < 3 && Date() < deadline {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }
    monitor.stop()
    let countAtStop = angles.count
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
    try expect(countAtStop >= 3, "A readable sensor is required for the optional hardware check")
    try expect(angles.count == countAtStop, "Stopped readers must discard pending angle callbacks")
    print("PASS: real HID monitor (\(countAtStop) samples, last \(Int(angles.last ?? 0))°)")
}
