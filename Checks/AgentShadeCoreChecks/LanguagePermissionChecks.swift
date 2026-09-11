import AppKit
@testable import AgentShadeCore

private final class PermissionFixture: ScreenCapturePermissionChecking {
    var isGranted = false
    var requestResult = false
    var requests = 0
    func requestAccess() -> Bool { requests += 1; return requestResult }
}

private final class LanguageLoginFixture: LoginItemManaging {
    let status = LoginItemStatus.disabled
    func setEnabled(_ enabled: Bool) throws {}
}

func runLanguagePermissionSettingsChecks() throws {
    _ = NSApplication.shared
    try runLiveLidLayoutChecks()
    let suite = "AgentShadeChecks.LanguageUI.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShadePreferences(defaults: defaults, preferredLanguages: ["fr-FR", "zh-Hans"])
    preferences.triggerAngle = 72
    preferences.blurRadius = 42
    preferences.tintOpacity = 0.18
    preferences.manualFrostStrength = 0.63
    preferences.automaticBlurRadius = 31
    preferences.automaticTintOpacity = 0.29
    preferences.displayScope = .all
    preferences.automaticDisplayScope = .builtIn
    preferences.scene = .frostedDark
    let permissions = PermissionFixture()
    let mediaStore = MediaStore(fileManager: .default, defaults: defaults, applicationSupportURL: FileManager.default.temporaryDirectory.appendingPathComponent(suite))
    let delegate = AppDelegate(preferences: preferences, permissions: permissions, shortcutPreferences: ShortcutPreferences(defaults: defaults), mediaStore: mediaStore, loginItemController: LanguageLoginFixture())
    let menu = delegate.makeMenu()
    try expect(menu.items.contains(where: { $0.title == "中文" && $0.submenu == nil && $0.action != nil }), "One top-level language button must offer Chinese when English is active")
    try expect(!menu.items.contains(where: { $0.title == "English" }), "The language button must not be duplicated")
    guard let settingsItem = menu.items.first(where: { $0.title == "Settings…" }), let settingsAction = settingsItem.action else {
        throw CheckFailure.failed("Missing settings menu action")
    }
    try expect(NSApp.sendAction(settingsAction, to: settingsItem.target, from: settingsItem), "The menu must open the real settings controller")
    // Other checks may leave closed, ARC-retained windows in NSApp.windows.
    // Inspect the window opened by this menu action, not an earlier closed one.
    guard let controller = NSApp.windows.filter(\.isVisible).compactMap({ $0.windowController as? FrostedSettingsWindowController }).first else {
        throw CheckFailure.failed("The settings menu did not open its window")
    }
    defer { controller.window?.close() }
    let content = controller.window!.contentView!
    func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
    func control<T: NSView>(_ id: String, _ type: T.Type) throws -> T {
        guard let view = descendants(content).first(where: { $0.identifier?.rawValue == id }) as? T else {
            throw CheckFailure.failed("Missing settings control: \(id)")
        }
        return view
    }
    let generalPage = try control("settingsPage.general", NSView.self)
    let generalTab = try control("settingsTab.general", NSButton.self)
    let lidTab = try control("settingsTab.lid", NSButton.self)
    let languageControl = try control("languageControl", NSButton.self)
    generalTab.performClick(nil)
    try expect(!generalPage.isHidden && !languageControl.isHiddenOrHasHiddenAncestor, "The language switch must be available on the General page")
    let status = try control("configureRecording", NSButton.self)
    let lidStatus = try control("lidConfigureRecording", NSButton.self)
    try expect(status.toolTip?.contains("not available") == true, "The configuration entry must explain unavailable current-process access")
    try expect(permissions.requests == 0, "Opening settings must never request capture access")
    lidTab.performClick(nil)
    let lidBlur = try control("automaticBlur", NSSlider.self)
    try expect(!lidStatus.isHiddenOrHasHiddenAncestor && lidBlur.isHiddenOrHasHiddenAncestor, "Keep one configuration entry and hide unavailable radius")
    permissions.isGranted = true
    NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
    try expect(status.toolTip?.contains("not verified") == true && !lidBlur.isHiddenOrHasHiddenAncestor, "Returning from authorization must reveal radius without claiming a captured frame")
    permissions.isGranted = false
    NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
    try expect(lidBlur.isHiddenOrHasHiddenAncestor && preferences.automaticBlurRadius == 31, "Revocation must hide radius without erasing its saved value")

    lidTab.performClick(nil)
    let simulatedAngle = try control("previewAngle", PreviewAngleSlider.self)
    let triggerAngle = try control("triggerAngle", NSSlider.self)
    for angle in [35.0, 67, 95, 72] {
        triggerAngle.doubleValue = angle
        triggerAngle.sendAction(triggerAngle.action, to: triggerAngle.target)
        controller.updateAngleStatus(.available(105))
        content.layoutSubtreeIfNeeded()
        try assertSettingsRowsDoNotOverlap(in: content)
    }
    simulatedAngle.doubleValue = 57
    simulatedAngle.sendAction(simulatedAngle.action, to: simulatedAngle.target)
    generalTab.performClick(nil)
    for (title, languageValue) in [("中文", AppLanguage.chinese), ("English", .english)] {
        guard let item = menu.items.first(where: { $0.title == title }), let action = item.action else {
            throw CheckFailure.failed("Missing top-level language action: \(title)")
        }
        try expect(NSApp.sendAction(action, to: item.target, from: item), "The native menu item must handle language selection")
        content.layoutSubtreeIfNeeded()
        try expect(preferences.language == languageValue, "The actual language switch must save its choice")
        try expect(controller.window!.title == (languageValue == .chinese ? "AgentShade · 设置" : "AgentShade · Settings"), "Switching languages must update the same open window")
        try expect(!generalPage.isHidden && languageControl.title == (languageValue == .chinese ? "English" : "中文"), "Menu language switching must preserve the current page and synchronize the General button")
        try expect(status.toolTip?.contains(languageValue == .chinese ? "未取得权限" : "not available") == true, "Dynamic permission messages must switch language too")
        try expect(lidStatus.toolTip?.contains(languageValue == .chinese ? "未取得权限" : "not available") == true, "Lid permission guidance must follow the selected language")
        try expect(menu.items.first?.title == (languageValue == .chinese ? "立即遮罩" : "Shade Now"), "Selecting a language must update the same menu immediately")
        let languageItems = menu.items.filter { $0.title == "中文" || $0.title == "English" }
        try expect(languageItems.count == 1 && languageItems.first?.submenu == nil && languageItems.first?.title == (languageValue == .chinese ? "English" : "中文"), "One language button must offer the other language")
        try expect(preferences.triggerAngle == 72 && preferences.blurRadius == 42 && preferences.tintOpacity == 0.18 && preferences.manualFrostStrength == 0.63 && preferences.automaticBlurRadius == 31 && preferences.automaticTintOpacity == 0.29, "Language selection must preserve independent manual and lid effect settings")
        try expect(preferences.displayScope == .all && preferences.automaticDisplayScope == .builtIn && preferences.scene == .frostedDark, "Language selection must preserve independent display scopes and the manual scene")
        try expect(simulatedAngle.doubleValue == 57, "Language selection must preserve the current preview angle")
        for page in ["manual", "lid", "general"] {
            try control("settingsTab.\(page)", NSButton.self).performClick(nil)
            content.layoutSubtreeIfNeeded()
            try assertSettingsRowsDoNotOverlap(in: content)
            let visible = descendants(content).filter { !$0.isHiddenOrHasHiddenAncestor }
            for field in visible.compactMap({ $0 as? NSTextField }) where !field.stringValue.isEmpty {
                try expect(field.bounds.height >= 10 && field.bounds.width >= 5, "Localized labels must not collapse on \(page): \(field.stringValue), \(field.bounds)")
                try expect(content.bounds.insetBy(dx: -1, dy: -1).contains(field.convert(field.bounds, to: content)), "Localized text must fit the visible \(page) page: \(field.stringValue)")
            }
            for slider in visible.compactMap({ $0 as? NSSlider }) {
                try expect(slider.bounds.height >= 16 && slider.bounds.width >= 100, "Every visible \(page) slider must remain usable after changing language: \(slider.accessibilityLabel() ?? ""), \(slider.bounds)")
            }
            for button in visible.compactMap({ $0 as? NSButton }) {
                try expect(button.bounds.height >= 18 && button.bounds.width >= 30, "Visible \(page) buttons must have usable click targets")
                try expect(content.bounds.insetBy(dx: -1, dy: -1).contains(button.convert(button.bounds, to: content)), "Localized controls must fit the visible \(page) page")
            }
        }
        if let option = CommandLine.arguments.first(where: { $0.hasPrefix("--export-language-settings=") }) {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35))
            let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
            content.cacheDisplay(in: content.bounds, to: bitmap)
            let folder = String(option.dropFirst("--export-language-settings=".count))
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("settings-\(languageValue.rawValue).png"))
            }
        }
    }
    languageControl.performClick(nil)
    try expect(preferences.language == .chinese && menu.items.first?.title == "立即遮罩" && status.toolTip?.contains("未取得权限") == true, "The General language button must update menu and permission text together")
    languageControl.performClick(nil)
    try expect(preferences.language == .english && menu.items.first?.title == "Shade Now" && !generalPage.isHidden, "Switching back from General must preserve the page and update the same menu")
    try expect(permissions.requests == 0, "Changing language must not request permission again")
    try expect(ShadePreferences(defaults: defaults, preferredLanguages: ["zh-Hans"]).language == .english, "Manual language choice must survive reopening on a Chinese system")

    let englishMenu = delegate.makeMenu()
    try expect(englishMenu.items.first?.title == "Shade Now", "The menu must use the saved English choice")
    try expect(englishMenu.items.contains(where: { $0.title == "Settings…" }), "The single Settings entry must be translated")
    preferences.language = .chinese
    let chineseMenu = delegate.makeMenu()
    try expect(chineseMenu.items.first?.title == "立即遮罩", "Rebuilding the menu must pick up the new Chinese choice")
    try expect(chineseMenu.items.contains(where: { $0.title == "设置…" }), "Chinese Settings text must remain available")
}

private func runLiveLidLayoutChecks() throws {
    let suite = "AgentShadeChecks.LiveLidLayout.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShadePreferences(defaults: defaults, preferredLanguages: ["zh-Hans"])
    preferences.automaticEnabled = true
    var controller: FrostedSettingsWindowController!
    controller = FrostedSettingsWindowController(preferences: preferences, permissions: PermissionFixture(), onChange: {
        controller.updateAngleStatus(.available(105))
    }, onClose: {})
    defer { controller.window?.close(); controller = nil }
    controller.show()
    let content = controller.window!.contentView!
    func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
    let children = descendants(content)
    let tab = children.first { $0.identifier?.rawValue == "settingsTab.lid" } as! NSButton
    let slider = children.first { $0.identifier?.rawValue == "triggerAngle" } as! NSSlider
    controller.updateAngleStatus(.available(105))
    tab.performClick(nil)
    for angle in [73.0, 67, 35, 95] {
        slider.doubleValue = angle
        slider.sendAction(slider.action, to: slider.target)
        // Exercise the next live layout pass, rather than only forcing layout
        // synchronously, which previously hid the nested-stack regression.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
        content.layoutSubtreeIfNeeded()
        try assertSettingsRowsDoNotOverlap(in: content)
        guard let row = slider.superview as? NSStackView else { throw CheckFailure.failed("Missing lid slider row") }
        let occupied = row.views.filter { !$0.isHiddenOrHasHiddenAncestor }.map { $0.alignmentRect(forFrame: $0.frame) }
        for rect in occupied {
            try expect(row.bounds.insetBy(dx: -1, dy: -1).contains(rect), "A slider label and track must stay inside their allocated row: row \(row.bounds), child \(rect)")
        }
        try expect(row.bounds.height <= 70, "A normal lid-angle row must not grow into a large blank spacer: \(row.bounds)")
    }
}

/// Controls fitting inside the window is insufficient: sibling rows must also
/// have nonzero layout heights and must not overlap after live text changes.
private func assertSettingsRowsDoNotOverlap(in view: NSView) throws {
    guard !view.isHiddenOrHasHiddenAncestor else { return }
    if let stack = view as? NSStackView {
        let visible = stack.views.filter { !$0.isHiddenOrHasHiddenAncestor }
        for (index, child) in visible.enumerated() {
            // Native button frames include decorative shadows outside their
            // alignment rectangles; those may overlap without colliding content.
            let a = child.alignmentRect(forFrame: child.convert(child.bounds, to: stack))
            if stack.orientation == .vertical {
                try expect(a.height > 0, "Visible settings rows must reserve layout height: \(child.identifier?.rawValue ?? String(describing: type(of: child))), \(a)")
            }
            for other in visible.dropFirst(index + 1) {
                let b = other.alignmentRect(forFrame: other.convert(other.bounds, to: stack))
                let intersection = a.intersection(b)
                try expect(intersection.isNull || intersection.width < 0.5 || intersection.height < 0.5,
                           "Settings sibling rows must not overlap: \(child.identifier?.rawValue ?? String(describing: type(of: child))) \(a) with \(other.identifier?.rawValue ?? String(describing: type(of: other))) \(b)")
            }
        }
    }
    for child in view.subviews { try assertSettingsRowsDoNotOverlap(in: child) }
}
