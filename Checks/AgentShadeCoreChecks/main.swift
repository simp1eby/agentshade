import Foundation
import CoreGraphics
import AppKit
import Carbon
import AgentShadeCore

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure.failed(message) }
}

func runMediaStoreChecks() throws {
    let fileManager = FileManager.default
    let temporaryDirectory = fileManager.temporaryDirectory
        .appendingPathComponent("AgentShadeChecks-\(UUID().uuidString)", isDirectory: true)
    let mediaDirectory = temporaryDirectory.appendingPathComponent("Application Support", isDirectory: true)
    let suiteName = "AgentShadeChecks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
        try? fileManager.removeItem(at: temporaryDirectory)
        defaults.removePersistentDomain(forName: suiteName)
    }
    try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

    let store = MediaStore(
        fileManager: fileManager,
        defaults: defaults,
        applicationSupportURL: mediaDirectory
    )

    let gif = temporaryDirectory.appendingPathComponent("first.gif")
    try Data("GIF89a".utf8).write(to: gif)
    let firstResult = try store.importMedia(from: gif)
    let copiedData = try Data(contentsOf: firstResult)
    try expect(firstResult.deletingLastPathComponent() == mediaDirectory, "Imported media must live in Application Support")
    try expect(copiedData == Data("GIF89a".utf8), "Imported media bytes must be preserved")
    try expect(store.selectedMediaURL == firstResult, "Imported media must become selected")

    let png = temporaryDirectory.appendingPathComponent("second.png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: png)
    let secondResult = try store.importMedia(from: png)
    try expect(!fileManager.fileExists(atPath: firstResult.path), "Replacing media must delete the prior copy")
    try expect(fileManager.fileExists(atPath: secondResult.path), "Replacing media must keep the new copy")

    store.useBlack()
    try expect(!fileManager.fileExists(atPath: secondResult.path), "Use Black must remove copied media")
    try expect(store.selectedMediaURL == nil, "Use Black must clear the selection")

    let missing = temporaryDirectory.appendingPathComponent("missing.gif")
    defaults.set(missing.path, forKey: MediaStore.preferenceKey)
    try expect(store.selectedMediaURL == nil, "Missing persisted media must fall back to black")
    try expect(defaults.string(forKey: MediaStore.preferenceKey) == nil, "Missing persisted media must clear its preference")

    do {
        _ = try store.importMedia(from: missing)
        throw CheckFailure.failed("Importing missing media must throw")
    } catch is CheckFailure {
        throw CheckFailure.failed("Importing missing media did not throw the filesystem error")
    } catch {
        // Expected filesystem error.
    }
}

final class FakeOverlay: ShadeOverlay {
    private(set) var closeCount = 0
    func close() { closeCount += 1 }
}

func runShadeSessionChecks() throws {
    let first = FakeOverlay()
    let second = FakeOverlay()
    let session = ShadeSession()

    try expect(session.activate(with: [first, second]), "A session with screens must activate")
    try expect(session.isActive, "An activated session must report active")
    try expect(session.overlayCount == 2, "Activation must retain one overlay per screen")

    let duplicate = FakeOverlay()
    try expect(!session.activate(with: [duplicate]), "Repeated activation must not replace active overlays")
    try expect(duplicate.closeCount == 1, "A rejected duplicate overlay must be closed")
    try expect(first.closeCount == 0 && second.closeCount == 0, "Repeated activation must preserve active overlays")

    let replacement = FakeOverlay()
    session.replace(with: [replacement])
    try expect(first.closeCount == 1 && second.closeCount == 1, "Screen changes must close old overlays")
    try expect(session.overlayCount == 1, "Screen changes must retain only current overlays")

    try expect(session.deactivate(), "An active session must deactivate")
    try expect(replacement.closeCount == 1, "Deactivation must close every current overlay")
    try expect(!session.isActive, "A deactivated session must report inactive")
    try expect(!session.deactivate(), "Repeated deactivation must be harmless")
}

func runAspectFillChecks() throws {
    let square = CGRect(x: 0, y: 0, width: 100, height: 100)
    let wide = AspectFillGeometry.frame(imageSize: CGSize(width: 200, height: 100), in: square)
    try expect(wide == CGRect(x: -50, y: 0, width: 200, height: 100), "Wide media must crop equally on the sides")

    let portrait = AspectFillGeometry.frame(imageSize: CGSize(width: 100, height: 200), in: square)
    try expect(portrait == CGRect(x: 0, y: -50, width: 100, height: 200), "Portrait media must crop equally at top and bottom")

    let invalid = AspectFillGeometry.frame(imageSize: .zero, in: square)
    try expect(invalid == square, "Invalid media dimensions must safely use the full bounds")
}

func runShadeWindowChecks() throws {
    _ = NSApplication.shared
    let frame = CGRect(x: 0, y: 0, width: 640, height: 480)
    let window = ShadeWindow(frame: frame, image: nil, onDismiss: {})
    defer { window.close() }

    try expect(window.styleMask == .borderless, "A shade window must be borderless")
    try expect(window.frame == frame, "A shade window must cover its supplied display frame")
    try expect(window.level.rawValue == Int(CGWindowLevelForKey(.screenSaverWindow)), "A shade window must stay above normal application windows")
    try expect(window.canBecomeKey, "A shade window must accept the restoring key")
    try expect(window.backgroundColor == .black && window.isOpaque, "A shade window must have an opaque black fallback")
    try expect(!window.isReleasedWhenClosed, "ARC-managed shade windows must not also release themselves when closed")

    let imageWindow = ShadeWindow(
        frame: frame,
        image: NSImage(size: NSSize(width: 64, height: 64)),
        onDismiss: {}
    )
    defer { imageWindow.close() }
    imageWindow.contentView?.layoutSubtreeIfNeeded()
    let hitView = imageWindow.contentView?.hitTest(NSPoint(x: 320, y: 240))
    try expect(
        hitView === imageWindow.contentView,
        "Mouse input over an image must be swallowed by the shade instead of reaching a child or dismissing it"
    )

    var dismissed = false
    let dismissingWindow = ShadeWindow(frame: frame, image: nil) {
        dismissed = true
    }
    defer { dismissingWindow.close() }
    let keyEvent = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: dismissingWindow.windowNumber,
        context: nil,
        characters: "a",
        charactersIgnoringModifiers: "a",
        isARepeat: false,
        keyCode: 0
    )!

    dismissingWindow.keyDown(with: keyEvent)
    try expect(!dismissed, "A restoring key must not release its receiving window during AppKit event dispatch")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
    try expect(dismissed, "A restoring key must dismiss on the next main run-loop turn")
}

func runGlobalHotKeyChecks() throws {
    NSApp.setActivationPolicy(.accessory)
    NSApp.finishLaunching()
    let hotKey = GlobalHotKey(
        keyCode: UInt32(kVK_ANSI_D),
        modifiers: UInt32(controlKey | optionKey | cmdKey),
        action: {}
    )
    let status = hotKey.register()
    if status == OSStatus(eventInternalErr) {
        print("SKIP: GlobalHotKey registration requires an application bundle")
        return
    }
    try expect(status == noErr, "Control-Option-Command-D must register as a global hotkey (OSStatus \(status))")
    try expect(hotKey.isRegistered, "A successful global hotkey registration must be observable")
    hotKey.unregister()
    try expect(!hotKey.isRegistered, "Unregistering must release the global hotkey")
    print("PASS: GlobalHotKey")
}

func runLoginItemPolicyChecks() throws {
    try expect(
        LoginItemStatus.disabled.toggleIntent == .enable,
        "A disabled login item must be enabled when clicked"
    )
    try expect(
        LoginItemStatus.enabled.toggleIntent == .disable,
        "An enabled login item must be disabled when clicked"
    )
    try expect(
        LoginItemStatus.requiresApproval.toggleIntent == .showApprovalInstructions,
        "A pending login item must show approval instructions instead of unregistering"
    )
}

func runStatusItemIconChecks() throws {
    let icon = StatusItemIcon.make()
    try expect(icon.size == NSSize(width: 18, height: 18), "The status item avatar must fit the menu bar")
    try expect(icon.isTemplate, "The simple robot icon must adapt to light and dark menu bars")

    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 18,
            pixelsHigh: 18,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else {
        throw CheckFailure.failed("The status item icon must render to a bitmap")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: 18, height: 18).fill()
    icon.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    let alphaAt: (Int, Int) -> CGFloat = { x, y in
        bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
    }
    try expect(alphaAt(9, 9) > 0.5, "The AgentShade visor must remain visible at menu-bar size")
    try expect(alphaAt(9, 11) < 0.1, "The outlined mask must preserve interior negative space")
    try expect(alphaAt(9, 1) > 0.5, "The agent signal dot must remain visible at menu-bar size")
}

do {
    if CommandLine.arguments.contains("--permission-presentation") { try runPermissionPresentationChecks(); exit(0) }
    if CommandLine.arguments.contains("--default-blur") { try runDefaultBlurRadiusChecks(); exit(0) }
    if CommandLine.arguments.contains("--permission-occlusion") { try runPermissionOcclusionChecks(); exit(0) }
    if CommandLine.arguments.contains("--responsive-lid") { try runResponsiveLidChecks(); exit(0) }
    if CommandLine.arguments.contains("--navigation-focus") { try runNavigationFocusChecks(); exit(0) }
    if CommandLine.arguments.contains("--preview-visual") { try runPreviewVisualChecks(); exit(0) }
    if CommandLine.arguments.contains("--preview-rendering") { try runPreviewRenderingRecoveryChecks(); exit(0) }
    if CommandLine.arguments.contains("--preview-recovery") { try runPreviewLayoutRecoveryChecks(); exit(0) }
    if CommandLine.arguments.contains("--simple-lid") { try runSimpleLidSettingsChecks(); exit(0) }
    if CommandLine.arguments.contains("--linked-preview") { try runLinkedLidPreviewChecks(); exit(0) }
    if CommandLine.arguments.contains("--frost-palette") { try runSharedFrostedPaletteChecks(); exit(0) }
    if CommandLine.arguments.contains("--effective-blur") { try runEffectiveBlurSettingsChecks(); exit(0) }
    if CommandLine.arguments.contains("--capture-feedback") { try runCaptureFeedbackChecks(); exit(0) }
    if CommandLine.arguments.contains("--stable-manual") { try runStableManualArtworkChecks(); exit(0) }
    if CommandLine.arguments.contains("--dismissal") { try runShortcutDismissalChecks(); exit(0) }
    if CommandLine.arguments.contains("--settings-occlusion") { try runSettingsOcclusionChecks(); exit(0) }
    if CommandLine.arguments.contains("--lid-radius") { try runConfigurableLidRadiusWithoutAccessChecks(); exit(0) }
    if CommandLine.arguments.contains("--slider-progress") { try runSliderProgressChecks(); exit(0) }
    if CommandLine.arguments.contains("--lid-presentation") { _ = NSApplication.shared; try runGentleLidPresentationChecks(); print("PASS: gentle lid preview, real windows and synthetic pixels"); exit(0) }
    if CommandLine.arguments.contains("--lid-curve") { try runGentleLidCurveChecks(); print("PASS: gentle lid curve and 40-degree endpoint"); exit(0) }
    if CommandLine.arguments.contains("--settings-callbacks") { _ = NSApplication.shared; try runSettingsCallbackIntegrationChecks(); exit(0) }
    if CommandLine.arguments.contains("--fallback-recovery") { _ = NSApplication.shared; try runBuiltInFallbackRecoveryChecks(); exit(0) }
    if CommandLine.arguments.contains("--independent-triggers") { _ = NSApplication.shared; try runIndependentTriggerRoutingChecks(); exit(0) }
    if CommandLine.arguments.contains("--independent-migration") { try runIndependentSettingsMigrationChecks(); exit(0) }
    if CommandLine.arguments.contains("--removed-stretch") { try runRemovedStretchChecks(); exit(0) }
    if CommandLine.arguments.contains("--builtin-frost") { _ = NSApplication.shared; try runBuiltInFrostedFallbackChecks(); exit(0) }
    if CommandLine.arguments.contains("--compact-menu") { _ = NSApplication.shared; try runCompactMenuChecks(); exit(0) }
    if CommandLine.arguments.contains("--unified-settings") { try runUnifiedSettingsChecks(); exit(0) }
    if CommandLine.arguments.contains("--shortcuts") { try runShortcutChecks(); try runShortcutRecorderChecks(); print("PASS: shortcut persistence, replacement, recording and cancellation"); exit(0) }
    if CommandLine.arguments.contains("--shortcut-native") { try runShortcutNativeRegistrationChecks(); print("PASS: native shortcut registration and event routing"); exit(0) }
    if CommandLine.arguments.contains("--frost-cold") { try runFrostedColdStartTimingChecks(); exit(0) }
    if CommandLine.arguments.contains("--frost-start") { try runClearStartFrostingChecks(); exit(0) }
    if CommandLine.arguments.contains("--frost-native") { _ = NSApplication.shared; try runNativeStrengthGradientChecks(); exit(0) }
    if CommandLine.arguments.contains("--frost-manual") { _ = NSApplication.shared; try runManualFrostedStrengthChecks(); exit(0) }
    if CommandLine.arguments.contains("--menu-experience") {
        _ = NSApplication.shared
        try runMenuExperienceChecks()
        print("PASS: single language button and sensor-gated menu")
        exit(0)
    }
    if CommandLine.arguments.contains("--experience-settings") {
        try runExperienceSettingsChecks()
        print("PASS: unified frosting migration and hardware capability controls")
        exit(0)
    }
    if CommandLine.arguments.contains("--language-permissions") {
        try runLocalizationChecks()
        try runLanguagePermissionSettingsChecks()
        print("PASS: first-use language, live switching and permission refresh")
        exit(0)
    }
    if CommandLine.arguments.contains("--angle-controls") {
        _ = NSApplication.shared
        try runConfigurableFrostingChecks()
        try runFullAngleGradientChecks()
        try runFrostedSettingsChecks()
        print("PASS: separate start/preview ranges and continuous frosting to 40 degrees")
        exit(0)
    }
    try runMediaStoreChecks()
    try runShadeSessionChecks()
    try runAspectFillChecks()
    try runShadeWindowChecks()
    try runGlobalHotKeyChecks()
    try runLoginItemPolicyChecks()
    try runStatusItemIconChecks()
    try runLidAnglePolicyChecks()
    try runShadePreferencesChecks()
    try runFrostedWindowChecks()
    try runConfigurableFrostingChecks()
    try runGentleLidCurveChecks()
    try runFullAngleGradientChecks()
    try runClearStartFrostingChecks()
    try runNativeStrengthGradientChecks()
    try runSmoothProgressChecks()
    try runFrostedRendererChecks()
    try runFrostedSettingsChecks()
    try runLocalizationChecks()
    try runLanguagePermissionSettingsChecks()
    try runPermissionPresentationChecks()
    try runExperienceSettingsChecks()
    try runMenuExperienceChecks()
    try runShortcutChecks()
    try runShortcutRecorderChecks()
    try runUnifiedSettingsChecks()
    try runCompactMenuChecks()
    try runSettingsCallbackIntegrationChecks()
    try runIndependentSettingsMigrationChecks()
    try runRemovedStretchChecks()
    try runBuiltInFrostedFallbackChecks()
    if let path = CommandLine.arguments.first(where: { $0.hasPrefix("--export-preview=") }) {
        try exportFrostedExample(to: String(path.dropFirst("--export-preview=".count)))
    }
    if CommandLine.arguments.contains("--integration") {
        try runDefaultBlurRadiusChecks()
        try runPermissionOcclusionChecks()
        try runResponsiveLidChecks()
        try runNavigationFocusChecks()
        try runPreviewVisualChecks()
        try runPreviewRenderingRecoveryChecks()
        try runPreviewLayoutRecoveryChecks()
        try runLinkedLidPreviewChecks()
        try runSharedFrostedPaletteChecks()
        try runEffectiveBlurSettingsChecks()
        try runCaptureFeedbackChecks()
        try runShortcutDismissalChecks()
        try runSettingsOcclusionChecks()
        try runConfigurableLidRadiusWithoutAccessChecks()
        try runSliderProgressChecks()
        try runStableManualArtworkChecks()
        try runGentleLidPresentationChecks()
        try runIndependentTriggerRoutingChecks()
        try runBuiltInFallbackRecoveryChecks()
        try runManualFrostedStrengthChecks()
        try runLidControllerIntegrationChecks()
        try runDisplayWakeTransitionChecks()
        try runEnhancementModeReuseChecks()
        try runFrostedHandoffChecks()
        try runFrostedDismissalChecks()
        print("PASS: real-window lid controller integration")
        print("PASS: display wake continuity and frosted handoff")
    }
    if CommandLine.arguments.contains("--sensor") { try runLidMonitorHardwareChecks() }
    print("PASS: MediaStore")
    print("PASS: ShadeSession")
    print("PASS: AspectFillGeometry")
    print("PASS: ShadeWindow")
    print("PASS: LoginItemPolicy")
    print("PASS: StatusItemIcon")
    print("PASS: LidAnglePolicy and sensor reports")
    print("PASS: ShadePreferences")
    print("PASS: FrostedWindow")
    print("PASS: ConfigurableFrosting")
    print("PASS: FrostedRenderer")
    print("PASS: Smooth angle interpolation")
    print("PASS: FrostedSettings controls and layout")
    print("PASS: built-in gradient, unified settings, independent triggers, language sync and custom shortcuts")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
