import AppKit
@testable import AgentShadeCore

func runPreviewVisualChecks() throws {
    _ = NSApplication.shared
    for start in [55.0, 67, 80, 85, 95] {
        for (fraction, expected) in [(0.0, 0.0), (0.1, 0.325), (0.3, 0.65), (0.5, 0.8125), (1.0, 1.0)] {
            let angle = start - (start - 40) * fraction
            try expect(abs(FrostedAppearance.progress(angle: angle, triggerAngle: start) - expected) < 0.000001,
                       "Every configured start must use the same normalized lid gradient, not a fixed 80-degree range")
        }
    }
    try expect(FrostedAppearance.progress(angle: 80, triggerAngle: 80) == 0, "The start angle must stay clear")
    try expect(FrostedAppearance.progress(angle: 76, triggerAngle: 80) >= 0.02, "The first four degrees below an 80-degree start must produce visible frosting")
    try expect(abs(FrostedAppearance.progress(angle: 68, triggerAngle: 80) - 0.65) < 0.000001, "30% of lid travel must reach 65% coverage")
    try expect(FrostedAppearance.progress(angle: 40, triggerAngle: 80) == 1, "Full frosting must still occur at 40 degrees")
    let preview = FrostedPreviewView(frame: NSRect(x: 0, y: 0, width: 500, height: 250))
    func children(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + children($0) } }
    for size in [NSSize(width: 500, height: 250), NSSize(width: 260, height: 400)] {
        preview.setFrameSize(size); preview.needsLayout = true; preview.layoutSubtreeIfNeeded()
        for id in ["frosted-example-desktop", "builtin-frosted-image"] {
            let image = children(preview).first { $0.identifier?.rawValue == id } as! NSImageView
            image.superview!.needsLayout = true; image.superview!.layoutSubtreeIfNeeded()
            let intrinsic = image.image!.size
            try expect(image.imageScaling == .scaleProportionallyUpOrDown, "Image drawing must preserve proportions even before a layout pass")
            try expect(abs(image.frame.width / image.frame.height - intrinsic.width / intrinsic.height) < 0.001, "Preview and fallback must preserve image proportions, not squash the scene")
            try expect(image.frame.insetBy(dx: -0.1, dy: -0.1).contains(image.superview!.bounds), "Proportional fill must cover its viewport without gaps")
            try expect(abs(image.frame.midX - image.superview!.bounds.midX) < 0.1 && abs(image.frame.midY - image.superview!.bounds.midY) < 0.1, "The preview crop must stay centered")
        }
    }
    preview.update(scene: .frostedDark, appearance: FrostedAppearance(),
                   progress: FrostedAppearance.progress(angle: 79, triggerAngle: 80), usesSnapshot: false)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
    let artwork = children(preview).first { $0.identifier?.rawValue == "builtin-frosted-image" }!
    try expect(artwork.alphaValue > 0.005, "The real preview must render the first degree of movement, not discard it as a negligible update")
    preview.update(scene: .frostedDark, appearance: FrostedAppearance(), progress: 0.65, usesSnapshot: false)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
    try expect(abs(artwork.alphaValue - 0.65) < 0.002, "The animated preview must settle at 65% coverage without overshoot")
    print("PASS: responsive start, actual 65% coverage preview and centered proportional fill")
}
