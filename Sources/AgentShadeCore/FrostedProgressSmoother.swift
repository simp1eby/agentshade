import Foundation

/// Time-based, bounded interpolation: sensor sampling and display refresh need not match.
struct FrostedProgressSmoother {
    private(set) var value: Double
    private(set) var target: Double
    var needsFrames: Bool { abs(value - target) > 0.001 }

    init(value: Double) {
        let initial = value.isFinite ? min(1, max(0, value)) : 1
        self.value = initial
        target = initial
    }

    mutating func retarget(_ target: Double) {
        guard target.isFinite else { return }
        self.target = min(1, max(0, target))
    }

    mutating func advance(by elapsed: TimeInterval) {
        guard elapsed.isFinite, elapsed > 0 else { return }
        value += (target - value) * (1 - exp(-min(elapsed, 0.05) / 0.075))
        if !needsFrames { value = target }
    }
}
