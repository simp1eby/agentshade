import AppKit

/// Keep the native knob and accessibility, but make the selected range explicit.
/// AppKit's inactive linear track otherwise gives no indication of progress.
final class SettingsSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = NSRect(x: rect.minX, y: rect.midY - 2, width: rect.width, height: 4)
        NSColor.separatorColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
        guard isEnabled, maxValue > minValue else { return }
        let fraction = CGFloat(min(1, max(0, (doubleValue - minValue) / (maxValue - minValue))))
        let width = track.width * fraction
        let rtl = controlView?.userInterfaceLayoutDirection == .rightToLeft
        let selected = NSRect(x: rtl ? track.maxX - width : track.minX, y: track.minY, width: width, height: track.height)
        NSColor.systemBlue.setFill()
        NSBezierPath(roundedRect: selected, xRadius: 2, yRadius: 2).fill()
    }
}
