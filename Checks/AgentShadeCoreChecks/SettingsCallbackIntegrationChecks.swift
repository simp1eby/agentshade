import AppKit
import Carbon
@testable import AgentShadeCore

func runCompactMenuChecks() throws {
    _ = NSApplication.shared
    let suite = "AgentShadeChecks.CompactMenu.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShadePreferences(defaults: defaults, preferredLanguages: ["en"])
    let shortcutPreferences = ShortcutPreferences(defaults: defaults)
    shortcutPreferences.shortcut = Shortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(controlKey | cmdKey))
    let delegate = AppDelegate(preferences: preferences, shortcutPreferences: shortcutPreferences)
    let menu = delegate.makeMenu()

    try expect(menu.items.count == 7 && menu.items.filter(\.isSeparatorItem).count == 2, "The menu must contain only five actions and two separators")
    try expect(menu.items.filter { !$0.isSeparatorItem }.map(\.title) == ["Shade Now", "Auto Lid Shading", "Settings…", "中文", "Quit AgentShade"], "The menu must expose the approved compact action order")
    try expect(menu.items.allSatisfy { $0.submenu == nil }, "Detailed settings must no longer be nested in the menu")
    try expect(menu.items.first?.keyEquivalent == "j" && menu.items.first?.keyEquivalentModifierMask == [.control, .command], "Shade Now must retain the saved custom shortcut")
    let automatic = menu.items[1]
    try expect(!automatic.isEnabled, "Automatic shading must remain unavailable until a readable sensor is detected")
    delegate.updateLidStatus(.available(100))
    try expect(automatic.isEnabled, "Sensor availability must enable the same automatic menu item")
    delegate.updateLidStatus(.unavailable)
    try expect(!automatic.isEnabled, "A lost sensor must disable automatic shading")

    let language = menu.items[4]
    try expect(NSApp.sendAction(language.action!, to: language.target, from: language), "The compact language toggle must be actionable")
    try expect(preferences.language == .chinese && menu.items[3].title == "设置…" && menu.items[4].title == "English", "The same menu must switch language and offer the reverse action")
}

private final class SettingsLoginFixture: LoginItemManaging {
    var status: LoginItemStatus = .disabled
    private(set) var changes: [Bool] = []
    func setEnabled(_ enabled: Bool) throws { changes.append(enabled); status = enabled ? .enabled : .disabled }
}

private final class SettingsPermissionFixture: ScreenCapturePermissionChecking {
    var isGranted = false
    private(set) var requests = 0
    func requestAccess() -> Bool { requests += 1; return false }
}

func runSettingsCallbackIntegrationChecks() throws {
    _ = NSApplication.shared
    let suite = "AgentShadeChecks.SettingsCallbacks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AgentShadeSettingsCallbacks-\(UUID().uuidString)", isDirectory: true)
    defer {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let mediaURL = folder.appendingPathComponent("synthetic-settings-image.png")
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                                  hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    for x in 0..<2 { for y in 0..<2 { bitmap.setColor(NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1), atX: x, y: y) } }
    try bitmap.representation(using: .png, properties: [:])!.write(to: mediaURL)
    defaults.set(mediaURL.path, forKey: MediaStore.preferenceKey)
    let preferences = ShadePreferences(defaults: defaults, preferredLanguages: ["en"])
    preferences.scene = .media
    let mediaStore = MediaStore(fileManager: .default, defaults: defaults, applicationSupportURL: folder)
    let login = SettingsLoginFixture()
    login.status = .requiresApproval
    let permissions = SettingsPermissionFixture()
    let delegate = AppDelegate(preferences: preferences, permissions: permissions, shortcutPreferences: ShortcutPreferences(defaults: defaults),
                               mediaStore: mediaStore, loginItemController: login)
    let menu = delegate.makeMenu()
    let settingsItem = menu.items.first { $0.identifier?.rawValue == "openSettings" }!
    try expect(NSApp.sendAction(settingsItem.action!, to: settingsItem.target, from: settingsItem), "The sole Settings action must open its live controller")
    guard let controller = NSApp.windows.filter(\.isVisible).compactMap({ $0.windowController as? FrostedSettingsWindowController }).first else {
        throw CheckFailure.failed("Settings did not open")
    }
    defer { controller.window?.close() }
    let window = controller.window!
    func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
    func control<T: NSView>(_ id: String, _ type: T.Type) throws -> T {
        guard let view = descendants(window.contentView!).first(where: { $0.identifier?.rawValue == id }) as? T else {
            throw CheckFailure.failed("Missing settings integration control: \(id)")
        }
        return view
    }

    let mediaName = try control("mediaName", NSTextField.self)
    try expect(mediaName.stringValue.contains(mediaURL.lastPathComponent), "Opening settings must show the media already owned by the app")
    let manualPage = try control("settingsPage.manual", NSView.self)
    guard let mediaView = descendants(manualPage).compactMap({ $0 as? NSImageView }).first(where: { !$0.isHiddenOrHasHiddenAncestor && $0.image != nil }) else {
        throw CheckFailure.failed("The manual image scene must expose the current media preview")
    }
    func previewColor() throws -> NSColor {
        guard let data = mediaView.image?.tiffRepresentation, let pixels = NSBitmapImageRep(data: data),
              let color = pixels.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB) else {
            throw CheckFailure.failed("The synthetic media preview must expose readable pixels")
        }
        return color
    }
    let initialColor = try previewColor()
    try expect(initialColor.blueComponent > 0.9 && initialColor.redComponent < 0.1,
               "The initial media preview must load the blue fixture; got RGBA \(initialColor.redComponent), \(initialColor.greenComponent), \(initialColor.blueComponent), \(initialColor.alphaComponent), image size \(mediaView.image!.size)")
    for x in 0..<2 { for y in 0..<2 { bitmap.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: x, y: y) } }
    try bitmap.representation(using: .png, properties: [:])!.write(to: mediaURL)
    controller.updateMediaURL(mediaURL)
    let replacedColor = try previewColor()
    try expect(replacedColor.redComponent > 0.9 && replacedColor.blueComponent < 0.1,
               "Replacing an image at the same stored URL must refresh the preview pixels")
    let scene = try control("manualScene", NSPopUpButton.self)
    guard let blackItem = scene.itemArray.first(where: { ($0.representedObject as? String) == ShadeScene.black.rawValue }) else {
        throw CheckFailure.failed("The manual scene control must offer black")
    }
    scene.select(blackItem)
    try expect(scene.sendAction(scene.action, to: scene.target), "The manual scene control must notify the app")
    try expect(preferences.scene == .black && mediaStore.selectedMediaURL == mediaURL && FileManager.default.fileExists(atPath: mediaURL.path), "Selecting another manual scene must preserve imported media for switching back")

    try control("settingsTab.general", NSButton.self).performClick(nil)
    let loginControl = try control("launchAtLogin", NSButton.self)
    try expect(loginControl.state == .mixed, "Settings must show login approval that is still pending")
    login.status = .enabled
    NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
    try expect(loginControl.state == .on && loginControl.title == "Launch at Login" && login.changes.isEmpty,
               "Returning from system approval must refresh login status without modifying the login item again")
    loginControl.performClick(nil)
    try expect(login.changes == [false] && login.status == .disabled && loginControl.state == .off, "Login toggling must use the delegate's provider and reflect the resulting status")
    loginControl.performClick(nil)
    try expect(login.changes == [false, true] && loginControl.state == .on, "Enabling login must update the same settings control")

    let language = try control("languageControl", NSButton.self)
    language.performClick(nil)
    try expect(preferences.language == .chinese && menu.items.first?.title == "立即遮罩" && menu.items[4].title == "English", "General language changes must update the existing menu and offer the reverse switch")
    let reverseLanguage = menu.items[4]
    try expect(NSApp.sendAction(reverseLanguage.action!, to: reverseLanguage.target, from: reverseLanguage), "The menu language action must update open settings")
    try expect(preferences.language == .english && controller.window === window && loginControl.title == "Launch at Login", "Menu language changes must refresh the same open settings window")

    try control("settingsTab.lid", NSButton.self).performClick(nil)
    let automatic = try control("automaticEnabled", NSButton.self)
    delegate.updateLidStatus(.unavailable)
    try expect(!automatic.isEnabled, "Settings must receive unavailable sensor status")
    delegate.updateLidStatus(.available(100))
    automatic.performClick(nil)
    try expect(preferences.automaticEnabled && automatic.state == .on && menu.items[1].state == .on, "The lid settings callback must change the real preference and refresh the menu")
    automatic.performClick(nil)
    try expect(!preferences.automaticEnabled && automatic.state == .off && menu.items[1].state == .off, "Disabling automatic shading must refresh both controls")
    try expect(permissions.requests == 0, "General settings callbacks must not request screen recording permission")
}
