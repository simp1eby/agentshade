import Foundation
import IOKit.hid

public enum LidAngleStatus: Equatable {
    case stopped, detecting, unavailable
    case available(Double)
}

/// Start/stop and callback access belong to the main thread; HID work stays off the UI thread.
public final class LidAngleMonitor {
    public var onUpdate: ((LidAngleStatus) -> Void)?
    private let queue = DispatchQueue(label: "io.github.simp1eby.agentshade.lid", qos: .utility)
    private let reader = LidSensorReader()
    private var generation = 0

    public init() {}

    deinit {
        let reader = reader
        queue.async { reader.stop() }
    }

    public func start() {
        generation += 1
        let currentGeneration = generation
        onUpdate?(.detecting)
        queue.async { [weak self, reader, queue] in
            reader.start(on: queue) { [weak self] status in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == currentGeneration else { return }
                    self.onUpdate?(status)
                }
            }
        }
    }

    public func stop() {
        generation += 1
        queue.async { [reader] in reader.stop() }
        onUpdate?(.stopped)
    }

    public static func decodeReport(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 3, bytes[0] == 1 else { return nil }
        let value = Int(bytes[1]) | Int(bytes[2]) << 8
        return value <= 180 ? Double(value) : nil
    }
}

private final class LidSensorReader {
    private var device: IOHIDDevice?
    private var timer: DispatchSourceTimer?
    private var onUpdate: ((LidAngleStatus) -> Void)?
    private var nextProbeTime: TimeInterval = 0
    private var failures = 0

    func start(on queue: DispatchQueue, onUpdate: @escaping (LidAngleStatus) -> Void) {
        stop()
        self.onUpdate = onUpdate
        nextProbeTime = 0
        // All events use the same serial queue as start/stop.
        let timer = DispatchSource.makeTimerSource(queue: queue)
        self.timer = timer
        timer.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        closeDevice()
        onUpdate = nil
    }

    private func closeDevice() {
        if let device { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        device = nil
        failures = 0
    }

    private func poll() {
        let now = ProcessInfo.processInfo.systemUptime
        if device == nil {
            guard now >= nextProbeTime else { return }
            nextProbeTime = now + 2
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            // Match only the orientation sensor, never keyboards or pointing devices.
            let matching: [String: Any] = [
                kIOHIDVendorIDKey: 0x05AC,
                kIOHIDDeviceUsagePageKey: 0x0020,
                kIOHIDDeviceUsageKey: 0x008A
            ]
            IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
            if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
                for candidate in devices where IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess {
                    device = candidate
                    break
                }
            }
            guard device != nil else {
                onUpdate?(.unavailable)
                return
            }
        }
        guard let device else { return }
        var report = [UInt8](repeating: 0, count: 8)
        var length = CFIndex(report.count)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
        if result == kIOReturnSuccess, length >= 3, length <= report.count,
           let angle = LidAngleMonitor.decodeReport(Array(report.prefix(length))) {
            failures = 0
            onUpdate?(.available(angle))
        } else {
            failures += 1
            if failures >= 3 {
                closeDevice()
                nextProbeTime = now + 2
                onUpdate?(.unavailable)
            }
        }
    }
}
