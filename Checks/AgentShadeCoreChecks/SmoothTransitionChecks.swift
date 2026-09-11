import AppKit
@testable import AgentShadeCore

func runClearStartFrostingChecks() throws {
    for trigger in [41.0, 60, 80, 95] {
        try expect(FrostedAppearance.progress(angle: trigger, triggerAngle: trigger) == 0,
                   "Entering at the trigger angle must start clear, without a fixed frosting step")
        try expect(FrostedAppearance.progress(angle: trigger - (trigger - 40) * 0.001, triggerAngle: trigger) < 0.005,
                   "A barely crossed trigger must remain nearly clear")
        try expect(abs(FrostedAppearance.progress(angle: (trigger + 40) / 2, triggerAngle: trigger) - 0.8125) < 0.0001,
                   "Half travel must deepen past 65% strength without reaching maximum early")
        try expect(FrostedAppearance.progress(angle: 40, triggerAngle: trigger) == 1,
                   "The lower endpoint must still reach full configured frosting")
    }
}

/// No display capture or visible window: exercise the built-in fallback fade.
func runNativeStrengthGradientChecks() throws {
    let window = ShadeWindow(frame: NSRect(x: 0, y: 0, width: 400, height: 300), image: nil, scene: .frostedDark, onDismiss: {})
    defer { window.close() }
    let artwork = try fallbackArtwork(in: window)
    window.updateFrosting(appearance: FrostedAppearance(), progress: 0)
    try expect(artwork.alphaValue <= 0.001, "The built-in fallback must start clear, without a fixed artwork step")
    window.updateFrosting(appearance: FrostedAppearance(), progress: 1)
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        try expect(artwork.alphaValue > 0 && artwork.alphaValue < 0.8, "Built-in artwork visibility must ease between angle samples")
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.65))
    try expect(artwork.alphaValue > 0.99, "The built-in background must reach full strength at the closing endpoint")
    window.updateFrosting(appearance: FrostedAppearance(), progress: 0.5)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.65))
    try expect(abs(artwork.alphaValue - 0.5) < 0.01, "Built-in fallback must follow the same half-strength target as enhanced frosting")
    try expect(window.contentView?.hitTest(NSPoint(x: 1, y: 1)) === window.contentView,
               "A visually clear cover must still intercept input across the entire screen")
}

/// The provider returns no images, so this checks the permission-free path.
func runManualFrostedStrengthChecks() throws {
    let suite = "AgentShadeChecks.ManualStrength.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShadePreferences(defaults: defaults)
    preferences.scene = .frostedDark
    preferences.displayScope = .all
    preferences.enhancedFrostingEnabled = false
    let controller = ShadeController(mediaStore: MediaStore(), preferences: preferences, snapshots: SyntheticSnapshotProvider())
    defer { controller.deactivate(isUserInitiated: false) }
    controller.updateLidAngle(35, at: 0)
    controller.activate()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.65))
    let windows = NSApp.windows.compactMap { $0 as? ShadeWindow }.filter(\.isVisible)
    try expect(!windows.isEmpty && windows.count == NSScreen.screens.count,
               "A manual all-display shade must cover every connected screen")
    for window in windows {
        let artwork = try fallbackArtwork(in: window)
        try expect(artwork.alphaValue == 1 && preferences.manualFrostStrength == 0.5, "Manual half strength must adjust the material, never reveal unblurred desktop pixels")
        try expect(NSScreen.screens.contains { $0.frame == window.frame }, "Half strength must preserve full-screen window bounds")
        try expect(window.contentView?.bounds.size == window.frame.size, "Half strength must fill the entire overlay")
    }
}

func runSmoothProgressChecks() throws {
    var smoother = FrostedProgressSmoother(value: 0.2)
    smoother.retarget(1)
    try expect(smoother.value == 0.2, "A sensor update must not instantly jump the displayed effect")
    smoother.advance(by: 1.0 / 60)
    try expect(smoother.value > 0.2 && smoother.value < 0.5, "A single frame must interpolate, not jump to full frosting")
    for _ in 0..<35 { smoother.advance(by: 1.0 / 60) }
    try expect(abs(smoother.value - 1) < 0.002 && !smoother.needsFrames, "A settled lid must converge and stop animation work")
    smoother.retarget(0)
    let previous = smoother.value
    smoother.advance(by: 1.0 / 60)
    try expect(smoother.value > 0 && smoother.value < previous, "Opening must smoothly reverse direction")
    smoother.retarget(.nan)
    try expect(smoother.target.isFinite, "Invalid input must not poison an animation")
    try expect(FrostedAppearance.progress(angle: 84, triggerAngle: 80) < 0.05, "The restore band must approach clear before dismissing, not retain a 22% step")
    try expect(FrostedAppearance.progress(angle: 85, triggerAngle: 80) == 0, "The effect must be clear at the configured restore angle")
}

/// Exercises the real controller with synthetic display pixels only.
func runDisplayWakeTransitionChecks() throws {
    let suite = "AgentShadeChecks.Wake.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = ShadePreferences(defaults: defaults)
    settings.scene = .frostedDark
    settings.automaticEnabled = true
    settings.automaticDisplayScope = .builtIn
    let provider = SyntheticSnapshotProvider()
    let controller = ShadeController(mediaStore: MediaStore(), preferences: settings, snapshots: provider)
    defer { controller.deactivate(isUserInitiated: false) }
    controller.updateLidAngle(50, at: 0)
    controller.updateLidAngle(50, at: 0.2)
    try expect(controller.isActive, "The wake test requires an actual overlay")
    let windows = NSApp.windows.compactMap { $0 as? ShadeWindow }.filter(\.isVisible)
    let captureCount = provider.requests
    controller.displayWillSleep()
    NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
    try expect(controller.isActive && controller.activeTrigger == .lidAngle, "Display sleep must preserve automatic coverage, not expose the desktop on wake")
    controller.displayDidWake()
    try expect(provider.requests == captureCount + 1, "Wake must refresh the stale snapshot while keeping old coverage")
    controller.displayDidWake()
    try expect(provider.requests == captureCount + 1, "Duplicate system/display wake notifications must not recapture twice")
    NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    try expect(windows.allSatisfy(\.isVisible), "An unchanged display notification must retain existing windows instead of closing them")
    controller.updateLidAngle(85, at: 1)
    try expect(!controller.isActive, "A fresh upright reading must still dismiss after wake")
    controller.displayWillSleep()
    controller.displayDidWake()
    try expect(!controller.isActive, "Waking an inactive session must not spontaneously shade")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
}

func runEnhancementModeReuseChecks() throws {
    let suite = "AgentShadeChecks.EnhancementMode.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShadePreferences(defaults: defaults)
    preferences.scene = .frostedDark
    preferences.automaticEnabled = true
    let provider = SyntheticSnapshotProvider()
    let image = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    image.setFillColor(NSColor.blue.cgColor)
    image.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    provider.image = image.makeImage()
    let controller = ShadeController(mediaStore: MediaStore(), preferences: preferences, snapshots: provider)
    defer { controller.deactivate(isUserInitiated: false) }
    controller.updateLidAngle(40, at: 0)
    controller.updateLidAngle(40, at: 0.2)
    let old = NSApp.windows.compactMap { $0 as? ShadeWindow }.filter(\.isVisible)
    let fallback = old.first!.contentView!.subviews.compactMap { $0 as? BuiltInFrostedView }.first!
    let deadline = Date(timeIntervalSinceNow: 2)
    while !fallback.isHidden && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
    try expect(fallback.isHidden, "The regression requires a displayed enhanced snapshot")
    preferences.enhancedFrostingEnabled = false
    controller.refreshPreferences()
    let current = NSApp.windows.compactMap { $0 as? ShadeWindow }.filter(\.isVisible)
    for window in current {
        let fallback = window.contentView!.subviews.compactMap { $0 as? BuiltInFrostedView }.first!
        let enhanced = window.contentView!.subviews.compactMap { $0 as? FrostedImageView }.first!
        try expect(!fallback.isHidden && enhanced.layer?.contents == nil, "Disabling enhancement must restore built-in artwork and release captured pixels")
    }
    try expect(controller.isActive, "Disabling enhancement must retain usable built-in coverage")
}

func runFrostedHandoffChecks() throws {
    let window = ShadeWindow(frame: NSRect(x: 80, y: 80, width: 400, height: 300), image: nil, scene: .frostedDark, onDismiss: {})
    defer { window.close() }
    window.present(animated: false)
    let content = window.contentView!
    let fallback = content.subviews.compactMap { $0 as? BuiltInFrostedView }.first!
    let frost = content.subviews.compactMap { $0 as? FrostedImageView }.first!
    let context = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 256,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.systemBlue.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
    window.setSnapshot(context.makeImage()!)
    let deadline = Date(timeIntervalSinceNow: 2)
    while frost.layer?.contents == nil && Date() < deadline {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
    }
    try expect(frost.layer?.contents != nil, "The synthetic enhanced frame must render")
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        try expect(!fallback.isHidden, "The first enhanced frame must not immediately remove the built-in background")
    }
    while !fallback.isHidden && Date() < deadline {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }
    try expect(fallback.isHidden && frost.alphaValue == 1, "Built-in fallback must retire only after the enhanced fade finishes")
    window.setRenderingPaused(true)
    let retained = frost.layer?.contents as AnyObject?
    window.close()
    try expect(retained != nil && frost.layer?.contents == nil, "Closing a paused overlay must still release its displayed snapshot")
}

func runFrostedDismissalChecks() throws {
    weak var retiringWindow: ShadeWindow?
    autoreleasepool {
        let window = ShadeWindow(frame: NSRect(x: 80, y: 80, width: 400, height: 300), image: nil, scene: .frostedDark, onDismiss: {})
        retiringWindow = window
        window.present(animated: false)
        window.animatesNextClose = true
        window.close()
    }
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        try expect(retiringWindow?.isVisible == true && retiringWindow?.ignoresMouseEvents == true, "Automatic fade must survive release by its session without blocking input")
    }
    let deadline = Date(timeIntervalSinceNow: 1)
    while retiringWindow?.isVisible == true && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
    try expect(retiringWindow?.isVisible != true, "Automatic restoration must finish closing, not retain a transparent cover")
}

private final class SyntheticSnapshotProvider: ScreenSnapshotProviding {
    var requests = 0
    var image: CGImage?
    func capture(displayIDs: [CGDirectDisplayID], completion: @escaping ([CGDirectDisplayID: CGImage]) -> Void) {
        requests += 1
        if let image { completion(Dictionary(uniqueKeysWithValues: displayIDs.map { ($0, image) })) }
        else { completion([:]) } // Deliberately unavailable: must retain built-in fallback.
    }
    func cancel() {}
}

private func fallbackArtwork(in window: ShadeWindow) throws -> NSImageView {
    guard let fallback = window.contentView?.subviews.compactMap({ $0 as? BuiltInFrostedView }).first,
          let artwork = fallback.subviews.compactMap({ $0 as? NSImageView }).first,
          artwork.image != nil else { throw CheckFailure.failed("The overlay must contain built-in fallback artwork") }
    return artwork
}
