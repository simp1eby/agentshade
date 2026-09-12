/// Compatibility surface retained for older integrations. AgentShade no
/// longer requests or checks Screen Recording access.
public enum ScreenCaptureVerification { case unchecked, checking, ready, failed }

/// Checks the current process, not the appearance of a System Settings toggle.
/// Only requestAccess may show a consent prompt; callers invoke it on user action.
public protocol ScreenCapturePermissionChecking {
    var isGranted: Bool { get }
    func requestAccess() -> Bool
}

public struct SystemScreenCapturePermission: ScreenCapturePermissionChecking {
    public init() {}
    public var isGranted: Bool { false }
    public func requestAccess() -> Bool { false }
}
