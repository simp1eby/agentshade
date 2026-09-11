import AppKit
@testable import AgentShadeCore

private struct NoSettingsCapture: ScreenCapturePermissionChecking {
    var isGranted: Bool { false }
    func requestAccess() -> Bool { false }
}

func runUnifiedSettingsChecks() throws {
    _ = NSApplication.shared
    let suite = "AgentShadeChecks.UnifiedSettings.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShadePreferences(defaults: defaults, preferredLanguages: ["en"])
    let controller = FrostedSettingsWindowController(preferences: preferences, permissions: NoSettingsCapture(), onChange: {}, onClose: {})
    defer { controller.window?.close() }
    controller.show()
    let content = controller.window!.contentView!
    func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
    func get<T: NSView>(_ id: String, _: T.Type) throws -> T {
        guard let view = descendants(content).first(where: { $0.identifier?.rawValue == id }) as? T else {
            throw CheckFailure.failed("Unified settings must expose \(id)")
        }
        return view
    }
    let manualTab = try get("settingsTab.manual", NSButton.self)
    let lidTab = try get("settingsTab.lid", NSButton.self)
    let generalTab = try get("settingsTab.general", NSButton.self)
    let manual = try get("settingsPage.manual", NSView.self)
    let lid = try get("settingsPage.lid", NSView.self)
    let general = try get("settingsPage.general", NSView.self)
    try expect(!manual.isHidden && lid.isHidden && general.isHidden, "Only manual settings should be initially visible")
    lidTab.performClick(nil)
    try expect(manual.isHidden && !lid.isHidden && general.isHidden, "Lid tab must switch the same settings window")
    try expect(!descendants(lid).contains { $0.identifier?.rawValue == "manualScene" || $0.identifier?.rawValue == "chooseMedia" }, "Lid shading must never expose custom image selection")
    generalTab.performClick(nil)
    try expect(manual.isHidden && lid.isHidden && !general.isHidden, "General tab must isolate application-wide settings")
    let language = try get("languageControl", NSButton.self)
    language.performClick(nil)
    try expect(preferences.language == .chinese && language.title == "English", "General language button must persist and offer the opposite language")
    try expect(!general.isHidden, "Language switching must retain the current section")
    manualTab.performClick(nil)
    let scene = try get("manualScene", NSPopUpButton.self)
    try expect(scene.selectedItem?.representedObject as? String == "black", "First-use manual settings must select black")
    scene.select(scene.itemArray.first { $0.representedObject as? String == "frostedDark" })
    scene.sendAction(scene.action, to: scene.target)
    try expect(!descendants(manual).contains { $0.identifier?.rawValue == "manualBlur" }, "Manual frosting must not offer a blur-radius control that has no effect")
    let strength = try get("manualStrength", NSSlider.self)
    strength.doubleValue = 0.35
    strength.sendAction(strength.action, to: strength.target)
    lidTab.performClick(nil)
    try expect(preferences.automaticAppearance.tintOpacity == 0.12, "Lid tint must use the fixed material value")
    manualTab.performClick(nil)
    try expect(abs(strength.doubleValue - 0.35) < 0.0001, "Changing tabs must preserve manual strength")
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        controller.window?.appearance = NSAppearance(named: appearance)
        for lang in [AppLanguage.chinese, .english] {
            preferences.language = lang
            controller.refreshLanguage()
            for (index, tab) in [manualTab, lidTab, generalTab].enumerated() {
                tab.performClick(nil)
                content.layoutSubtreeIfNeeded()
                for field in descendants(content).compactMap({ $0 as? NSTextField }) where !field.stringValue.isEmpty && !field.isHiddenOrHasHiddenAncestor {
                    try expect(field.bounds.width >= 5 && field.bounds.height >= 10, "Visible text must not collapse: \(field.stringValue)")
                    try expect(content.bounds.insetBy(dx: -1, dy: -1).contains(field.convert(field.bounds, to: content)), "Visible text must stay within its page: \(field.stringValue)")
                }
                if let option = CommandLine.arguments.first(where: { $0.hasPrefix("--export-unified-settings=") }) {
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
                    let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
                    content.cacheDisplay(in: content.bounds, to: bitmap)
                    let folder = String(option.dropFirst("--export-unified-settings=".count))
                    let path = URL(fileURLWithPath: folder).appendingPathComponent("\(lang.rawValue)-\(appearance.rawValue)-\(index).png")
                    try bitmap.representation(using: .png, properties: [:])!.write(to: path)
                }
            }
        }
    }
    try expect(!descendants(content).compactMap { $0 as? NSSlider }.contains { $0.accessibilityLabel() == "Vertical stretch" || $0.accessibilityLabel() == "纵向拉伸" }, "No setting may offer removed stretch behavior")
    print("PASS: unified sections, local language switching and first-use manual scene")
}
