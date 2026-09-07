import Foundation

public protocol ShadeOverlay: AnyObject {
    func close()
}

public final class ShadeSession {
    private var overlays: [any ShadeOverlay] = []

    public init() {}

    public var isActive: Bool { !overlays.isEmpty }
    public var overlayCount: Int { overlays.count }

    @discardableResult
    public func activate(with newOverlays: [any ShadeOverlay]) -> Bool {
        guard !newOverlays.isEmpty else { return false }
        guard !isActive else {
            newOverlays.forEach { $0.close() }
            return false
        }
        overlays = newOverlays
        return true
    }

    public func replace(with newOverlays: [any ShadeOverlay]) {
        guard isActive else {
            newOverlays.forEach { $0.close() }
            return
        }
        overlays.forEach { $0.close() }
        overlays = newOverlays
    }

    @discardableResult
    public func deactivate() -> Bool {
        guard isActive else { return false }
        let closing = overlays
        overlays.removeAll()
        closing.forEach { $0.close() }
        return true
    }
}
