import AppKit
import AgentShadeCore

/// Catch early visual saturation, an incorrect closing endpoint, or a reversed curve.
func runGentleLidCurveChecks() throws {
    let samples: [(angle: Double, strength: Double)] = [
        (95, 0), (80, 0), (76, 0.325), (68, 0.65),
        (60, 0.8125), (50, 0.9285714285714286), (40, 1), (35, 1), (0, 1)
    ]
    for sample in samples {
        try expect(abs(FrostedAppearance.progress(angle: sample.angle, triggerAngle: 80) - sample.strength) < 0.000001,
                   "Lid frosting must reach 65% coverage at 30% travel and maximum at 40 degrees (angle \(sample.angle))")
    }
    for trigger in [41.0, 60, 80, 95] {
        var previous = 0.0
        for step in 1...100 {
            let angle = trigger - (trigger - 40) * Double(step) / 100
            let progress = FrostedAppearance.progress(angle: angle, triggerAngle: trigger)
            try expect(progress > previous && progress <= 1, "Every closing step must deepen the effect without an early plateau")
            if step < 100 { try expect(progress < 1, "Full blur is reserved for the 40-degree endpoint") }
            previous = progress
        }
    }
}

/// Equal scenes at different source resolutions must have equal visible blur.
func runFrostedPerceptualScaleChecks() throws {
    func edgeImage(width: Int) throws -> CGImage {
        guard let context = CGContext(data: nil, width: width, height: 96, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CheckFailure.failed("Cannot create the synthetic blur-scale fixture")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: 96))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: 96))
        guard let image = context.makeImage() else { throw CheckFailure.failed("Cannot finish the synthetic blur-scale fixture") }
        return image
    }
    let renderer = FrostedImageRenderer()
    let settings = FrostedAppearance(blurRadius: 28, tintOpacity: 0)
    guard let small = renderer.render(source: try edgeImage(width: 960), scene: .frostedDark, appearance: settings, progress: 0.5),
          let large = renderer.render(source: try edgeImage(width: 1920), scene: .frostedDark, appearance: settings, progress: 0.5),
          let smallEdge = NSBitmapImageRep(cgImage: small).colorAt(x: 460, y: 48)?.usingColorSpace(.deviceRGB),
          let largeEdge = NSBitmapImageRep(cgImage: large).colorAt(x: 920, y: 48)?.usingColorSpace(.deviceRGB) else {
        throw CheckFailure.failed("Synthetic blur-scale rendering must succeed")
    }
    try expect(abs(smallEdge.redComponent - largeEdge.redComponent) < 0.035,
               "The same scene at 960 and 1920 pixels must retain equal relative blur instead of sharpening the larger source")
    try expect(smallEdge.redComponent > 0.16,
               "Half-strength frosting must substantially soften detail, not remain a lightly blurred screenshot")
}

/// Synthetic pixels only. Timings are evidence, not flaky pass/fail thresholds.
func runFrostedColdStartTimingChecks() throws {
    let context = CGContext(data: nil, width: 640, height: 400, bitsPerComponent: 8, bytesPerRow: 640 * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 640, height: 400))
    context.setFillColor(NSColor.black.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 320, height: 400))
    let source = context.makeImage()!
    for attempt in 1...4 {
        let start = ProcessInfo.processInfo.systemUptime
        let renderer = FrostedImageRenderer()
        let initialized = ProcessInfo.processInfo.systemUptime
        let image = renderer.render(source: source, scene: .frostedDark, appearance: FrostedAppearance(), progress: 0.5)
        let rendered = ProcessInfo.processInfo.systemUptime
        try expect(image != nil, "Synthetic cold-start rendering must succeed")
        print(String(format: "Frosted renderer attempt %d: init %.2f ms, first frame %.2f ms", attempt,
                     (initialized - start) * 1000, (rendered - initialized) * 1000))
    }
}

func runConfigurableFrostingChecks() throws {
    let suite = "AgentShadeChecks.Frosted.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShadePreferences(defaults: defaults)
    preferences.triggerAngle = 60
    try expect(preferences.restoreAngle == 65, "The restore angle must follow the configured trigger")
    let policy = LidAnglePolicy()
    try expect(policy.update(angle: 79, at: 0, triggerAngle: preferences.triggerAngle) == .none, "Changing the threshold must change actual trigger behavior")
    _ = policy.update(angle: 59, at: 1, triggerAngle: preferences.triggerAngle)
    try expect(policy.update(angle: 59, at: 1.2, triggerAngle: preferences.triggerAngle) == .activate, "A configured lower threshold must activate")
    try expect(policy.update(angle: 64, at: 2, triggerAngle: preferences.triggerAngle) == .none, "The configured threshold must keep hysteresis")
    try expect(policy.update(angle: 65, at: 3, triggerAngle: preferences.triggerAngle) == .deactivate, "The configured restore angle must deactivate")
    preferences.triggerAngle = 200
    try expect(preferences.triggerAngle == 95, "An out-of-range saved trigger must not start frosting above 95 degrees")
    preferences.triggerAngle = 20
    try expect(preferences.triggerAngle == 41, "The start angle must remain above the 40-degree full-frost endpoint")
    defaults.set(130, forKey: "triggerAngle")
    try expect(ShadePreferences(defaults: defaults).triggerAngle == 95, "Existing saved settings must use the new upper limit on reload")
    defaults.set(20, forKey: "triggerAngle")
    try expect(ShadePreferences(defaults: defaults).triggerAngle == 41, "Old saved low thresholds must retain a nonzero fade interval on reload")
    preferences.triggerAngle = .nan
    try expect(preferences.triggerAngle == 80, "Corrupt numeric settings must not poison the trigger")
    preferences.blurRadius = 32
    preferences.tintOpacity = 0.2
    preferences.stretchAmount = 0.15
    let reloaded = ShadePreferences(defaults: defaults)
    try expect(reloaded.blurRadius == 32 && reloaded.tintOpacity == 0.2 && reloaded.stretchAmount == 0, "Appearance controls must survive a restart without restoring removed stretch")
    try expect(FrostedAppearance.progress(angle: 40, triggerAngle: 80) > FrostedAppearance.progress(angle: 70, triggerAngle: 80), "Lowering the lid must increase frosting")
    try expect(FrostedAppearance.progress(angle: 0, triggerAngle: 80) == 1, "Progress must be bounded at full frost")
}

func runFullAngleGradientChecks() throws {
    for trigger in [41.0, 60, 80, 95] {
        var previous = FrostedAppearance.progress(angle: trigger, triggerAngle: trigger)
        for angle in stride(from: trigger - 1, through: 40, by: -1) {
            let progress = FrostedAppearance.progress(angle: angle, triggerAngle: trigger)
            try expect(progress > previous, "Frosting must keep deepening at every degree down to 40 (trigger \(trigger), angle \(angle))")
            if angle > 40 { try expect(progress < 1, "Frosting must not reach maximum before 40 degrees") }
            previous = progress
        }
        try expect(FrostedAppearance.progress(angle: 40, triggerAngle: trigger) == 1, "40 degrees must use full configured strength")
        try expect(abs(FrostedAppearance.progress(angle: (trigger + 40) / 2, triggerAngle: trigger) - 0.8125) < 0.0001, "Half of the closing travel must deepen beyond 65% coverage, with no early saturation")
    }
    try expect(FrostedAppearance.progress(angle: 41, triggerAngle: 35) == 0, "Legacy low thresholds must normalize to a clear start above the endpoint")
    try expect(FrostedAppearance.progress(angle: 0, triggerAngle: 35) == 1, "Angles below the minimum must stay bounded")
    try expect(FrostedAppearance.progress(angle: 40, triggerAngle: 35) == 1, "A legacy low threshold must still reach full strength at 40 degrees")
    let high = LidAnglePolicy()
    _ = high.update(angle: 100, at: 0, triggerAngle: 130)
    try expect(high.update(angle: 100, at: 0.2, triggerAngle: 130) == .none, "The real activation policy must enforce the same 95-degree upper limit")
    let low = LidAnglePolicy()
    _ = low.update(angle: 40.5, at: 0, triggerAngle: 20)
    try expect(low.update(angle: 40.5, at: 0.2, triggerAngle: 20) == .activate, "The real policy must start the normalized low-threshold fade before the 40-degree endpoint")
}

func runFrostedRendererChecks() throws {
    let width = 120, height = 80
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(NSColor.black.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
    let source = context.makeImage()!
    let renderer = FrostedImageRenderer()
    let settings = FrostedAppearance(blurRadius: 30, tintOpacity: 0, stretchAmount: 0)
    guard let image = renderer.render(source: source, scene: .frostedDark, appearance: settings, progress: 1) else {
        throw CheckFailure.failed("The frosted renderer must produce an image")
    }
    try expect(image.width == width && image.height == height, "Frosting must preserve display dimensions without transparent blur borders")
    let bitmap = NSBitmapImageRep(cgImage: image)
    let seam = bitmap.colorAt(x: width / 2 - 1, y: height / 2)!.usingColorSpace(.deviceRGB)!
    try expect(seam.redComponent > 0.05 && seam.redComponent < 0.95, "The renderer must actually blur the edge, not merely tint the image")
    let corner = bitmap.colorAt(x: 0, y: 0)!
    try expect(corner.alphaComponent > 0.99, "Blur must not create transparent edges")
    guard let original = renderer.render(source: source, scene: .frostedDark, appearance: settings, progress: 0) else {
        throw CheckFailure.failed("The clear preview must render")
    }
    let clearSeam = NSBitmapImageRep(cgImage: original).colorAt(x: width / 2 - 1, y: height / 2)!.usingColorSpace(.deviceRGB)!
    try expect(clearSeam.redComponent < 0.02, "Zero progress must preserve the original scene")
}

func runFrostedSettingsChecks() throws {
    let suite = "AgentShadeChecks.SettingsUI.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShadePreferences(defaults: defaults)
    preferences.language = .chinese
    var changes = 0, closes = 0
    let controller = FrostedSettingsWindowController(preferences: preferences, onChange: { changes += 1 }, onClose: { closes += 1 })
    guard let content = controller.window?.contentView else { throw CheckFailure.failed("Settings must have a content view") }
    func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
    let lidTab = descendants(content).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "settingsTab.lid" }!
    lidTab.performClick(nil)
    controller.updateAngleStatus(.available(110))
    content.layoutSubtreeIfNeeded()
    let children = descendants(content)
    let sliders = children.compactMap { $0 as? NSSlider }.filter { !$0.isHiddenOrHasHiddenAncestor }
    guard let trigger = sliders.first(where: { $0.accessibilityLabel() == "触发开合角度" }) else { throw CheckFailure.failed("Missing threshold slider") }
    guard let simulation = sliders.first(where: { $0.accessibilityLabel() == "模拟开合角度" }) else { throw CheckFailure.failed("Missing simulated angle slider") }
    for (slider, minimum, maximum) in [(trigger, 41.0, 95.0), (simulation, 35.0, 95.0)] {
        slider.doubleValue = 0
        try expect(slider.doubleValue == minimum, "Start must stay above 40 degrees while simulation may continue below full strength")
        slider.doubleValue = 150
        try expect(slider.doubleValue == maximum, "The start control must respect the device range and simulation must respect the saved threshold")
    }
    trigger.doubleValue = 57
    trigger.sendAction(trigger.action, to: trigger.target)
    try expect(preferences.triggerAngle == 57 && preferences.restoreAngle == 62 && changes == 1, "Moving the actual settings control must persist and notify")
    let preview = children.compactMap { $0 as? FrostedPreviewView }.first { !$0.isHiddenOrHasHiddenAncestor }!
    print("Settings layout: content \(content.bounds), preview \(preview.frame)")
    try expect(preview.bounds.width > 350 && preview.bounds.height >= 250, "Settings must provide a legible preview beside the controls")
    for slider in sliders {
        let rect = slider.convert(slider.bounds, to: content)
        try expect(content.bounds.insetBy(dx: -1, dy: -1).contains(rect), "All settings sliders must fit inside the window")
    }
    try expect(simulation.bounds.height >= 32, "The simulated-angle slider needs a generous vertical click target")
    let hit = content.hitTest(simulation.convert(NSPoint(x: simulation.bounds.midX, y: 3), to: content))
    try expect(hit === simulation, "The padded simulated-angle click area must reach the slider, not a surrounding stack")
    let window = controller.window!
    window.orderFrontRegardless()
    let initialChanges = changes
    func event(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: simulation.convert(NSPoint(x: x, y: y), to: nil), modifierFlags: [],
                          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                          context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    // Queue a mouse-up so the original NSSlider's modal tracking also terminates.
    // The replacement can handle ordinary down/drag/up events without a nested loop.
    simulation.doubleValue = 35
    NSApp.postEvent(event(.leftMouseUp, x: simulation.bounds.midX, y: 3), atStart: true)
    simulation.mouseDown(with: event(.leftMouseDown, x: simulation.bounds.midX, y: 3))
    if let up = NSApp.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true) {
        simulation.mouseUp(with: up)
    }
    try expect(abs(simulation.doubleValue - 65) < 1, "Clicking the padded track must jump halfway through the fixed 35–95 degree range")
    simulation.mouseDown(with: event(.leftMouseDown, x: simulation.bounds.midX, y: simulation.bounds.midY))
    simulation.mouseDragged(with: event(.leftMouseDragged, x: simulation.bounds.maxX + 20, y: simulation.bounds.midY))
    try expect(simulation.doubleValue == 95, "Dragging must update continuously and clamp at the fixed upper end before release")
    simulation.mouseDragged(with: event(.leftMouseDragged, x: -20, y: simulation.bounds.midY))
    try expect(simulation.doubleValue == 35, "Dragging back must reach the lower endpoint")
    simulation.mouseUp(with: event(.leftMouseUp, x: -20, y: simulation.bounds.midY))
    let readouts = children.compactMap { $0 as? NSTextField }.map(\.stringValue)
    try expect(readouts.contains("35°"), "Pointer events must update the actual preview readout")
    try expect(preferences.triggerAngle == 57 && changes == initialChanges, "Simulation must not alter saved preferences or activate the real overlay")
    content.layoutSubtreeIfNeeded()
    for field in children.compactMap({ $0 as? NSTextField }) where !field.stringValue.isEmpty && !field.isHiddenOrHasHiddenAncestor {
        try expect(field.bounds.height >= 10, "Settings text must remain visible: \(field.stringValue), height \(field.bounds.height)")
        try expect(content.bounds.insetBy(dx: -1, dy: -1).contains(field.convert(field.bounds, to: content)), "Settings text must fit inside the window: \(field.stringValue)")
    }
    if let option = CommandLine.arguments.first(where: { $0.hasPrefix("--export-settings=") }) {
        // Only this test-owned window and its synthetic example, not the desktop.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
        let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
        content.cacheDisplay(in: content.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CheckFailure.failed("Settings example export failed") }
        try data.write(to: URL(fileURLWithPath: String(option.dropFirst("--export-settings=".count))))
    }
    controller.window?.close()
    try expect(closes == 1, "Closing settings must notify the automation pause owner")
}

/// Exports only an app-drawn example, never the desktop or any user data.
func exportFrostedExample(to path: String) throws {
    guard let source = FrostedPreviewView.makeExampleImage() else { throw CheckFailure.failed("Example scene must render") }
    let renderer = FrostedImageRenderer()
    let sheet = NSImage(size: NSSize(width: 1500, height: 438))
    sheet.lockFocus()
    NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 1500, height: 438).fill()
    let examples: [(String, ShadeScene, Double)] = [("Original · 示例桌面", .frostedDark, 0), ("Frosted Glass · 毛玻璃 50%", .frostedDark, 0.5), ("Frosted Glass · 毛玻璃 100%", .frostedDark, 1)]
    for (index, example) in examples.enumerated() {
        let rendered = renderer.render(source: source, scene: example.1, appearance: FrostedAppearance(), progress: example.2)!
        let x = 18 + index * 498
        NSImage(cgImage: rendered, size: .zero).draw(in: NSRect(x: x, y: 44, width: 468, height: 351))
        (example.0 as NSString).draw(at: NSPoint(x: x, y: 16), withAttributes: [.font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor.white])
    }
    sheet.unlockFocus()
    guard let image = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw CheckFailure.failed("Example export failed") }
    try data.write(to: URL(fileURLWithPath: path))
}
