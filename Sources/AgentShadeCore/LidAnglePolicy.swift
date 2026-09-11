import Foundation

/// Main-thread policy; independent of HID and windows so threshold behavior is deterministic.
public final class LidAnglePolicy {
    public enum Action { case none, activate, deactivate }
    private var active = false
    private var suppressed = false
    private var pendingSince: TimeInterval?
    private var previousThreshold: Double?

    public init() {}

    public func update(angle: Double, at time: TimeInterval, triggerAngle: Double = 80) -> Action {
        let range = ShadePreferences.angleRange
        let threshold = triggerAngle.isFinite ? min(range.upperBound, max(range.lowerBound, triggerAngle)) : 80
        if previousThreshold != threshold { pendingSince = nil; previousThreshold = threshold }
        guard angle.isFinite, (0...180).contains(angle), time.isFinite else {
            pendingSince = nil
            return .none
        }
        if angle >= threshold + 5 {
            let wasActive = active
            reset()
            return wasActive ? .deactivate : .none
        }
        guard !suppressed, !active else { return .none }
        guard angle < threshold else {
            pendingSince = nil
            return .none
        }
        guard let since = pendingSince, time >= since, time - since <= 0.5 else {
            pendingSince = time
            return .none
        }
        guard time - since >= 0.1 else { return .none }
        active = true
        pendingSince = nil
        return .activate
    }

    public func userDismissed() {
        active = false
        pendingSince = nil
        suppressed = true
    }

    public func reset() {
        suspend()
        suppressed = false
    }

    /// Missing readings or sleep must not undo a user's dismissal of this lid cycle.
    public func suspend() {
        active = false
        pendingSince = nil
    }
}
