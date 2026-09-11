import AppKit
@testable import AgentShadeCore

private final class ChangingSettingsPermission: ScreenCapturePermissionChecking {
    var isGranted = true
    var onRequest: (() -> Void)?
    func requestAccess() -> Bool { onRequest?(); return false }
}

/// Model visibility notifications without changing the user's actual TCC grant.
private final class ReportedOcclusionWindow: NSWindow {
    var reportedOcclusion: NSWindow.OcclusionState = [.visible]
    var closeCount = 0
    override var occlusionState: NSWindow.OcclusionState { reportedOcclusion }
    override var isVisible: Bool { closeCount == 0 }
    override var isOnActiveSpace: Bool { true }
    override func close() { closeCount += 1 }
}

func runPermissionOcclusionChecks() throws {
    _ = NSApplication.shared
    for returnOrder in ["activation-first", "key-window-first", "visibility-first", "prompt-then-settings", "prompt-still-external"] {
        try checkPermissionReturn(returnOrder: returnOrder)
    }
    print("PASS: slow permission returns preserve settings in every notification order; ordinary full coverage still closes")
}

private func checkPermissionReturn(returnOrder: String) throws {
    let suite = "AgentShadeChecks.PermissionOcclusion.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let access = ChangingSettingsPermission()
    let preferences = ShadePreferences(defaults: defaults)
    preferences.triggerAngle = 85
    let controller = FrostedSettingsWindowController(preferences: preferences, permissions: access,
        openRecordingSettings: { _ in true }, onChange: {}, onClose: {})
    func children(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + children($0) } }
    let button = children(controller.window!.contentView!).first { $0.identifier?.rawValue == "lidConfigureRecording" } as! NSButton
    let window = ReportedOcclusionWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 730), styleMask: [.titled], backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    controller.window = window
    func report(_ state: NSWindow.OcclusionState) {
        window.reportedOcclusion = state
        controller.windowDidChangeOcclusionState(Notification(name: NSWindow.didChangeOcclusionStateNotification, object: window))
    }
    report([.visible])
    if returnOrder == "prompt-then-settings" || returnOrder == "prompt-still-external" {
        access.isGranted = false
        access.onRequest = {
            NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
            report([])
            if returnOrder == "prompt-then-settings" {
                NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
                report([.visible])
            }
        }
    }
    button.performClick(nil)
    if returnOrder != "prompt-still-external" {
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
    }
    report([])
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
    try expect(window.closeCount == 0, "Opening permission settings must protect AgentShade for the entire external interaction, not just the launch call")
    access.isGranted = false
    switch returnOrder {
    case "activation-first", "prompt-then-settings", "prompt-still-external":
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
    case "key-window-first":
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
    default:
        // Settings can be partially visible while the external permission UI
        // remains active. That alone must not end the protected interaction.
        report([.visible])
    }
    report([])
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
    try expect(window.closeCount == 0, "\(returnOrder): permission return must wait for confirmed visibility, even beyond the normal occlusion debounce")
    report([.visible])
    if returnOrder == "visibility-first" {
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
    try expect(window.closeCount == 0, "Revoking capture access with a transient visibility notification must not close settings")
    try expect(controller.window === window && preferences.triggerAngle == 85, "Returning from System Settings must preserve the same AgentShade settings window and configuration")
    NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
    report([])
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
    report([.visible])
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
    try expect(window.closeCount == 0, "A short visibility transition must not be treated as sustained full coverage")
    report([])
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
    try expect(window.closeCount == 1, "After returning from permission settings, ordinary sustained full coverage must still close the window")
}
