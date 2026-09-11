import AppKit
@testable import AgentShadeCore

func runDefaultBlurRadiusChecks() throws {
    let suite = "AgentShadeChecks.DefaultRadius.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShadePreferences(defaults: defaults)
    try expect(preferences.automaticAppearance.blurRadius == 20,
               "A fresh installation must render lid frosting with a default radius of 20, including first-run migration")
    try expect(FrostedAppearance().blurRadius == 20, "The renderer's default must agree with the saved-settings default")
    preferences.automaticBlurRadius = 47
    try expect(ShadePreferences(defaults: defaults).automaticAppearance.blurRadius == 47,
               "Changing the default must not overwrite a user's explicitly saved radius")
    preferences.automaticBlurRadius = .nan
    try expect(preferences.automaticAppearance.blurRadius == 20, "Invalid radius input must recover to the new default")
    defaults.removeObject(forKey: "automaticFrostedBlurRadius")
    try expect(preferences.automaticAppearance.blurRadius == 20, "An absent migrated radius must use the same default")
    print("PASS: default radius 20, first-run migration, preserved custom radius and safe fallback")
}

func runIndependentSettingsMigrationChecks() throws {
    let suite = "AgentShadeChecks.IndependentFrosting.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("builtIn", forKey: "shadeDisplayScope")
    defaults.set(41.0, forKey: "frostedBlurRadius")
    defaults.set(0.27, forKey: "frostedTintOpacity")
    let preferences = ShadePreferences(defaults: defaults)
    try expect(preferences.scene == .black, "Manual shading must default to black for a new scene selection")
    try expect(defaults.string(forKey: "automaticShadeDisplayScope") == "builtIn",
               "The old shared scope must migrate to lid shading before either setting changes")
    try expect(defaults.double(forKey: "automaticFrostedBlurRadius") == 41 && defaults.double(forKey: "automaticFrostedTintOpacity") == 0.27,
               "Old shared appearance values must migrate to independent lid settings")
    preferences.displayScope = .all
    preferences.blurRadius = 12
    preferences.tintOpacity = 0.08
    _ = ShadePreferences(defaults: defaults)
    try expect(defaults.string(forKey: "automaticShadeDisplayScope") == "builtIn"
               && defaults.double(forKey: "automaticFrostedBlurRadius") == 41
               && defaults.double(forKey: "automaticFrostedTintOpacity") == 0.27,
               "Changing manual settings and reloading must not overwrite migrated lid settings")
    defaults.set(55.0, forKey: "automaticFrostedBlurRadius")
    _ = ShadePreferences(defaults: defaults)
    try expect(defaults.double(forKey: "automaticFrostedBlurRadius") == 55 && preferences.blurRadius == 12,
               "Migration must run once and preserve later independent edits")
    try expect(preferences.automaticDisplayScope == .builtIn && preferences.automaticBlurRadius == 55 && preferences.automaticTintOpacity == 0.27,
               "Automatic accessors must read the independent persisted values")
    preferences.automaticDisplayScope = .all
    preferences.automaticBlurRadius = 47
    preferences.automaticTintOpacity = 0.32
    try expect(preferences.blurRadius == 12 && preferences.tintOpacity == 0.08,
               "Editing the lid appearance must leave manual settings unchanged")
    try expect(preferences.appearance.blurRadius == 12 && preferences.automaticAppearance.blurRadius == 47,
               "Each renderer appearance must use its own trigger's values")
    try expect(preferences.manualFrostStrength == 0.5, "Manual frosting must default to half strength")
    preferences.manualFrostStrength = 2
    try expect(preferences.manualFrostStrength == 1, "Saved manual strength must be bounded")
    preferences.manualFrostStrength = .nan
    try expect(preferences.manualFrostStrength == 0.5, "Invalid manual strength must use its safe default")
    preferences.scene = .media
    try expect(preferences.automaticScene == .frostedDark, "A manual custom image must never become the lid scene")
}

func runRemovedStretchChecks() throws {
    let appearance = FrostedAppearance(blurRadius: 0, tintOpacity: 0, stretchAmount: 0.3)
    try expect(appearance.stretchAmount == 0, "Legacy stretch input must no longer deform the image")
    guard let bitmap = CGContext(data: nil, width: 24, height: 24, bitsPerComponent: 8, bytesPerRow: 96,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw CheckFailure.failed("Cannot create the stretch-removal bitmap fixture")
    }
    bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
    bitmap.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
    bitmap.setFillColor(CGColor(gray: 0, alpha: 1))
    bitmap.fill(CGRect(x: 0, y: 0, width: 24, height: 12))
    guard let source = bitmap.makeImage(),
          let rendered = FrostedImageRenderer().render(source: source, scene: .frostedDark, appearance: appearance, progress: 1) else {
        throw CheckFailure.failed("The stretch-removal renderer must produce an unchanged bitmap")
    }
    let original = NSBitmapImageRep(cgImage: source)
    let result = NSBitmapImageRep(cgImage: rendered)
    for y in [8, 11, 12, 14, 18] {
        guard let originalColor = original.colorAt(x: 12, y: y)?.usingColorSpace(.deviceRGB),
              let resultColor = result.colorAt(x: 12, y: y)?.usingColorSpace(.deviceRGB) else {
            throw CheckFailure.failed("Cannot inspect the stretch-removal bitmap pixels")
        }
        let before = originalColor.redComponent
        let after = resultColor.redComponent
        try expect(abs(before - after) < 0.02, "Removing stretch must preserve the position of an unblurred image edge")
    }
}

/// No visible window and no screen capture: inspect the actual fallback contents.
func runBuiltInFrostedFallbackChecks() throws {
    try runFrostedPerceptualScaleChecks()
    let window = ShadeWindow(frame: NSRect(x: 0, y: 0, width: 400, height: 300), image: nil, scene: .frostedDark, onDismiss: {})
    defer { window.close() }
    let content = window.contentView!
    func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
    let children = descendants(content)
    try expect(children.allSatisfy { !($0 is NSVisualEffectView) }, "Without a captured frame, fallback must be built-in artwork, not a desktop-sampling native material")
    guard let artwork = children.compactMap({ $0 as? NSImageView }).first(where: { $0.image != nil }) else {
        throw CheckFailure.failed("Frosted fallback must contain an app-owned image before any capture completes")
    }
    window.updateFrosting(appearance: FrostedAppearance(), progress: 0)
    try expect(artwork.alphaValue < 0.001, "The built-in background must start clear")
    window.updateFrosting(appearance: FrostedAppearance(), progress: 0.5)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.65))
    try expect(abs(artwork.alphaValue - 0.5) < 0.01, "The built-in image must fade to the requested half strength")
    window.updateFrosting(appearance: FrostedAppearance(), progress: 1)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.65))
    try expect(artwork.alphaValue > 0.99, "The strongest fallback must fully cover the desktop with app-owned artwork")
    try expect(content.hitTest(NSPoint(x: 1, y: 1)) === content, "Clear or opaque fallback must retain full-screen input coverage")
    let preview = FrostedPreviewView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    preview.update(scene: .frostedDark, appearance: FrostedAppearance(), progress: 0, usesSnapshot: false)
    let backdrop = descendants(preview).compactMap { $0 as? NSImageView }.first { $0.identifier?.rawValue == "frosted-example-desktop" }
    try expect(backdrop?.image != nil && backdrop?.alphaValue == 1,
               "A clear fallback preview must reveal its readable app-owned desktop example, not an empty settings background")
    preview.update(scene: .frostedDark, appearance: FrostedAppearance(), progress: 1, usesSnapshot: false)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.65))
    let previewArtwork = descendants(preview).compactMap { $0 as? NSImageView }.first { $0.identifier?.rawValue == "builtin-frosted-image" }
    try expect(previewArtwork?.image === artwork.image && previewArtwork?.alphaValue == artwork.alphaValue,
               "Permission-free preview must show the same app-owned artwork and strength as the actual overlay")
    window.updateFrosting(appearance: FrostedAppearance(), progress: 0.5, mode: .manual)
    preview.update(scene: .frostedDark, appearance: FrostedAppearance(), progress: 0.5, usesSnapshot: false, mode: .manual)
    try expect(artwork.alphaValue == 1 && previewArtwork?.alphaValue == 1,
               "Manual half-strength must immediately hide clear content in both preview and actual overlay")
    let material = content.subviews.compactMap { $0 as? BuiltInFrostedView }.first!
    let depth = material.subviews.first { $0.identifier?.rawValue == "builtin-frosted-tint" }
    var previousDepth: CGFloat = -1
    for amount in [0.0, 0.25, 0.5, 0.75, 0.9, 1] {
        material.update(appearance: FrostedAppearance(), progress: amount, mode: .lidAngle)
        let currentDepth = depth?.layer?.backgroundColor?.alpha ?? -1
        try expect(currentDepth > previousDepth, "The material must continue deepening through the whole closing travel without an early plateau")
        previousDepth = currentDepth
    }
    material.update(appearance: FrostedAppearance(), progress: 0, mode: .lidAngle)
    try expect(artwork.alphaValue == 0 && depth?.layer?.backgroundColor?.alpha == 0,
               "Lid mode must remain completely clear at its start, including the material tint")
}

/// Exercise shared lid targets through real windows, the simulator and synthetic pixels.
func runGentleLidPresentationChecks() throws {
    let suite = "AgentShadeChecks.GentleLid.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShadePreferences(defaults: defaults)
    preferences.triggerAngle = 80
    preferences.automaticEnabled = true
    preferences.enhancedFrostingEnabled = false
    let controller = ShadeController(mediaStore: MediaStore(), preferences: preferences, snapshots: IndependentEmptySnapshotProvider())
    let settings = FrostedSettingsWindowController(preferences: preferences, onChange: {}, onClose: {})
    defer { controller.deactivate(isUserInitiated: false); settings.window?.close() }
    func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
    let children = descendants(settings.window!.contentView!)
    children.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "settingsTab.lid" }!.performClick(nil)
    let simulation = children.compactMap { $0 as? NSSlider }.first { $0.identifier?.rawValue == "previewAngle" }!
    let preview = children.compactMap { $0 as? FrostedPreviewView }.first { !$0.isHiddenOrHasHiddenAncestor }!
    let previewArtwork = descendants(preview).compactMap { $0 as? NSImageView }.first { $0.identifier?.rawValue == "builtin-frosted-image" }!
    controller.updateLidAngle(68, at: 0)
    controller.updateLidAngle(68, at: 0.2)
    for (angle, strength, time) in [(68.0, 0.65, 0.4), (40, 1, 0.6), (35, 1, 0.8), (68, 0.65, 1.0)] {
        controller.updateLidAngle(angle, at: time)
        simulation.doubleValue = angle
        simulation.sendAction(simulation.action, to: simulation.target)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.65))
        let windows = NSApp.windows.compactMap { $0 as? ShadeWindow }.filter(\.isVisible)
        try expect(!windows.isEmpty, "The real lid route must create an overlay")
        for window in windows {
            let artwork = descendants(window.contentView!).compactMap { $0 as? NSImageView }.first { $0.identifier?.rawValue == "builtin-frosted-image" }!
            try expect(abs(artwork.alphaValue - strength) < 0.002,
                       "Real lid coverage must use the gentle curve, including reverse motion and below 40 degrees")
        }
        try expect(abs(previewArtwork.alphaValue - strength) < 0.002,
                   "The simulator must show the same gentle strength as the real lid route")
    }

    let bitmap = CGContext(data: nil, width: 960, height: 96, bitsPerComponent: 8, bytesPerRow: 3840,
                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    bitmap.setFillColor(NSColor.white.cgColor)
    bitmap.fill(CGRect(x: 0, y: 0, width: 960, height: 96))
    bitmap.setFillColor(NSColor.black.cgColor)
    bitmap.fill(CGRect(x: 0, y: 0, width: 480, height: 96))
    let source = bitmap.makeImage()!
    let renderer = FrostedImageRenderer()
    // Compare linear light, not display-dependent, gamma-encoded RGB values.
    let linearColorSpace = NSColorSpace(cgColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)!
    func edgeContrast(_ strength: Double, radius: Double) throws -> CGFloat {
        guard let image = renderer.render(source: source, scene: .frostedDark, appearance: FrostedAppearance(blurRadius: radius, tintOpacity: 0.12), progress: strength) else {
            throw CheckFailure.failed("The synthetic lid blur fixture must render")
        }
        let pixels = NSBitmapImageRep(cgImage: image)
        guard let left = pixels.colorAt(x: 476, y: 48)?.usingColorSpace(linearColorSpace),
              let right = pixels.colorAt(x: 484, y: 48)?.usingColorSpace(linearColorSpace) else {
            throw CheckFailure.failed("The synthetic lid edge must be readable")
        }
        return right.redComponent - left.redComponent
    }
    // Normalize against the same colored material with no blur. Absolute gray
    // brightness cannot measure detail loss after adopting the shared palette.
    let early = try edgeContrast(0.65, radius: 32) / edgeContrast(0.65, radius: 0)
    let full = try edgeContrast(1, radius: 32) / edgeContrast(1, radius: 0)
    try expect(early > full && full < 0.15, "65% blur at 30% travel must retain more detail than full frosting (early \(early), full \(full))")
}

/// Uses empty snapshots to exercise both trigger routes without screen access.
func runIndependentTriggerRoutingChecks() throws {
    let suite = "AgentShadeChecks.TriggerRouting.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShadePreferences(defaults: defaults)
    preferences.scene = .media
    preferences.automaticEnabled = true
    preferences.displayScope = .builtIn
    preferences.automaticDisplayScope = .all
    preferences.tintOpacity = 0.07
    preferences.automaticTintOpacity = 0.31
    preferences.manualFrostStrength = 0.3
    let provider = IndependentEmptySnapshotProvider()
    let controller = ShadeController(mediaStore: MediaStore(), preferences: preferences, snapshots: provider)
    defer { controller.deactivate(isUserInitiated: false) }
    controller.updateLidAngle(35, at: 0)
    controller.updateLidAngle(35, at: 0.2)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.65))
    let automatic = NSApp.windows.compactMap { $0 as? ShadeWindow }.filter(\.isVisible)
    try expect(!automatic.isEmpty && automatic.count == NSScreen.screens.count && automatic.allSatisfy { $0.scene == .frostedDark },
               "Lid shading must apply its all-display scope and frosting even when manual mode selects media")
    func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
    for window in automatic {
        let tint = descendants(window.contentView!).first { $0.identifier?.rawValue == "builtin-frosted-tint" }
        try expect(abs((tint?.layer?.backgroundColor?.alpha ?? -1) - 0.388) < 0.002,
                   "An automatic overlay must render the fixed lid tint, not legacy preferences")
    }
    NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
    try expect(controller.isActive, "Automatic all-display shading must not use the manual built-in-only focus policy")
    controller.deactivate(isUserInitiated: false, restoreFocus: false)
    preferences.scene = .frostedDark
    preferences.displayScope = .all
    controller.activate()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.65))
    let manual = NSApp.windows.compactMap { $0 as? ShadeWindow }.filter(\.isVisible)
    try expect(!manual.isEmpty, "The manual route must create its overlay")
    for window in manual {
        let children = descendants(window.contentView!)
        let artwork = children.compactMap { $0 as? NSImageView }.first { $0.image != nil }
        let tint = children.first { $0.identifier?.rawValue == "builtin-frosted-tint" }
        try expect((artwork?.alphaValue ?? -1) > 0.999,
                   "Manual frosting must occlude readable desktop pixels instead of interpreting strength as image opacity")
        try expect(abs((tint?.layer?.backgroundColor?.alpha ?? -1) - 0.1164) < 0.002,
                   "Manual overlays must apply the fixed tint at manual strength")
    }
}

func runBuiltInFallbackRecoveryChecks() throws {
    try runExpiredFirstFrameRecoveryChecks()
    try expect(FrostedFirstFramePolicy.shouldWait(renderedProgress: 0.1, currentProgress: 0.7, elapsed: 0.02),
               "An immediately stale first frame must keep the responsive fallback in place")
    try expect(!FrostedFirstFramePolicy.shouldWait(renderedProgress: 0.1, currentProgress: 0.7, elapsed: 0.4),
               "First-frame progress mismatch must have a bounded wait during continuous lid movement")
    try expect(!FrostedFirstFramePolicy.shouldWait(renderedProgress: 0.68, currentProgress: 0.7, elapsed: 0.02),
               "A recent first frame must not be held behind a fixed delay")
    let suite = "AgentShadeChecks.FallbackRecovery.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShadePreferences(defaults: defaults)
    preferences.scene = .frostedDark
    preferences.automaticEnabled = true
    let provider = IndependentEmptySnapshotProvider()
    guard let bitmap = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw CheckFailure.failed("Cannot create the recovery bitmap fixture")
    }
    bitmap.setFillColor(CGColor(gray: 0.5, alpha: 1))
    bitmap.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    guard let image = bitmap.makeImage() else { throw CheckFailure.failed("Cannot create the recovery image fixture") }
    provider.image = image
    let controller = ShadeController(mediaStore: MediaStore(), preferences: preferences, snapshots: provider)
    defer { controller.deactivate(isUserInitiated: false) }
    controller.updateLidAngle(40, at: 0)
    controller.updateLidAngle(40, at: 0.2)
    // AppKit may publish a newly ordered borderless window on the next run-loop
    // turn, even though the controller already owns an active session.
    let visibilityDeadline = Date(timeIntervalSinceNow: 0.3)
    while !NSApp.windows.contains(where: { $0 is ShadeWindow && $0.isVisible }), Date() < visibilityDeadline {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }
    guard let window = NSApp.windows.compactMap({ $0 as? ShadeWindow }).first(where: { $0.isVisible }),
          let fallback = window.contentView?.subviews.compactMap({ $0 as? BuiltInFrostedView }).first,
          let enhanced = window.contentView?.subviews.compactMap({ $0 as? FrostedImageView }).first else {
        throw CheckFailure.failed("Recovery fixture requires a visible overlay: active=\(controller.isActive), screens=\(NSScreen.screens.count), appWindows=\(NSApp.windows.count)")
    }
    let deadline = Date(timeIntervalSinceNow: 2)
    while !fallback.isHidden && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
    try expect(fallback.isHidden && enhanced.layer?.contents != nil, "The recovery fixture must first display its synthetic enhanced image")
    provider.image = nil
    controller.refreshPreferences()
    try expect(!fallback.isHidden && enhanced.layer?.contents == nil,
               "An unavailable capture must return to built-in artwork and release the previous captured image")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    try expect(!fallback.isHidden, "A late handoff completion must not hide a restored built-in fallback")
    provider.image = image
    controller.refreshPreferences()
    let recoveryDeadline = Date(timeIntervalSinceNow: 2)
    while !fallback.isHidden && Date() < recoveryDeadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
    try expect(fallback.isHidden && enhanced.layer?.contents != nil, "A later successful capture must be able to replace the fallback again")
}

/// A deliberately occupied render queue models a cold/slow GPU without desktop pixels.
private func runExpiredFirstFrameRecoveryChecks() throws {
    let window = ShadeWindow(frame: NSRect(x: 0, y: 0, width: 400, height: 300), image: nil, scene: .frostedDark, onDismiss: {})
    defer { window.close() }
    guard let fallback = window.contentView?.subviews.compactMap({ $0 as? BuiltInFrostedView }).first,
          let frost = window.contentView?.subviews.compactMap({ $0 as? FrostedImageView }).first,
          let bitmap = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 256,
                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw CheckFailure.failed("Cannot create the delayed first-frame fixture")
    }
    bitmap.setFillColor(CGColor(gray: 0.5, alpha: 1))
    bitmap.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
    guard let image = bitmap.makeImage() else { throw CheckFailure.failed("Cannot create a delayed synthetic image") }
    let queueGate = DispatchSemaphore(value: 0)
    FrostedImageRenderer.renderQueue.async { _ = queueGate.wait(timeout: .now() + 2) }
    window.setSnapshot(image)
    window.updateFrosting(appearance: FrostedAppearance(), progress: 1, mode: .lidAngle)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.32))
    queueGate.signal()
    var queueDrained = false
    FrostedImageRenderer.renderQueue.async { DispatchQueue.main.async { queueDrained = true } }
    let deadline = Date(timeIntervalSinceNow: 2)
    while !queueDrained && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005)) }
    try expect(queueDrained && frost.layer?.contents == nil && !fallback.isHidden,
               "An expired stale first frame must leave the built-in material in place, not start a late handoff")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
    try expect(frost.layer?.contents == nil && !fallback.isHidden,
               "Later timer ticks must not resurrect an abandoned first source")
    window.updateFrosting(appearance: FrostedAppearance(), progress: 0.5, mode: .manual)
    window.setSnapshot(image)
    let recoveryDeadline = Date(timeIntervalSinceNow: 2)
    while !fallback.isHidden && Date() < recoveryDeadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
    try expect(fallback.isHidden && frost.layer?.contents != nil,
               "A newly assigned source must retry successfully after an expired first source")
}

private final class IndependentEmptySnapshotProvider: ScreenSnapshotProviding {
    var image: CGImage?
    func capture(displayIDs: [CGDirectDisplayID], completion: @escaping ([CGDirectDisplayID: CGImage]) -> Void) {
        completion(Dictionary(uniqueKeysWithValues: displayIDs.compactMap { id in image.map { (id, $0) } }))
    }
    func cancel() {}
}
