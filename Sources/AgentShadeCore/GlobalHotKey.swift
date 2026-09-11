import Carbon
import Foundation

public protocol HotKeyRegistration: AnyObject {
    var isRegistered: Bool { get }
    func register() -> OSStatus
    func unregister()
}

public final class GlobalHotKey: HotKeyRegistration {
    private static let signature: OSType = 0x53534844 // "SSHD"
    private static let identifierLock = NSLock()
    private static var nextIdentifier: UInt32 = 0

    private let identifier: UInt32

    private let keyCode: UInt32
    private let modifiers: UInt32
    private let action: () -> Void
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?

    public init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        Self.identifierLock.lock()
        Self.nextIdentifier &+= 1
        if Self.nextIdentifier == 0 { Self.nextIdentifier = 1 }
        self.identifier = Self.nextIdentifier
        Self.identifierLock.unlock()
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.action = action
    }

    deinit {
        unregister()
    }

    public var isRegistered: Bool { hotKeyReference != nil }
    var eventID: EventHotKeyID { EventHotKeyID(signature: Self.signature, id: identifier) }

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
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                guard status == noErr,
                      identifier.signature == GlobalHotKey.signature,
                      identifier.id == hotKey.identifier,
                      hotKey.isRegistered else {
                    return OSStatus(eventNotHandledErr)
                }
                hotKey.action()
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandlerReference
        )
        guard handlerStatus == noErr else { return handlerStatus }

        let registrationStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            eventID,
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

public final class ShortcutManager {
    public typealias Factory = (_ shortcut: Shortcut, _ action: @escaping () -> Void) -> HotKeyRegistration

    private let preferences: ShortcutPreferences
    private let factory: Factory
    private let action: () -> Void
    private var registration: HotKeyRegistration?
    public private(set) var shortcut: Shortcut

    public init(preferences: ShortcutPreferences = ShortcutPreferences(),
                factory: @escaping Factory = { shortcut, action in
                    GlobalHotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, action: action)
                }, action: @escaping () -> Void) {
        self.preferences = preferences
        self.factory = factory
        self.action = action
        self.shortcut = preferences.shortcut
    }

    deinit { unregister() }

    public var isRegistered: Bool { registration?.isRegistered == true }

    @discardableResult
    public func start() -> Result<Void, ShortcutChangeError> { replace(with: shortcut) }

    @discardableResult
    public func replace(with candidate: Shortcut) -> Result<Void, ShortcutChangeError> {
        guard candidate.isValid else { return .failure(.invalidShortcut) }
        if candidate == shortcut && isRegistered { return .success(()) }
        let replacement = factory(candidate, action)
        let status = replacement.register()
        guard status == noErr else {
            replacement.unregister()
            return .failure(.registrationFailed(status))
        }
        let previous = registration
        registration = replacement
        shortcut = candidate
        preferences.shortcut = candidate
        previous?.unregister()
        return .success(())
    }

    public func unregister() {
        registration?.unregister()
        registration = nil
    }
}
