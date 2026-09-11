import AppKit
import Carbon

/// Records only events delivered to this application's own settings window.
public final class ShortcutRecorderView: NSView {
    public var language: AppLanguage = .english { didSet { updateText() } }
    public private(set) var shortcut: Shortcut = .default
    public private(set) var isRecording = false
    public var onChange: ((Shortcut) -> Result<Void, ShortcutChangeError>)?
    public var onRecordingChanged: ((Bool) -> Void)?

    private let recordButton = NSButton(title: "", target: nil, action: nil)
    private let defaultButton = NSButton(title: "", target: nil, action: nil)
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private var currentError: ShortcutChangeError?
    private var eventMonitor: Any?
    private var windowObserver: NSObjectProtocol?

    public init() {
        super.init(frame: .zero)
        recordButton.target = self
        recordButton.action = #selector(recordClicked)
        recordButton.bezelStyle = .rounded
        recordButton.identifier = NSUserInterfaceItemIdentifier("recordShortcut")
        defaultButton.target = self
        defaultButton.action = #selector(defaultClicked)
        defaultButton.bezelStyle = .rounded
        defaultButton.identifier = NSUserInterfaceItemIdentifier("restoreDefaultShortcut")
        defaultButton.setContentHuggingPriority(.required, for: .horizontal)
        feedback.font = .systemFont(ofSize: 11)
        feedback.identifier = NSUserInterfaceItemIdentifier("shortcutFeedback")
        feedback.setContentCompressionResistancePriority(.required, for: .vertical)
        let buttons = NSStackView(views: [recordButton, defaultButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.distribution = .fill
        for view in [buttons, feedback] { addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            buttons.leadingAnchor.constraint(equalTo: leadingAnchor),
            buttons.trailingAnchor.constraint(equalTo: trailingAnchor),
            buttons.topAnchor.constraint(equalTo: topAnchor),
            feedback.leadingAnchor.constraint(equalTo: leadingAnchor),
            feedback.trailingAnchor.constraint(equalTo: trailingAnchor),
            feedback.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 6),
            feedback.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
        updateText()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { removeEventObservers() }

    public override var intrinsicContentSize: NSSize { NSSize(width: 282, height: 96) }
    public override var acceptsFirstResponder: Bool { true }

    public func setShortcut(_ shortcut: Shortcut) {
        cancelRecording()
        self.shortcut = shortcut
        currentError = nil
        updateText()
    }

    public func showError(_ error: ShortcutChangeError) {
        currentError = error
        updateText()
    }

    public func beginRecording() {
        guard !isRecording else { return }
        currentError = nil
        isRecording = true
        onRecordingChanged?(true)
        window?.makeFirstResponder(self)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording, let window = self.window,
                  window.isKeyWindow, event.window === window else { return event }
            self.keyDown(with: event)
            return nil
        }
        if let window {
            windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.cancelRecording()
            }
        }
        updateText()
    }

    public func cancelRecording() {
        currentError = nil
        finishRecording()
        updateText()
    }

    public func restoreDefault() {
        cancelRecording()
        submit(.default)
    }

    public override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        guard !event.isARepeat else { return }
        if event.keyCode == UInt16(kVK_Escape) { cancelRecording(); return }
        let candidate = Shortcut(event: event)
        guard candidate.isValid else { showError(.invalidShortcut); return }
        submit(candidate)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    public override func resignFirstResponder() -> Bool {
        cancelRecording()
        return true
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow { cancelRecording() }
        super.viewWillMove(toWindow: newWindow)
    }

    @objc private func recordClicked() { beginRecording() }
    @objc private func defaultClicked() { restoreDefault() }

    private func submit(_ candidate: Shortcut) {
        switch onChange?(candidate) ?? .success(()) {
        case .success:
            shortcut = candidate
            currentError = nil
        case .failure(let error): currentError = error
        }
        finishRecording()
        updateText()
    }

    private func finishRecording() {
        guard isRecording else { return }
        isRecording = false
        removeEventObservers()
        updateText()
        onRecordingChanged?(false)
    }

    private func removeEventObservers() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor); self.eventMonitor = nil }
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver); self.windowObserver = nil }
    }

    private func updateText() {
        recordButton.title = isRecording ? language.text("按下快捷键…", "Press shortcut…") : shortcut.displayText
        recordButton.setAccessibilityLabel(language.text("录制全局快捷键", "Record global shortcut"))
        defaultButton.title = language.text("恢复默认", "Restore Default")
        if let currentError {
            feedback.stringValue = currentError.message(in: language)
            feedback.textColor = .systemRed
        } else {
            feedback.stringValue = isRecording
                ? language.text("按下包含 ⌘ 或 ⌃ 的组合键；Esc 取消。", "Press a shortcut with ⌘ or ⌃. Esc cancels.")
                : language.text("点击快捷键可重新录制；至少包含 ⌘ 或 ⌃。", "Click the shortcut to record; include ⌘ or ⌃.")
            feedback.textColor = .secondaryLabelColor
        }
    }
}
