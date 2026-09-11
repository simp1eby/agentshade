import AppKit
@testable import AgentShadeCore

func runResponsiveLidChecks() throws {
    _ = NSApplication.shared
    for start in [41.0, 55, 67, 80, 85, 95] {
        let angle = start - (start - 40) * 0.3
        try expect(abs(FrostedAppearance.progress(angle: angle, triggerAngle: start) - 0.65) < 0.000001,
                   "30% of the configured lid travel must reach 65% material opacity")
        // Match slopes around the requested milestone: no segmented-curve kink.
        let epsilon = 0.0001
        func strength(_ t: Double) -> Double {
            FrostedAppearance.progress(angle: start - (start - 40) * t, triggerAngle: start)
        }
        let left = (strength(0.3) - strength(0.3 - epsilon)) / epsilon
        let right = (strength(0.3 + epsilon) - strength(0.3)) / epsilon
        try expect(abs(left - right) < 0.005, "The gradient must stay smooth through 30% travel")
        let fallback = BuiltInFrostedView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        fallback.update(appearance: FrostedAppearance(), progress: strength(0.3))
        let image = fallback.subviews.compactMap { $0 as? NSImageView }.first!
        try expect(abs(image.alphaValue - 0.65) < 0.000001, "The rendered permission-free material must use 65% coverage, not just a changed label")
    }
    print("PASS: configurable 30% travel / 65% coverage and smooth curve slope")
}

func runNavigationFocusChecks() throws {
    _ = NSApplication.shared
    let button = SettingsNavigationButton(title: "Lid Gradient", target: nil, action: nil)
    button.setButtonType(.toggle)
    button.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: nil)
    button.state = .on
    try expect(button.focusRingType == .none,
               "Custom-drawn navigation must not overlay a native cell-shaped focus ring on its icon")
    try expect(button.acceptsFirstResponder, "Removing the automatic focus artwork must preserve keyboard navigation")
    print("PASS: one custom navigation highlight without a native icon-shaped focus overlay")
}
