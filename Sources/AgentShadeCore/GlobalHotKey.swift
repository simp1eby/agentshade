import Carbon
import Foundation

public final class GlobalHotKey {
    private static let signature: OSType = 0x53534844 // "SSHD"
    private static let identifier: UInt32 = 1

    private let keyCode: UInt32
    private let modifiers: UInt32
    private let action: () -> Void
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?

    public init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.action = action
    }

    deinit {
        unregister()
    }

    public var isRegistered: Bool { hotKeyReference != nil }

    @discardableResult
    public func register() -> OSStatus {
        if isRegistered { return noErr }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr,
                      identifier.signature == GlobalHotKey.signature,
                      identifier.id == GlobalHotKey.identifier else {
                    return OSStatus(eventNotHandledErr)
                }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                hotKey.action()
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandlerReference
        )
        guard handlerStatus == noErr else { return handlerStatus }

        let identifier = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        let registrationStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        if registrationStatus != noErr {
            if let eventHandlerReference {
                RemoveEventHandler(eventHandlerReference)
                self.eventHandlerReference = nil
            }
        }
        return registrationStatus
    }

    public func unregister() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
    }
}
