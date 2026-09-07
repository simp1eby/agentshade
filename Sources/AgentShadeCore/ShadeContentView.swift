import AppKit

final class ShadeContentView: NSView {
    private let imageView = NSImageView(frame: .zero)

    init(frame frameRect: NSRect, image: NSImage?) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true

        imageView.imageFrameStyle = .none
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleAxesIndependently
        imageView.animates = true
        imageView.image = image
        imageView.isHidden = image == nil
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func layout() {
        super.layout()
        guard let image = imageView.image else {
            imageView.frame = bounds
            return
        }
        imageView.frame = AspectFillGeometry.frame(imageSize: image.size, in: bounds)
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func rightMouseDragged(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func otherMouseUp(with event: NSEvent) {}
    override func otherMouseDragged(with event: NSEvent) {}
}
