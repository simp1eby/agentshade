import AppKit
import Carbon
@testable import AgentShadeCore

private final class ShortcutRegistrationFixture: HotKeyRegistration {
    let result: OSStatus
    let action: () -> Void
    var beforeRegister: (() -> Void)?
    private(set) var isRegistered = false
    private(set) var unregisterCount = 0

    init(result: OSStatus, action: @escaping () -> Void) { self.result = result; self.action = action }
    func register() -> OSStatus {
        beforeRegister?()
        isRegistered = result == noErr
        return result
    }
    func unregister() { unregisterCount += 1; isRegistered = false }
    func fire() { if isRegistered { action() } }
}

private func requireShortcutSuccess(_ result: Result<Void, ShortcutChangeError>) throws {
    if case .failure(let error) = result { throw CheckFailure.failed("Unexpected shortcut error: \(error)") }
}

private func hasShortcutError(_ result: Result<Void, ShortcutChangeError>, _ expected: ShortcutChangeError) -> Bool {
    if case .failure(let error) = result { return error == expected }
    return false
}

func runShortcutChecks() throws {
    try expect(Shortcut.default.keyCode == UInt32(kVK_ANSI_D) && Shortcut.default.modifiers == UInt32(controlKey | optionKey | cmdKey), "The existing default shortcut must remain Control-Option-Command-D")
    try expect(Shortcut.default.displayText == "⌃⌥⌘D", "The default shortcut must have a readable native modifier display")
    try expect(Shortcut.default.keyEquivalent == "d" && Shortcut.default.modifierFlags == [.control, .option, .command], "Menu equivalents must follow the selected shortcut")
    try expect(!Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: 0).isValid, "Bare letters must not become global shortcuts")
    try expect(!Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(shiftKey | optionKey)).isValid, "Option and Shift alone must not hijack ordinary typing")
    try expect(!Shortcut(keyCode: UInt32(kVK_Escape), modifiers: UInt32(cmdKey)).isValid, "Escape must remain available to cancel recording")
    try expect(!Shortcut(keyCode: UInt32(kVK_Command), modifiers: UInt32(cmdKey)).isValid, "Modifier-only input must not become a shortcut")
    try expect(Shortcut(keyCode: UInt32(kVK_F18), modifiers: UInt32(controlKey)).isValid, "Control with a function key must remain supported")

    let suite = "AgentShadeChecks.Shortcuts.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ShortcutPreferences(defaults: defaults)
    try expect(preferences.shortcut == .default, "First use must preserve the existing shortcut")
    let first = Shortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(controlKey | cmdKey))
    let second = Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(optionKey | cmdKey))
    var fixtures: [ShortcutRegistrationFixture] = []
    var nextStatus: OSStatus = noErr
    var priorRemainedActiveDuringReplacement = false
    var oldChoiceStayedSavedDuringReplacement = false
    var actions = 0
    let manager = ShortcutManager(preferences: preferences, factory: { _, action in
        let fixture = ShortcutRegistrationFixture(result: nextStatus, action: action)
        if let previous = fixtures.last {
            fixture.beforeRegister = {
                priorRemainedActiveDuringReplacement = previous.isRegistered
                oldChoiceStayedSavedDuringReplacement = preferences.shortcut == .default
            }
        }
        fixtures.append(fixture)
        return fixture
    }, action: { actions += 1 })
    defer { manager.unregister() }

    try requireShortcutSuccess(manager.start())
    try expect(manager.isRegistered && fixtures.count == 1, "Starting must register the saved shortcut")
    try requireShortcutSuccess(manager.start())
    try expect(fixtures.count == 1, "Starting an active shortcut twice must be idempotent")
    try requireShortcutSuccess(manager.replace(with: first))
    try expect(priorRemainedActiveDuringReplacement && oldChoiceStayedSavedDuringReplacement, "A candidate must register while the old shortcut and saved value remain intact")
    try expect(!fixtures[0].isRegistered && fixtures[1].isRegistered && manager.shortcut == first, "Only a successful candidate may replace the old registration")
    try expect(ShortcutPreferences(defaults: UserDefaults(suiteName: suite)!).shortcut == first, "A successful custom shortcut must survive a new preferences instance")
    fixtures[0].fire(); fixtures[1].fire()
    try expect(actions == 1, "Replaced registrations must not keep firing")

    nextStatus = OSStatus(eventHotKeyExistsErr)
    let conflict = manager.replace(with: second)
    try expect(hasShortcutError(conflict, .registrationFailed(OSStatus(eventHotKeyExistsErr))), "A registration conflict must be reported to the UI")
    try expect(manager.shortcut == first && preferences.shortcut == first && fixtures[1].isRegistered, "A failed replacement must preserve the old shortcut and its saved value")
    fixtures[1].fire(); fixtures[2].fire()
    try expect(actions == 2, "The previous shortcut must remain usable after a conflict")
    let registrationsBeforeInvalid = fixtures.count
    try expect(hasShortcutError(manager.replace(with: Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: 0)), .invalidShortcut), "Invalid shortcuts must fail before registration")
    try expect(fixtures.count == registrationsBeforeInvalid, "Invalid input must not create registrations")

    manager.unregister()
    try expect(!manager.isRegistered && manager.shortcut == first && preferences.shortcut == first, "Pausing recording must unregister without changing the stored choice")
    nextStatus = noErr
    try requireShortcutSuccess(manager.start())
    try expect(manager.isRegistered && manager.shortcut == first, "Cancelled recording must be able to restart the same shortcut")
    try requireShortcutSuccess(manager.replace(with: .default))
    try expect(manager.shortcut == .default && preferences.shortcut == .default, "Restoring the default must use the same successful replacement path")
}

func runShortcutRecorderChecks() throws {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 160), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let recorder = ShortcutRecorderView()
    window.contentView = recorder
    defer { recorder.cancelRecording(); window.close() }
    var accepted: [Shortcut] = []
    var recordingStates: [Bool] = []
    var nextResult: Result<Void, ShortcutChangeError> = .success(())
    recorder.onChange = { accepted.append($0); return nextResult }
    recorder.onRecordingChanged = { recordingStates.append($0) }
    func event(_ code: Int, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                        windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                        isARepeat: false, keyCode: UInt16(code))!
    }
    func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
    func feedback() -> String {
        descendants(recorder).compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "shortcutFeedback" }?.stringValue ?? ""
    }

    recorder.language = .english
    recorder.beginRecording()
    recorder.beginRecording()
    try expect(recorder.isRecording && recordingStates == [true] && feedback().contains("Esc"), "Recording must show cancellation guidance and emit one start event")
    recorder.keyDown(with: event(kVK_ANSI_A))
    try expect(recorder.isRecording && accepted.isEmpty && feedback().contains("Command"), "Bare letters must explain the modifier rule without changing the shortcut")
    recorder.keyDown(with: event(kVK_Escape))
    try expect(!recorder.isRecording && recorder.shortcut == .default && recordingStates == [true, false], "Escape must cancel and pair the recording callbacks without saving")

    recorder.beginRecording()
    try expect(recorder.performKeyEquivalent(with: event(kVK_ANSI_J, [.control, .command])), "Recording must consume Command combinations before AppKit menu shortcuts")
    let custom = Shortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(controlKey | cmdKey))
    try expect(recorder.shortcut == custom && accepted == [custom] && !recorder.isRecording, "A valid app-local key event must submit the recorded shortcut")
    try expect(recordingStates == [true, false, true, false], "Successful recording must resume global shortcut handling exactly once")

    nextResult = .failure(.registrationFailed(OSStatus(eventHotKeyExistsErr)))
    recorder.beginRecording()
    recorder.keyDown(with: event(kVK_ANSI_K, [.command, .option]))
    try expect(recorder.shortcut == custom && !recorder.isRecording, "Rejected registration must end recording and keep the previous displayed shortcut")
    try expect(feedback().contains("\(eventHotKeyExistsErr)"), "Registration failure feedback must retain the system error code")
    recorder.language = .chinese
    try expect(feedback().contains("快捷键"), "Existing shortcut error feedback must update when the interface language changes")

    nextResult = .success(())
    recorder.restoreDefault()
    try expect(recorder.shortcut == .default && accepted.last == .default, "Restore Default must use the same validated change callback")
    recorder.beginRecording()
    _ = recorder.resignFirstResponder()
    try expect(!recorder.isRecording && recordingStates.suffix(2) == [true, false], "Losing first-responder focus must resume global shortcuts")
    recorder.beginRecording()
    window.contentView = NSView()
    try expect(!recorder.isRecording && recordingStates.suffix(2) == [true, false], "Leaving the window must cancel recording and pair callbacks")
}

/// Opt-in: registers only Control-Option-Shift-Command-F18/F19, never the app's default.
func runShortcutNativeRegistrationChecks() throws {
    _ = NSApplication.shared
    let modifiers = UInt32(controlKey | optionKey | shiftKey | cmdKey)
    var firstActions = 0
    var secondActions = 0
    let first = GlobalHotKey(keyCode: UInt32(kVK_F18), modifiers: modifiers) { firstActions += 1 }
    let second = GlobalHotKey(keyCode: UInt32(kVK_F19), modifiers: modifiers) { secondActions += 1 }
    defer { first.unregister(); second.unregister() }
    for hotKey in [first, second] {
        let result = hotKey.register()
        if result == OSStatus(eventHotKeyExistsErr) || result == OSStatus(eventInternalErr) {
            print("SKIP: isolated native shortcut check unavailable (OSStatus \(result))")
            return
        }
        try expect(result == noErr, "An isolated native shortcut must register (OSStatus \(result))")
    }
    try expect(first.eventID.id != second.eventID.id, "Simultaneous registrations must have distinct event identifiers")
    func dispatch(_ identifier: EventHotKeyID) throws {
        var identifier = identifier
        var event: EventRef?
        try expect(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &event) == noErr, "A synthetic app-local hotkey event must be creatable")
        guard let event else { throw CheckFailure.failed("Missing native event") }
        defer { ReleaseEvent(event) }
        try expect(SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &identifier) == noErr, "A native hotkey event must carry its registration identity")
        try expect(SendEventToEventTarget(event, GetApplicationEventTarget()) == noErr, "The matching native handler must consume its event")
    }
    try dispatch(first.eventID)
    try expect(firstActions == 1 && secondActions == 0, "The first registration event must not trigger the second action")
    try dispatch(second.eventID)
    try expect(firstActions == 1 && secondActions == 1, "The second registration event must fire exactly once")
}
