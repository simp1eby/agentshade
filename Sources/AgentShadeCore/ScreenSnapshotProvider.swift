import Foundation
import CoreGraphics

/// Compatibility surface retained for integrations compiled against older
/// AgentShade releases. The product no longer captures the desktop.
public protocol ScreenSnapshotProviding: AnyObject {
    func capture(displayIDs: [CGDirectDisplayID], completion: @escaping ([CGDirectDisplayID: CGImage]) -> Void)
    func cancel()
}

/// A deliberately inert provider. Keeping this type source-compatible avoids
/// breaking older callers while ensuring no ScreenCaptureKit/TCC access occurs.
public final class ScreenSnapshotProvider: ScreenSnapshotProviding {
    public init() {}

    public func capture(displayIDs: [CGDirectDisplayID], completion: @escaping ([CGDirectDisplayID: CGImage]) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        completion([:])
    }

    public func cancel() {
        dispatchPrecondition(condition: .onQueue(.main))
    }
}
