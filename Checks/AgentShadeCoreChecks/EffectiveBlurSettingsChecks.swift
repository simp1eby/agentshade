import AppKit
@testable import AgentShadeCore

private final class EffectiveBlurPermission: ScreenCapturePermissionChecking {
    var isGranted = false
    func requestAccess() -> Bool { false }
}

func runCaptureFeedbackChecks() throws {
    _ = NSApplication.shared
    let suite = "AgentShadeChecks.CaptureFeedback.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShadePreferences(defaults: defaults, preferredLanguages: ["en"])
    let permissions = EffectiveBlurPermission()
    permissions.isGranted = true
    let snapshots = VerificationSnapshots()
    let settings = FrostedSettingsWindowController(preferences: preferences, permissions: permissions, onChange: {}, onClose: {})
    defer { settings.window?.close() }
    let children = effectiveBlurChildren(settings.window!.contentView!)
    let entry = children.first { $0.identifier?.rawValue == "lidConfigureRecording" } as! NSButton
    let generalEntry = children.first { $0.identifier?.rawValue == "configureRecording" } as! NSButton
    try expect(entry.toolTip?.contains("not verified") == true, "Permission availability must not claim a captured frame")
    let store = MediaStore(fileManager: .default, defaults: defaults, applicationSupportURL: FileManager.default.temporaryDirectory.appendingPathComponent(suite))
    preferences.automaticEnabled = true
    let shade = ShadeController(mediaStore: store, preferences: preferences, snapshots: snapshots)
    defer { shade.deactivate(restoreFocus: false) }
    shade.onSnapshotStatusChange = { settings.updateCaptureVerification($0) }
    shade.updateLidAngle(100, at: 0); shade.updateLidAngle(60, at: 1); shade.updateLidAngle(60, at: 1.2)
    try expect(entry.toolTip?.contains("verifying") == true, "Actual lid capture must report its pending state")
    snapshots.finish(success: false)
    try expect(entry.toolTip?.contains("failed") == true && entry.toolTip == generalEntry.toolTip, "Capture failure must reach both configuration-entry hints")
    shade.deactivate(restoreFocus: false)
    shade.updateLidAngle(100, at: 2); shade.updateLidAngle(60, at: 3); shade.updateLidAngle(60, at: 3.2)
    snapshots.finish(success: true)
    try expect(entry.toolTip?.contains("capture verified") == true, "Only complete actual frame results may report capture success")
    permissions.isGranted = false
    NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
    try expect(entry.toolTip?.contains("not available") == true, "Revocation must invalidate old verified feedback")
    preferences.language = .chinese; settings.refreshLanguage()
    try expect(entry.toolTip?.contains("未取得权限") == true, "The compact entry must retain localized permission guidance")
    print("PASS: real capture feedback, shared configuration hints and stale-permission invalidation")
}

private func effectiveBlurChildren(_ view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + effectiveBlurChildren($0) }
}

private final class VerificationSnapshots: ScreenSnapshotProviding {
    var requests = 0
    var ids: [CGDirectDisplayID] = []
    var completion: (([CGDirectDisplayID: CGImage]) -> Void)?
    func capture(displayIDs: [CGDirectDisplayID], completion: @escaping ([CGDirectDisplayID: CGImage]) -> Void) {
        requests += 1; ids = displayIDs; self.completion = completion
    }
    func cancel() { completion = nil }
    func finish(success: Bool) {
        let callback = completion; completion = nil
        let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.5, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        callback?(success ? Dictionary(uniqueKeysWithValues: ids.map { ($0, context.makeImage()!) }) : [:])
    }
}

func runEffectiveBlurSettingsChecks() throws {
    _ = NSApplication.shared
    let suite = "AgentShadeChecks.EffectiveBlur.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShadePreferences(defaults: defaults, preferredLanguages: ["en"])
    preferences.scene = .frostedDark
    let permissions = EffectiveBlurPermission()
    let controller = FrostedSettingsWindowController(preferences: preferences, permissions: permissions, onChange: {}, onClose: {})
    defer { controller.window?.close() }
    let content = controller.window!.contentView!
    let views = effectiveBlurChildren(content)
    func control<T: NSView>(_ id: String, _ type: T.Type) throws -> T {
        guard let result = views.first(where: { $0.identifier?.rawValue == id }) as? T else { throw CheckFailure.failed("Missing effective blur control: \(id)") }
        return result
    }
    try expect(!views.contains { $0.identifier?.rawValue == "manualBlur" && !$0.isHiddenOrHasHiddenAncestor },
               "Fixed manual artwork must not expose an ineffective blur radius")
    try control("settingsTab.lid", NSButton.self).performClick(nil)
    let radius = try control("automaticBlur", NSSlider.self)
    try expect(radius.isHiddenOrHasHiddenAncestor, "Permission-free lid artwork must not expose an ineffective radius")
    guard let preview = views.compactMap({ $0 as? FrostedPreviewView }).first(where: { !$0.isHiddenOrHasHiddenAncestor }),
          let imageView = effectiveBlurChildren(preview).compactMap({ $0 as? FrostedImageView }).first else {
        throw CheckFailure.failed("Missing lid snapshot preview")
    }
    var renderedProgress = 0.0
    let originalProgress = imageView.onProgress
    imageView.onProgress = { progress in
        originalProgress?(progress)
        renderedProgress = progress
    }
    func waitFor(_ description: String, until ready: () -> Bool) throws {
        let deadline = Date(timeIntervalSinceNow: 3)
        while !ready(), Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        try expect(ready(), description)
    }
    permissions.isGranted = true
    NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
    try expect(!radius.isHiddenOrHasHiddenAncestor && radius.isEnabled, "Authorized lid snapshots must expose the real blur radius")
    try expect(radius.accessibilityLabel() == "Blur radius", "The retained radius must use one unambiguous name")
    let previewAngle = try control("previewAngle", NSSlider.self)
    previewAngle.doubleValue = 90
    previewAngle.sendAction(previewAngle.action, to: previewAngle.target)
    previewAngle.doubleValue = 40
    previewAngle.sendAction(previewAngle.action, to: previewAngle.target)
    try expect(previewAngle.doubleValue == 40, "Deepest preview must use the actual 40-degree endpoint")
    content.layoutSubtreeIfNeeded()
    func frame(radius value: Double) throws -> CGImage {
        radius.doubleValue = value
        radius.sendAction(radius.action, to: radius.target)
        try waitFor("Deepest preview animation must reach its endpoint") { renderedProgress == 1 }
        // Drain the current render and its possible latest-generation replacement.
        // A preview remains hidden until its first asynchronous frame succeeds.
        for _ in 0..<2 {
            var drained = false
            FrostedImageRenderer.renderQueue.async {
                DispatchQueue.main.async { drained = true }
            }
            try waitFor("Deepest preview render must finish") { drained }
        }
        try expect(!imageView.isHiddenOrHasHiddenAncestor, "The enhanced preview must display rendered pixels, not fallback artwork")
        guard let contents = imageView.layer?.contents else { throw CheckFailure.failed("Deepest example must render real pixels") }
        return contents as! CGImage
    }
    let clear = try frame(radius: 0), blurred = try frame(radius: 60)
    let clearData = clear.dataProvider!.data!, blurredData = blurred.dataProvider!.data!
    let clearBytes = CFDataGetBytePtr(clearData)!
    let blurredBytes = CFDataGetBytePtr(blurredData)!
    var difference = 0
    for i in stride(from: 0, to: min(clear.bytesPerRow * clear.height, blurred.bytesPerRow * blurred.height), by: 16) {
        difference += abs(Int(clearBytes[i]) - Int(blurredBytes[i]))
    }
    try expect(difference > 50000, "Dragging the retained radius must visibly change the synthetic deepest-preview pixels")
    try expect(ShadePreferences(defaults: defaults).automaticBlurRadius == 60, "The effective radius must persist")
    preferences.enhancedFrostingEnabled = false
    controller.refreshPreferences()
    try expect(radius.isHiddenOrHasHiddenAncestor, "Turning off desktop snapshots must hide their radius")
    print("PASS: effective-only radius controls, unified name and visible deepest-preview pixel change")
}
