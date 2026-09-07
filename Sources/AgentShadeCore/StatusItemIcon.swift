import AppKit

public enum StatusItemIcon {
    public static let size = NSSize(width: 18, height: 18)

    public static func make() -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()

            NSBezierPath(ovalIn: NSRect(x: 7.5, y: 15.2, width: 3, height: 2.8)).fill()
            NSBezierPath(roundedRect: NSRect(x: 8.25, y: 13.5, width: 1.5, height: 2.5), xRadius: 0.75, yRadius: 0.75).fill()
            NSBezierPath(roundedRect: NSRect(x: 0.75, y: 6, width: 2, height: 6), xRadius: 1, yRadius: 1).fill()
            NSBezierPath(roundedRect: NSRect(x: 15.25, y: 6, width: 2, height: 6), xRadius: 1, yRadius: 1).fill()
            NSBezierPath(roundedRect: NSRect(x: 2, y: 3, width: 14, height: 11.5), xRadius: 3.25, yRadius: 3.25).fill()

            guard let context = NSGraphicsContext.current else { return true }
            context.saveGraphicsState()
            context.compositingOperation = .clear
            NSBezierPath(ovalIn: NSRect(x: 4.5, y: 7.25, width: 3.25, height: 3.5)).fill()
            NSBezierPath(ovalIn: NSRect(x: 10.25, y: 7.25, width: 3.25, height: 3.5)).fill()
            context.restoreGraphicsState()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "AgentShade"
        return image
    }
}
