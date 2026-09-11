import AppKit

/// Keeps native button keyboard/accessibility behavior with a clear selected row.
final class SettingsNavigationButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // NSButton's cell mask uses its own icon geometry, not our custom layout.
        // It otherwise adds an offset blue icon when selectPage gives us focus.
        focusRingType = .none
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        focusRingType = .none
    }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        needsDisplay = true
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        needsDisplay = true
        return accepted
    }
    override func draw(_ dirtyRect: NSRect) {
        let selected = state == .on
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        if selected {
            NSColor.systemBlue.withAlphaComponent(0.18).setFill()
            shape.fill()
            NSColor.systemBlue.withAlphaComponent(window?.firstResponder === self ? 0.85 : 0.55).setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
        let foreground: NSColor = selected ? .labelColor : .secondaryLabelColor
        if let image {
            let symbol = image.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [selected ? .systemBlue : foreground])) ?? image
            symbol.draw(in: NSRect(x: 10, y: (bounds.height - 17) / 2, width: 17, height: 17))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let title = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: selected ? .semibold : .regular),
            .foregroundColor: foreground, .paragraphStyle: paragraph
        ])
        title.draw(in: NSRect(x: 35, y: (bounds.height - title.size().height) / 2,
                             width: max(0, bounds.width - 43), height: title.size().height))
    }
}
