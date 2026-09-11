import AppKit
@testable import AgentShadeCore

private final class ExperiencePermissionFixture: ScreenCapturePermissionChecking {
    let isGranted = false
    func requestAccess() -> Bool { false }
}

func runMenuExperienceChecks() throws {
    let suite = "AgentShadeChecks.MenuExperience.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShadePreferences(defaults: defaults, preferredLanguages: ["en"])
    let delegate = AppDelegate(preferences: preferences)
    let menu = delegate.makeMenu()
    guard let item = menu.items.first(where: { $0.identifier?.rawValue == "languageToggle" }), let action = item.action else {
        throw CheckFailure.failed("Language switching must use one top-level button")
    }
    try expect(item.title == "中文" && item.submenu == nil, "The language button must name the destination language")
    try expect(NSApp.sendAction(action, to: item.target, from: item), "The language toggle must be actionable")
    try expect(preferences.language == .chinese && menu.items.first?.title == "立即遮罩", "One click must switch the menu and save the selection")
    let next = menu.items.first(where: { $0.identifier?.rawValue == "languageToggle" })!
    try expect(next.title == "English", "After switching, the button must offer English")
    try expect(menu.items.filter { $0.title == "中文" || $0.title == "English" }.count == 1, "Only one language choice may appear")
    let automatic = menu.items.first { $0.identifier?.rawValue == "automaticShadingToggle" }!
    try expect(!automatic.isEnabled, "Automatic shading must be disabled until a readable sensor has been detected")
    delegate.updateLidStatus(.available(100))
    try expect(automatic.isEnabled, "A readable sensor must enable automatic shading")
    delegate.updateLidStatus(.unavailable)
    try expect(!automatic.isEnabled, "A lost or unsupported sensor must disable automatic shading")
}

func runExperienceSettingsChecks() throws {
    let suite = "AgentShadeChecks.Experience.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("frostedLight", forKey: "shadeScene")
    defaults.set("frostedLight", forKey: "automaticFrostedScene")
    let preferences = ShadePreferences(defaults: defaults, preferredLanguages: ["en"])
    try expect(preferences.scene == .frostedDark && preferences.automaticScene == .frostedDark,
               "Existing light frosting must migrate to the unified dark frosting, not black")
    try expect(!ShadeScene.allCases.contains { $0.rawValue == "frostedLight" }, "Light frosting must no longer be offered")

    _ = NSApplication.shared
    let controller = FrostedSettingsWindowController(preferences: preferences, permissions: ExperiencePermissionFixture(), onChange: {}, onClose: {})
    defer { controller.window?.close() }
    controller.show()
    func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
    let views = descendants(controller.window!.contentView!)
    func control<T: NSView>(_ id: String, _ type: T.Type) throws -> T {
        guard let view = views.first(where: { $0.identifier?.rawValue == id }) as? T else {
            throw CheckFailure.failed("Missing experience settings control: \(id)")
        }
        return view
    }
    let recorder = try control("shortcutRecorder", ShortcutRecorderView.self)
    try expect(!views.contains { $0.identifier?.rawValue == "manualBlur" }, "Manual settings must not offer a blur-radius control that has no effect")
    let manualStrength = try control("manualStrength", NSSlider.self)
    try expect(!recorder.isHiddenOrHasHiddenAncestor && !manualStrength.isHiddenOrHasHiddenAncestor, "The initial manual page must expose the custom shortcut and manual effects")
    try expect(manualStrength.isEnabled, "Without snapshot access, manual strength must remain usable")
    try control("settingsTab.lid", NSButton.self).performClick(nil)
    let trigger = try control("triggerAngle", NSSlider.self)
    let simulation = try control("previewAngle", PreviewAngleSlider.self)
    let animation = try control("angleAnimation", NSButton.self)
    let automatic = try control("automaticEnabled", NSButton.self)
    let scope = try control("automaticScope", NSPopUpButton.self)
    controller.updateAngleStatus(.unavailable)
    try expect(!trigger.isEnabled && !animation.isEnabled && !automatic.isEnabled && !scope.isEnabled, "Missing sensors must disable all hardware-only controls on the lid page")
    try expect(!simulation.isHiddenOrHasHiddenAncestor && simulation.isEnabled, "Visible simulated preview must remain usable without a sensor")
    controller.updateAngleStatus(.available(100))
    try expect(trigger.isEnabled && animation.isEnabled && automatic.isEnabled && scope.isEnabled, "A successfully detected sensor must re-enable hardware-only controls")
    controller.updateAngleStatus(.unavailable)
    try expect(!trigger.isEnabled && !animation.isEnabled && !automatic.isEnabled && !scope.isEnabled, "Lost sensor support must disable controls again")
    try control("settingsTab.manual", NSButton.self).performClick(nil)
    try expect(!manualStrength.isHiddenOrHasHiddenAncestor && manualStrength.isEnabled && !recorder.isHiddenOrHasHiddenAncestor, "Returning to manual settings must retain usable strength and shortcut recording without a sensor")
}
