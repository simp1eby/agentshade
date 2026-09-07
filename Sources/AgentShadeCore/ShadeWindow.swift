import AppKit
import CoreGraphics

public final class ShadeWindow: NSWindow, ShadeOverlay {
    private let onDismiss: () -> Void

    public convenience init(screen: NSScreen, image: NSImage?, onDismiss: @escaping () -> Void) {
        self.init(frame: screen.frame, image: image, onDismiss: onDismiss)
    }

    public init(frame: NSRect, image: NSImage?, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        setFrame(frame, display: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .black
        isOpaque = true
        isReleasedWhenClosed = false
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        contentView = ShadeContentView(
            frame: NSRect(origin: .zero, size: frame.size),
            image: image
        )
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    public override func keyDown(with event: NSEvent) {
        DispatchQueue.main.async { [onDismiss] in
            onDismiss()
        }
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        DispatchQueue.main.async { [onDismiss] in
            onDismiss()
        }
        return true
    }
}
