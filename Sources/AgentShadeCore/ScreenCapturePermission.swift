import CoreGraphics

/// Permission preflight and successful frame delivery are separate facts.
public enum ScreenCaptureVerification { case unchecked, checking, ready, failed }

/// Checks the current process, not the appearance of a System Settings toggle.
/// Only requestAccess may show a consent prompt; callers invoke it on user action.
public protocol ScreenCapturePermissionChecking {
    var isGranted: Bool { get }
    func requestAccess() -> Bool
}

public struct SystemScreenCapturePermission: ScreenCapturePermissionChecking {
    public init() {}
    public var isGranted: Bool { CGPreflightScreenCaptureAccess() }
    public func requestAccess() -> Bool { CGRequestScreenCaptureAccess() }
}
