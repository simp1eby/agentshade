import AppKit
import Carbon
@testable import AgentShadeCore

private struct SettingsAccess: ScreenCapturePermissionChecking {
    var isGranted: Bool { true }
    func requestAccess() -> Bool { false }
}

private func controls(in view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + controls(in: $0) }
}

private final class DelayedGraySnapshot: ScreenSnapshotProviding {
    var requests = 0
    func capture(displayIDs: [CGDirectDisplayID], completion: @escaping ([CGDirectDisplayID: CGImage]) -> Void) {
        requests += 1
        let bitmap = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.setFillColor(CGColor(gray: 0.8, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = bitmap.makeImage()!
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { completion(Dictionary(uniqueKeysWithValues: displayIDs.map { ($0, image) })) }
    }
    func cancel() {}
}

func runStableManualArtworkChecks() throws {
    _ = NSApplication.shared
    let suite = "AgentShadeChecks.StableManual.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShadePreferences(defaults: defaults)
    preferences.scene = .frostedDark
    preferences.automaticEnabled = true
    let provider = DelayedGraySnapshot()
    let store = MediaStore(fileManager: .default, defaults: defaults, applicationSupportURL: FileManager.default.temporaryDirectory.appendingPathComponent(suite))
    let shade = ShadeController(mediaStore: store, preferences: preferences, snapshots: provider)
    defer { shade.deactivate(restoreFocus: false) }
    shade.activate()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.45))
    try expect(provider.requests == 0, "Shortcut frosting must keep the initial blue artwork instead of requesting a replacement desktop snapshot")
    func expectArtwork() throws {
        let windows = NSApp.windows.compactMap { $0 as? ShadeWindow }.filter(\.isVisible)
        try expect(!windows.isEmpty, "Stable manual artwork must cover the displays")
        for window in windows {
            let children = controls(in: window.contentView!)
            let artwork = children.compactMap { $0 as? BuiltInFrostedView }.first!
            let snapshot = children.compactMap { $0 as? FrostedImageView }.first!
            try expect(!artwork.isHidden && snapshot.layer?.contents == nil, "Manual frosting must never change to gray snapshot pixels")
        }
    }
    try expectArtwork()
    shade.deactivate(restoreFocus: false)
    shade.updateLidAngle(100, at: 0)
    shade.updateLidAngle(60, at: 1)
    shade.updateLidAngle(60, at: 1.2)
    try expect(provider.requests == 1, "Lid frosting must retain enhanced snapshot support")
    shade.activate() // Promote a lid overlay while its old capture is still pending.
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.45))
    try expectArtwork()
    try expect(provider.requests == 1, "A delayed lid snapshot must not trigger a new manual capture")
    print("PASS: stable blue shortcut artwork, enhanced lid capture and late-frame isolation")
}

func runShortcutDismissalChecks() throws {
    _ = NSApplication.shared
    let suite = "AgentShadeChecks.Dismissal.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShadePreferences(defaults: defaults, preferredLanguages: ["en"])
    preferences.enhancedFrostingEnabled = false
    let store = MediaStore(fileManager: .default, defaults: defaults, applicationSupportURL: FileManager.default.temporaryDirectory.appendingPathComponent(suite))
    let shade = ShadeController(mediaStore: store, preferences: preferences)
    defer { shade.deactivate(restoreFocus: false) }
    func window() throws -> ShadeWindow {
        guard let result = NSApp.windows.compactMap({ $0 as? ShadeWindow }).first(where: \.isVisible) else {
            throw CheckFailure.failed("Expected a real shade window")
        }
        return result
    }
    func key(_ window: ShadeWindow, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "a", charactersIgnoringModifiers: "a",
            isARepeat: false, keyCode: UInt16(kVK_ANSI_A))!
    }
    shade.activate()
    try window().keyDown(with: key(try window()))
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
    try expect(!shade.isActive, "Default settings must dismiss on an ordinary key")

    defaults.set(true, forKey: "manualDismissRequiresShortcut")
    shade.activate()
    let locked = try window()
    locked.keyDown(with: key(locked))
    _ = locked.performKeyEquivalent(with: key(locked, flags: .command))
    NSApp.sendEvent(key(locked)) // Exercise the controller's local event monitor too.
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
    try expect(shade.isActive, "Shortcut-only mode must swallow ordinary keys and unrelated Command combinations")
    shade.toggle() // Same action dispatched by the registered global shortcut.
    try expect(!shade.isActive, "Pressing the registered shortcut again must close a shortcut-only shade")
    preferences.displayScope = .builtIn
    shade.activate()
    if shade.isActive {
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        try expect(shade.isActive, "Shortcut-only manual shading must not dismiss when focus moves to an uncovered screen")
        shade.toggle()
    }
    preferences.displayScope = .all

    preferences.automaticEnabled = true
    preferences.triggerAngle = 80
    shade.updateLidAngle(100, at: 0)
    shade.updateLidAngle(60, at: 1)
    shade.updateLidAngle(60, at: 1.2)
    try expect(shade.isActive && shade.activeTrigger == .lidAngle, "Lid shading must still activate with shortcut-only manual mode")
    shade.updateLidAngle(90, at: 2)
    try expect(!shade.isActive, "Opening the lid must still dismiss automatic shading")

    let settings = FrostedSettingsWindowController(preferences: preferences, permissions: SettingsAccess(), onChange: {}, onClose: {})
    defer { settings.window?.close() }
    guard let button = controls(in: settings.window!.contentView!).first(where: { $0.identifier?.rawValue == "manualDismissRequiresShortcut" }) as? NSButton else {
        throw CheckFailure.failed("Shortcut settings must expose the persisted dismissal option")
    }
    try expect(button.state == .on && button.title.contains("shortcut"), "Reopened English settings must reflect the saved option")
    button.performClick(nil)
    try expect(!defaults.bool(forKey: "manualDismissRequiresShortcut"), "Turning the setting off must persist")
    preferences.language = .chinese
    settings.refreshLanguage()
    try expect(button.title.contains("快捷键"), "The new setting must follow the Chinese language selection")
    print("PASS: default and shortcut-only dismissal, lid isolation, persisted bilingual setting")
}

private final class OcclusionCoverWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

func runSettingsOcclusionChecks() throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    NSApp.finishLaunching()
    func pumpEvents(for duration: TimeInterval) {
        let deadline = Date(timeIntervalSinceNow: duration)
        repeat {
            while let event = NSApp.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        } while Date() < deadline
    }
    let suite = "AgentShadeChecks.Focus.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShadePreferences(defaults: defaults)
    preferences.automaticEnabled = true
    preferences.enhancedFrostingEnabled = false
    let store = MediaStore(fileManager: .default, defaults: defaults, applicationSupportURL: FileManager.default.temporaryDirectory.appendingPathComponent(suite))
    let shade = ShadeController(mediaStore: store, preferences: preferences)
    var closes = 0
    let settings = FrostedSettingsWindowController(preferences: preferences, permissions: SettingsAccess(), onChange: {}, onClose: {
        closes += 1
        shade.automationPaused = false
    })
    defer { settings.window?.close(); shade.deactivate(restoreFocus: false) }
    shade.updateLidAngle(60, at: 0)
    shade.updateLidAngle(60, at: 0.2)
    try expect(shade.isActive, "The settings entry fixture must begin with an automatic shade")
    shade.automationPaused = true
    let window = settings.window!
    window.level = .floating
    settings.show()
    pumpEvents(for: 0.2)
    try expect(window.isVisible && closes == 0 && shade.automationPaused,
               "Opening settings from a lid shade must not let an old focus restoration close the new settings")
    window.resignKey()
    (settings as NSWindowDelegate).windowDidResignKey?(Notification(name: NSWindow.didResignKeyNotification, object: window))
    NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
    pumpEvents(for: 0.05)
    try expect(window.isVisible && closes == 0 && shade.automationPaused,
               "An unobscured settings window must stay open when keyboard or app focus changes")
    window.miniaturize(nil)
    pumpEvents(for: 0.25)
    try expect(closes == 0, "Minimizing is not coverage by another window and must preserve settings")
    window.deminiaturize(nil)
    window.makeKeyAndOrderFront(nil)
    pumpEvents(for: 0.25)

    let half = NSRect(x: window.frame.minX, y: window.frame.minY, width: window.frame.width / 2, height: window.frame.height)
    let cover = OcclusionCoverWindow(contentRect: half, styleMask: .borderless, backing: .buffered, defer: false)
    cover.isReleasedWhenClosed = false
    cover.isOpaque = true; cover.backgroundColor = .black; cover.hasShadow = false
    cover.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
    defer { cover.close() }
    cover.makeKeyAndOrderFront(nil)
    pumpEvents(for: 0.2)
    try expect(window.isVisible && window.occlusionState.contains(.visible) && closes == 0,
               "Partial coverage by another key window must retain settings (visible=\(window.isVisible), occlusion=\(window.occlusionState.rawValue), closes=\(closes), frame=\(window.frame), cover=\(cover.frame), appHidden=\(NSApp.isHidden))")

    var interactionStayedOpen = false
    settings.onChooseMedia = {
        cover.setFrame(window.frame, display: true)
        pumpEvents(for: 0.2)
        interactionStayedOpen = window.isVisible && closes == 0
        cover.setFrame(half, display: true)
        pumpEvents(for: 0.1)
    }
    let picker = controls(in: window.contentView!).first { $0.identifier?.rawValue == "chooseMedia" } as! NSButton
    picker.performClick(nil)
    try expect(interactionStayedOpen, "An app-owned image picker may temporarily cover settings without closing it")
    settings.onChooseMedia = nil
    cover.setFrame(window.frame, display: true)
    let deadline = Date(timeIntervalSinceNow: 2)
    while window.isVisible && Date() < deadline { pumpEvents(for: 0.02) }
    try expect(!window.isVisible && closes == 1 && !shade.automationPaused,
               "Full occlusion must close settings once and resume lid automation (visible=\(window.isVisible), occlusion=\(window.occlusionState.rawValue), closes=\(closes), paused=\(shade.automationPaused))")
    shade.updateLidAngle(60, at: 1)
    shade.updateLidAngle(60, at: 1.2)
    try expect(shade.isActive, "Resuming after settings must not leave the current lid cycle suppressed")
    print("PASS: focus/partial visibility retained; full occlusion closes and resumes lid shading")
}

func runConfigurableLidRadiusWithoutAccessChecks() throws {
    _ = NSApplication.shared
    let suite = "AgentShadeChecks.LidRadius.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    struct NoAccess: ScreenCapturePermissionChecking {
        var isGranted: Bool { false }
        func requestAccess() -> Bool { false }
    }
    let preferences = ShadePreferences(defaults: defaults, preferredLanguages: ["en"])
    preferences.automaticBlurRadius = 46
    let settings = FrostedSettingsWindowController(preferences: preferences, permissions: NoAccess(), onChange: {}, onClose: {})
    defer { settings.window?.close() }
    let children = controls(in: settings.window!.contentView!)
    (children.first { $0.identifier?.rawValue == "settingsTab.lid" } as! NSButton).performClick(nil)
    func radiusIsVisible() -> Bool {
        controls(in: settings.window!.contentView!).contains { $0.identifier?.rawValue == "automaticBlur" && !$0.isHiddenOrHasHiddenAncestor }
    }
    try expect(!radiusIsVisible(), "Lid blur radius must be hidden without current capture access")
    try expect(ShadePreferences(defaults: defaults).automaticBlurRadius == 46, "Opening settings without capture access must preserve the saved lid radius")
    preferences.enhancedFrostingEnabled = false
    settings.refreshPreferences()
    try expect(!radiusIsVisible() && ShadePreferences(defaults: defaults).automaticBlurRadius == 46, "Turning snapshots off must keep the ineffective radius hidden without resetting its saved value")
    preferences.enhancedFrostingEnabled = true
    settings.refreshPreferences()
    try expect(!radiusIsVisible() && ShadePreferences(defaults: defaults).automaticBlurRadius == 46, "Re-enabling snapshots without capture access must keep the radius hidden and preserve its saved value")
    guard let status = children.first(where: { $0.identifier?.rawValue == "lidRecordingExplanation" }) as? NSTextField else {
        throw CheckFailure.failed("Missing visible lid recording explanation")
    }
    try expect(!status.isHiddenOrHasHiddenAncestor && status.stringValue.contains("not available"), "The lid page must visibly explain why current capture access is unavailable")
    print("PASS: ineffective lid radius stays hidden while its saved value survives permission-free refreshes")
}

func runSliderProgressChecks() throws {
    _ = NSApplication.shared
    let suite = "AgentShadeChecks.Slider.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShadePreferences(defaults: defaults)
    preferences.scene = .frostedDark
    let settings = FrostedSettingsWindowController(preferences: preferences, permissions: SettingsAccess(), onChange: {}, onClose: {})
    defer { settings.window?.close() }
    settings.window?.appearance = NSAppearance(named: .darkAqua)
    let content = settings.window!.contentView!
    content.layoutSubtreeIfNeeded()
    let sliders = controls(in: content).compactMap { $0 as? NSSlider }
    func bluePixels(_ slider: NSSlider, fraction: Double, enabled: Bool) throws -> Int {
        slider.isEnabled = enabled
        slider.doubleValue = slider.minValue + fraction * (slider.maxValue - slider.minValue)
        let pixels = slider.bitmapImageRepForCachingDisplay(in: slider.bounds)!
        slider.cacheDisplay(in: slider.bounds, to: pixels)
        var blue = 0
        for x in 0..<pixels.pixelsWide { for y in 0..<pixels.pixelsHigh {
            if let c = pixels.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
               c.blueComponent > c.redComponent + 0.3, c.blueComponent > c.greenComponent + 0.1 { blue += 1 }
        } }
        return blue
    }
    for slider in sliders {
        let quarter = try bluePixels(slider, fraction: 0.25, enabled: true)
        let threeQuarters = try bluePixels(slider, fraction: 0.75, enabled: true)
        try expect(quarter > 30 && threeQuarters > quarter * 2,
                   "Enabled slider \(slider.identifier?.rawValue ?? "") must paint blue progress proportional to its value, even without focus")
        let disabled = try bluePixels(slider, fraction: 0.75, enabled: false)
        try expect(disabled == 0, "Disabled sliders must not imply an active blue control")
    }
    print("PASS: proportional blue slider progress and disabled state")
}
