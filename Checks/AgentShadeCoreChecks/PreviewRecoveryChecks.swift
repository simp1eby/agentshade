import AppKit
@testable import AgentShadeCore

func runPreviewRenderingRecoveryChecks() throws {
    _ = NSApplication.shared
    let preview = FrostedPreviewView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
    let appearance = FrostedAppearance(blurRadius: 40, tintOpacity: 0.12)
    preview.update(scene: .frostedDark, appearance: appearance, progress: 0, usesSnapshot: true)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    let rendered = preview.subviews.compactMap { $0 as? FrostedImageView }.first!
    let fallback = preview.subviews.compactMap { $0 as? BuiltInFrostedView }.first!
    guard let first = rendered.layer?.contents else { throw CheckFailure.failed("The initial clear example must be available") }
    let initial = (first as! CGImage).dataProvider!.data! as Data
    preview.update(scene: .frostedDark, appearance: appearance, progress: 1, usesSnapshot: true)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.7))
    let latest = rendered.layer?.contents.map { ($0 as! CGImage).dataProvider!.data! as Data }
    let artwork = fallback.subviews.compactMap { $0 as? NSImageView }.first!
    let enhancedChanged = !rendered.isHidden && latest != nil && latest != initial
    let fallbackChanged = !fallback.isHidden && artwork.alphaValue > 0.99
    try expect(enhancedChanged || fallbackChanged, "Dragging to maximum must show frosting even if the enhanced renderer cannot produce a frame; never leave the clear example exposed")
    print("PASS: actual preview pixels or visible full-strength fallback (fallback=\(fallbackChanged))")
}

private final class RecoveryAccess: ScreenCapturePermissionChecking {
    var isGranted = false
    func requestAccess() -> Bool { false }
}

func runPreviewLayoutRecoveryChecks() throws {
    _ = NSApplication.shared
    let suite = "AgentShadeChecks.PreviewRecovery.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShadePreferences(defaults: defaults, preferredLanguages: ["en"])
    let access = RecoveryAccess()
    var controller: FrostedSettingsWindowController!
    controller = FrostedSettingsWindowController(preferences: preferences, permissions: access, onChange: {
        controller.refreshPreferences(); controller.updateAngleStatus(.available(105))
    }, onClose: {})
    defer { controller.window?.close(); controller = nil }
    func children(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + children($0) } }
    let content = controller.window!.contentView!
    let views = children(content)
    func get<T: NSView>(_ id: String, _ type: T.Type) throws -> T {
        guard let view = views.first(where: { $0.identifier?.rawValue == id }) as? T else { throw CheckFailure.failed("Missing \(id)") }
        return view
    }
    try get("settingsTab.lid", NSButton.self).performClick(nil)
    controller.updateAngleStatus(.available(105)); content.layoutSubtreeIfNeeded()
    let button = try get("lidConfigureRecording", NSButton.self)
    try expect(button.bounds.width <= 150, "The recording entry must remain compact, not stretch to the whole column")
    let status = try get("lidRecordingAccess", NSTextField.self)
    let explanation = try get("lidRecordingExplanation", NSTextField.self)
    try expect(explanation.stringValue.contains("still desktop snapshot") && explanation.stringValue.contains("without permission"), "The lid page must explain snapshot use and the permission-free fallback")
    let lidPreview = views.compactMap { $0 as? FrostedPreviewView }.last!
    try expect(abs(lidPreview.bounds.width / lidPreview.bounds.height - 4.0 / 3.0) < 0.01, "The lid preview viewport must retain the example desktop's 4:3 proportions")
    try expect(status.stringValue == "Built-in frost ready", "Unavailable capture access must show that the permission-free effect is still usable")
    access.isGranted = true
    NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
    try expect(status.stringValue == "Capture authorized", "The visible status must refresh when process access changes")
    let trigger = try get("triggerAngle", NSSlider.self)
    let simulator = try get("previewAngle", NSSlider.self)
    content.layoutSubtreeIfNeeded()
    let start = trigger.convert(trigger.bounds, to: content)
    let previewStart = simulator.convert(simulator.bounds, to: content)
    for id in ["lidConfigurationColumn", "lidPreviewColumn"] {
        let column = try get(id, NSView.self)
        try expect(!column.hasAmbiguousLayout, "Equal-height columns must have a definite layout before live slider updates")
    }
    for value in [85.0, 67, 41, 95, 85] {
        trigger.doubleValue = value; trigger.sendAction(trigger.action, to: trigger.target)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)); content.layoutSubtreeIfNeeded()
        let frame = trigger.convert(trigger.bounds, to: content)
        let previewFrame = simulator.convert(simulator.bounds, to: content)
        try expect(abs(frame.minY - start.minY) < 1 && abs(previewFrame.minY - previewStart.minY) < 1, "Live start-angle callbacks must not move either slider down the page")
    }
    preferences.language = .chinese; controller.refreshLanguage()
    try expect(status.stringValue == "录屏已授权", "The visible permission state must follow language selection")
    access.isGranted = false
    NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
    try expect(status.stringValue == "内置毛玻璃可用", "Revoked process access must show the usable fallback instead of retaining authorization")
    print("PASS: compact recording entry, visible live permission state and stable slider positions")
}
