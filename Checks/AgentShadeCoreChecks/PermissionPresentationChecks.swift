import AppKit
@testable import AgentShadeCore

private final class PresentationPermission: ScreenCapturePermissionChecking {
    var isGranted = false
    var requests = 0
    func requestAccess() -> Bool { requests += 1; return false }
}

/// Permission is optional; a functioning artwork fallback must not look broken.
func runPermissionPresentationChecks() throws {
    _ = NSApplication.shared
    let suite = "AgentShadeChecks.PermissionPresentation.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShadePreferences(defaults: defaults, preferredLanguages: ["en"])
    let permission = PresentationPermission()
    var settingsOpens = 0
    let settings = FrostedSettingsWindowController(preferences: preferences, permissions: permission,
        openRecordingSettings: { _ in settingsOpens += 1; return true }, onChange: {}, onClose: {})
    defer { settings.window?.close() }
    try expect(!settings.window!.styleMask.contains(.resizable), "The unified settings window must not become vertically resizable")
    let content = settings.window!.contentView!
    func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
    let views = descendants(content)
    func field(_ id: String) -> NSTextField {
        views.first { $0.identifier?.rawValue == id } as! NSTextField
    }
    let statuses = [field("recordingAccess"), field("lidRecordingAccess")]
    let details = [field("recordingExplanation"), field("lidRecordingExplanation")]

    for language in [AppLanguage.english, .chinese] {
        preferences.language = language
        permission.isGranted = false
        settings.refreshPreferences()
        try expect(statuses.allSatisfy { $0.stringValue.contains(language == .chinese ? "内置毛玻璃" : "Built-in frost") },
                   "Without capture access both pages must say built-in frosting is usable, not imply shading is broken")
        try expect(details.allSatisfy { $0.stringValue.contains(language == .chinese ? "未取得权限" : "not available") },
                   "The visible explanation must distinguish unavailable desktop capture from available artwork")
        permission.isGranted = true
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        try expect(statuses.allSatisfy { $0.stringValue.contains(language == .chinese ? "已授权" : "authorized") },
                   "Returning with access must update both visible permission badges")
        try expect(details.allSatisfy { $0.stringValue.contains(language == .chinese ? "尚未验证" : "not verified") },
                   "Permission alone must not be presented as a successfully captured desktop")
        settings.updateCaptureVerification(.checking)
        try expect(details.allSatisfy { $0.stringValue.contains(language == .chinese ? "正在验证" : "verifying") },
                   "Pending desktop capture must be visible without relying on a tooltip")
        settings.updateCaptureVerification(.failed)
        try expect(details.allSatisfy { $0.stringValue.contains(language == .chinese ? "取图失败" : "capture failed") && $0.stringValue.contains(language == .chinese ? "内置" : "artwork") },
                   "A failed desktop capture must visibly explain the working artwork fallback")
        settings.updateCaptureVerification(.ready)
        try expect(details.allSatisfy { $0.stringValue.contains(language == .chinese ? "取图成功" : "capture verified") },
                   "Only successful frame delivery should show capture verified")
        permission.isGranted = false
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        try expect(statuses.allSatisfy { $0.stringValue.contains(language == .chinese ? "内置毛玻璃" : "Built-in frost") },
                   "Revocation must return to the usable fallback state and discard old capture success")
        try expect(!details.contains { $0.stringValue.contains(language == .chinese ? "取图成功" : "capture verified") },
                   "An old successful capture must not survive permission revocation")
    }
    try expect(permission.requests == 0 && settingsOpens == 0,
               "Opening, refreshing or translating permission feedback must never request access or open System Settings")
    print("PASS: bilingual usable-fallback status, truthful capture feedback, revocation and no unsolicited permission UI")
}
