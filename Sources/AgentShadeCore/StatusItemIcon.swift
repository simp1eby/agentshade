import AppKit

public enum StatusItemIcon {
    public static let size = NSSize(width: 18, height: 18)

    public static func make() -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 7.8, y: 15, width: 2.4, height: 2.4)).fill()

            NSColor.black.setStroke()
            let signalStem = NSBezierPath()
            signalStem.move(to: NSPoint(x: 9, y: 15.2))
            signalStem.line(to: NSPoint(x: 9, y: 14))
            signalStem.lineWidth = 1.4
            signalStem.lineCapStyle = .round
            signalStem.stroke()

            let mask = NSBezierPath(
                roundedRect: NSRect(x: 2.25, y: 3.25, width: 13.5, height: 10.75),
                xRadius: 4.25,
                yRadius: 4.25
            )
            mask.lineWidth = 1.6
            mask.lineJoinStyle = .round
            mask.stroke()

            NSBezierPath(
                roundedRect: NSRect(x: 4, y: 7.75, width: 10, height: 3.5),
                xRadius: 1.75,
                yRadius: 1.75
            ).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "AgentShade"
        return image
    }
}
