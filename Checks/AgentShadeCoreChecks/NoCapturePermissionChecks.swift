import AppKit
@testable import AgentShadeCore

/// AgentShade's user-facing frosting must not expose or request Screen Recording.
func runNoCapturePermissionChecks() throws {
    _ = NSApplication.shared
    let suite = "AgentShadeChecks.NoCapturePermission.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShadePreferences(defaults: defaults, preferredLanguages: ["en"])
    let systemPermission = SystemScreenCapturePermission()
    try expect(!systemPermission.isGranted && !systemPermission.requestAccess(),
               "The default permission provider must never query or request Screen Recording")
    let settings = FrostedSettingsWindowController(preferences: preferences, onChange: {}, onClose: {})
    defer { settings.window?.close() }
    let content = settings.window!.contentView!
    func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
    let views = descendants(content)
    let forbiddenIDs = ["configureRecording", "lidConfigureRecording", "permissionRequest", "lidPermissionRequest",
                        "permissionRefresh", "lidPermissionRefresh", "captureVerify", "lidCaptureVerify",
                        "automaticBlur"]
    try expect(!views.contains { forbiddenIDs.contains($0.identifier?.rawValue ?? "") },
               "Settings must not expose Screen Recording or desktop-capture controls")
    try expect(!views.compactMap { $0 as? NSTextField }.contains { $0.stringValue.localizedCaseInsensitiveContains("recording") },
               "Settings must not present Screen Recording copy")
    let preview = FrostedPreviewView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
    preview.update(scene: .frostedDark, appearance: FrostedAppearance(), progress: 0.5, usesSnapshot: true)
    try expect(preview.subviews.compactMap { $0 as? BuiltInFrostedView }.contains { !$0.isHiddenOrHasHiddenAncestor },
               "Lid preview must always use the built-in permission-free material")
    print("PASS: no Screen Recording controls, copy or capture-dependent preview")
}
