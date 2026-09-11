import AppKit

/// A native-looking slider whose entire padded row accepts click-and-drag input.
/// Separate responder events leave the main run loop free to render the preview.
final class PreviewAngleSlider: NSSlider {
    private var trackingPointer = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        trackingPointer = true
        updateValue(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard trackingPointer else { return }
        updateValue(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard trackingPointer else { return }
        updateValue(with: event)
        trackingPointer = false
    }

    private func updateValue(with event: NSEvent) {
        guard isEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)
        let knobWidth = (cell as? NSSliderCell)?.knobRect(flipped: isFlipped).width ?? 16
        let inset = max(8, knobWidth / 2)
        let travel = bounds.width - 2 * inset
        guard travel > 0 else { return }
        var fraction = min(1, max(0, (point.x - bounds.minX - inset) / travel))
        if userInterfaceLayoutDirection == .rightToLeft { fraction = 1 - fraction }
        doubleValue = minValue + Double(fraction) * (maxValue - minValue)
        sendAction(action, to: target)
    }
}
