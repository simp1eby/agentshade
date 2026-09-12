import AppKit
@testable import AgentShadeCore

private struct SimpleLidAccess: ScreenCapturePermissionChecking {
    var isGranted: Bool { false }
    func requestAccess() -> Bool { false }
}

func runSimpleLidSettingsChecks() throws {
    _ = NSApplication.shared
    let suite = "AgentShadeChecks.SimpleLid.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShadePreferences(defaults: defaults, preferredLanguages: ["en"])
    preferences.triggerAngle = 85
    preferences.tintOpacity = 0.4; preferences.automaticTintOpacity = 0.3
    let settings = FrostedSettingsWindowController(preferences: preferences, permissions: SimpleLidAccess(), onChange: {}, onClose: {})
    defer { settings.window?.close() }
    let content = settings.window!.contentView!
    func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
    let views = descendants(content)
    func get<T: NSView>(_ id: String, _ type: T.Type) throws -> T {
        guard let view = views.first(where: { $0.identifier?.rawValue == id }) as? T else { throw CheckFailure.failed("Missing control \(id)") }
        return view
    }
    try get("settingsTab.lid", NSButton.self).performClick(nil)
    let angle = try get("previewAngle", NSSlider.self)
    let trigger = try get("triggerAngle", NSSlider.self)
    try expect(angle.minValue == 35 && angle.maxValue == 95 && angle.doubleValue == 85, "Opening settings must start simulation at the saved threshold within the fixed 35–95 range")
    angle.doubleValue = 55; angle.sendAction(angle.action, to: angle.target)
    try expect(preferences.triggerAngle == 85 && angle.doubleValue == 55, "Simulation must not change the configured start angle")
    trigger.sendAction(trigger.action, to: trigger.target)
    try expect(angle.doubleValue == 85, "Interacting with the start slider must reset simulation even if the rounded start value stays the same")
    trigger.doubleValue = 70; trigger.sendAction(trigger.action, to: trigger.target)
    try expect(angle.doubleValue == 70 && angle.maxValue == 95, "Changing the start angle must reset the simulator's current value, not its upper bound")
    let preview = views.compactMap { $0 as? FrostedPreviewView }.first { !$0.isHiddenOrHasHiddenAncestor }!
    let artwork = descendants(preview).first { $0.identifier?.rawValue == "builtin-frosted-image" }!
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
    try expect(artwork.alphaValue < 0.002, "Editing the start angle must return the preview to clear")
    angle.doubleValue = 40; angle.sendAction(angle.action, to: angle.target)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
    try expect(artwork.alphaValue > 0.998, "Only dragging the simulator downward must reach full frosting at 40 degrees")
    settings.refreshPreferences()
    try expect(angle.doubleValue == 40, "Unrelated refreshes must not erase a user's in-progress simulation")
    try expect(preferences.appearance.tintOpacity == 0.12 && preferences.automaticAppearance.tintOpacity == 0.12, "Both rendering routes must use fixed 12% tint regardless of legacy saved values")
    for language in [AppLanguage.chinese, .english] {
        preferences.language = language; settings.refreshLanguage()
        for tab in ["manual", "lid", "general"] {
            try get("settingsTab.\(tab)", NSButton.self).performClick(nil)
            content.layoutSubtreeIfNeeded()
            let visible = views.filter { !$0.isHiddenOrHasHiddenAncestor }
            try expect(!visible.contains { ["manualTint", "automaticTint", "previewDeepest", "enhancedFrosting", "lidEnhancedFrosting", "permissionRequest", "lidPermissionRequest", "captureVerify", "lidCaptureVerify"].contains($0.identifier?.rawValue ?? "") }, "Simplified settings must not expose removed tint, maximum-preview or permission-panel controls")
            try expect(!visible.contains { ["lidConfigureRecording", "configureRecording"].contains($0.identifier?.rawValue ?? "") }, "Settings must not expose Screen Recording controls")
        }
        try get("settingsTab.lid", NSButton.self).performClick(nil)
        content.layoutSubtreeIfNeeded()
        let left = try get("lidConfigurationColumn", NSView.self), right = try get("lidPreviewColumn", NSView.self)
        let l = left.convert(left.bounds, to: content), r = right.convert(right.bounds, to: content)
        try expect(abs(l.maxY - r.maxY) < 1 && abs(l.height - r.height) < 1, "The lid columns must have aligned tops and equal heights in both languages")
    }
    print("PASS: fixed simulation range, synchronized current angle, clear reset, fixed tint and compact bilingual columns")
}
