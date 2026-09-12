import AppKit
import CoreGraphics

/// One settings window. Previews never capture the user's desktop.
public final class FrostedSettingsWindowController: NSWindowController, NSWindowDelegate {
    private let preferences: ShadePreferences
    private let permissions: ScreenCapturePermissionChecking
    private let snapshotValidator: ScreenSnapshotProviding
    private let openRecordingSettings: (URL) -> Bool
    private var captureVerification: ScreenCaptureVerification = .unchecked
    private var previousPermission: Bool?
    public var onRestart: (() -> Void)?
    public var onCaptureVerificationChange: ((ScreenCaptureVerification) -> Void)?
    private let onChange: () -> Void
    private let onClose: () -> Void
    public var onChooseMedia: (() -> Void)?
    public var onToggleAutomatic: (() -> Void)?
    public var onToggleLogin: (() -> Void)?
    public var onLanguageChanged: (() -> Void)?
    public var onRefreshSystemState: (() -> Void)?
    private let shortcutRecorder = ShortcutRecorderView()
    private let manualScene = NSPopUpButton()
    private let manualScope = NSPopUpButton()
    private let dismissalControl = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let dismissalHint = NSTextField(wrappingLabelWithString: "")
    private let automaticScope = NSPopUpButton()
    private let chooseMedia = NSButton()
    private let mediaName = NSTextField(wrappingLabelWithString: "")
    private let strengthSlider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let automaticBlurSlider = NSSlider(value: FrostedAppearance.defaultBlurRadius, minValue: 0, maxValue: 60, target: nil, action: nil)
    private var automaticBlurControls: NSView!
    private let triggerSlider = NSSlider(value: 80, minValue: ShadePreferences.angleRange.lowerBound, maxValue: ShadePreferences.angleRange.upperBound, target: nil, action: nil)
    private let angleSlider = PreviewAngleSlider(value: 60, minValue: 35, maxValue: 95, target: nil, action: nil)
    private var previewRangeTitle: NSTextField?
    private var previewStartAngle: Double?
    private let automaticControl = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let animationControl = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let enhancedControl = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let lidEnhancedControl = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let loginControl = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let languageControl = NSButton()
    private let restoreLabel = NSTextField(wrappingLabelWithString: "")
    private let sensorLabel = NSTextField(wrappingLabelWithString: "")
    private let permissionLabel = NSTextField(wrappingLabelWithString: "")
    private let permissionButton = NSButton()
    private let permissionRefreshButton = NSButton()
    private let permissionHelpButton = NSButton()
    private let recordingAccessLabel = NSTextField(labelWithString: "")
    private let lidRecordingAccessLabel = NSTextField(labelWithString: "")
    private var recordingExplanations: [NSTextField] = []
    private let lidPermissionLabel = NSTextField(wrappingLabelWithString: "")
    private let lidPermissionButton = NSButton()
    private let lidPermissionRefreshButton = NSButton()
    private let lidPermissionHelpButton = NSButton()
    private let captureVerifyButton = NSButton()
    private let lidCaptureVerifyButton = NSButton()
    private let manualBlurHelp = NSTextField(wrappingLabelWithString: "")
    private let automaticBlurHelp = NSTextField(wrappingLabelWithString: "")
    private let manualPreview = FrostedPreviewView(frame: .zero)
    private let lidPreview = FrostedPreviewView(frame: .zero)
    private let mediaPreview = NSImageView()
    private let blackPreview = NSView()
    private let previewCaption = NSTextField(wrappingLabelWithString: "")
    private let lidPreviewCaption = NSTextField(wrappingLabelWithString: "")
    private let previewHost = NSView()
    private var manualFrostControls: NSView!
    private var mediaControls: NSView!
    private var localizedFields: [(NSTextField, String, String)] = []
    private var sliderLabels: [(NSSlider, NSTextField, String, String)] = []
    private var pages: [NSView] = []
    private var tabs: [NSButton] = []
    private var selectedPage = 0
    private var lidStatus: LidAngleStatus = .detecting
    private var loginStatus: LoginItemStatus = .disabled
    private var mediaURL: URL?
    private var permissionRequestAccepted = false
    private var activationObserver: NSObjectProtocol?
    private var deactivationObserver: NSObjectProtocol?
    private var displayObserver: NSObjectProtocol?
    private var interactionDepth = 0
    private var occlusionCheckPending = false
    private var hasBeenVisible = false
    private var didNotifyClose = false
    private var pendingOcclusionClose: DispatchWorkItem?
    private var permissionSettingsInteraction = false
    private var permissionSettingsLeftApplication = false
    private var permissionSettingsReturnedToApplication = false
    private var permissionSettingsRecoveryWorkItem: DispatchWorkItem?

    public init(preferences: ShadePreferences, permissions: ScreenCapturePermissionChecking = SystemScreenCapturePermission(),
                snapshotValidator: ScreenSnapshotProviding = ScreenSnapshotProvider(),
                shortcut: Shortcut = .default,
                onShortcutChange: ((Shortcut) -> Result<Void, ShortcutChangeError>)? = nil,
                onShortcutRecordingChanged: ((Bool) -> Void)? = nil,
                openRecordingSettings: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
                onChange: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.preferences = preferences
        self.permissions = permissions
        self.snapshotValidator = snapshotValidator
        self.openRecordingSettings = openRecordingSettings
        self.onChange = onChange
        self.onClose = onClose
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 730),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        super.init(window: window)
        window.delegate = self
        shortcutRecorder.setShortcut(shortcut)
        shortcutRecorder.onChange = onShortcutChange
        shortcutRecorder.onRecordingChanged = onShortcutRecordingChanged
        angleSlider.doubleValue = preferences.triggerAngle
        buildContent()
        refreshPreferences()
        selectPage(0)
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.permissionSettingsDidReturnToApplication()
            self?.onRefreshSystemState?()
            self?.updatePermissionStatus()
            self?.updatePreview()
        }
        deactivationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.permissionSettingsInteraction else { return }
            self.permissionSettingsLeftApplication = true
            self.permissionSettingsReturnedToApplication = false
        }
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.invalidateCaptureVerification()
        }
        window.center()
    }
    deinit {
        pendingOcclusionClose?.cancel()
        snapshotValidator.cancel()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        if let deactivationObserver { NotificationCenter.default.removeObserver(deactivationObserver) }
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    public func show() {
        cancelPendingOcclusionClose()
        permissionSettingsInteraction = false
        permissionSettingsLeftApplication = false
        permissionSettingsReturnedToApplication = false
        permissionSettingsRecoveryWorkItem?.cancel()
        permissionSettingsRecoveryWorkItem = nil
        didNotifyClose = false
        hasBeenVisible = false
        occlusionCheckPending = false
        refreshPreferences(); showWindow(nil)
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
        hasBeenVisible = window?.occlusionState.contains(.visible) == true
    }
    public func refreshPreferences() {
        strengthSlider.doubleValue = preferences.manualFrostStrength
        automaticBlurSlider.doubleValue = preferences.automaticBlurRadius
        triggerSlider.doubleValue = preferences.triggerAngle
        enhancedControl.state = preferences.enhancedFrostingEnabled ? .on : .off
        lidEnhancedControl.state = enhancedControl.state
        animationControl.state = preferences.angleAnimationEnabled ? .on : .off
        dismissalControl.state = preferences.manualDismissRequiresShortcut ? .on : .off
        refreshLanguage()
    }
    func refreshLanguage() {
        window?.title = text("AgentShade · 设置", "AgentShade · Settings")
        for (field, zh, en) in localizedFields { field.stringValue = text(zh, en) }
        let titles = [("快捷键遮罩设置", "Shortcut Shade"), ("合盖渐变设置", "Lid Gradient"), ("通用设置", "General")]
        for (index, button) in tabs.enumerated() { button.title = text(titles[index].0, titles[index].1) }
        shortcutRecorder.language = preferences.language
        languageControl.title = preferences.language == .chinese ? "English" : "中文"
        automaticControl.title = text("启用合盖自动遮罩", "Enable automatic lid shading")
        animationControl.title = text("随开合角度渐变", "Animate with lid angle")
        dismissalControl.title = text("仅用快捷键关闭遮罩", "Dismiss only with the shortcut")
        enhancedControl.title = text("合盖时使用桌面快照增强模糊", "Enhance lid blur with a desktop snapshot")
        lidEnhancedControl.title = text("使用桌面快照（需录屏权限）", "Use desktop snapshots (permission required)")
        chooseMedia.title = text("选择图片或 GIF…", "Choose Image or GIF…")
        permissionRefreshButton.title = text("重新检测", "Check Again")
        permissionHelpButton.title = text("录屏权限…", "Recording…")
        lidPermissionRefreshButton.title = permissionRefreshButton.title
        lidPermissionHelpButton.title = permissionHelpButton.title
        for button in [captureVerifyButton, lidCaptureVerifyButton] { button.title = text("验证取图", "Verify Capture") }
        populate(manualScene, values: ShadeScene.allCases.map { ($0.rawValue, $0.title(in: preferences.language)) }, selected: preferences.scene.rawValue)
        for (popup, selected) in [(manualScope, preferences.displayScope), (automaticScope, preferences.automaticDisplayScope)] {
            populate(popup, values: [("all", text("全部屏幕（含外接屏）", "All displays (including external)")), ("builtIn", text("仅内置屏幕", "Built-in display only"))], selected: selected.rawValue)
            let builtin = NSScreen.screens.contains { screen in
                guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
                return CGDisplayIsBuiltin(id.uint32Value) != 0
            }
            popup.item(at: 1)?.isEnabled = builtin
        }
        for (slider, _, zh, en) in sliderLabels { slider.setAccessibilityLabel(text(zh, en)) }
        updateLoginStatus(loginStatus); updateAngleStatus(lidStatus); updatePermissionStatus()
        updateReadouts(); updateMediaName(); updatePreview()
    }
    func cancelShortcutRecording() { shortcutRecorder.cancelRecording() }
    func showShortcutError(_ error: ShortcutChangeError) { shortcutRecorder.showError(error) }
    public func updateMediaURL(_ url: URL?) {
        // Imports of the same format replace the bytes at the same stored URL.
        // Re-read the image after the owner's refresh, not just when its path changes.
        mediaURL = url; mediaPreview.image = url.flatMap { NSImage(contentsOf: $0) }
        updateMediaName(); updatePreview()
    }
    public func updateLoginStatus(_ status: LoginItemStatus) {
        loginStatus = status
        loginControl.allowsMixedState = true
        loginControl.state = status == .enabled ? .on : status == .requiresApproval ? .mixed : .off
        loginControl.title = status == .requiresApproval ? text("登录时启动（待系统批准）", "Launch at Login (Approval Required)") : text("登录时启动", "Launch at Login")
    }
    public func updateAngleStatus(_ status: LidAngleStatus) {
        lidStatus = status
        let supported: Bool
        if case .available = status { supported = true } else { supported = false }
        for control in [automaticControl, animationControl, triggerSlider, automaticScope] as [NSControl] {
            control.isEnabled = supported
            control.toolTip = supported ? nil : text("没有可读取的开合角度传感器，手动遮罩仍可用。", "No readable lid-angle sensor. Manual shading remains available.")
        }
        automaticControl.state = preferences.automaticEnabled && supported ? .on : .off
        switch status {
        case .available(let angle): sensorLabel.stringValue = text("当前开合角度：\(Int(angle.rounded()))°", "Current lid angle: \(Int(angle.rounded()))°")
        case .detecting: sensorLabel.stringValue = text("正在检测开合角度传感器…", "Detecting the lid-angle sensor…")
        case .unavailable: sensorLabel.stringValue = text("本机角度读取不可用，仍可使用快捷键遮罩和模拟预览。", "Lid angle unavailable. Shortcut shading and simulated preview still work.")
        case .stopped: sensorLabel.stringValue = text("角度检测已暂停", "Lid angle detection is paused")
        }
    }
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Permission prompts and System Settings may ask AppKit to close or
        // reorder this window while they hand control back. Veto that direct
        // request until the protected interaction has fully returned.
        !permissionSettingsInteraction
    }
    public func windowWillClose(_ notification: Notification) {
        guard !didNotifyClose else { return }
        cancelPendingOcclusionClose()
        permissionSettingsInteraction = false
        permissionSettingsLeftApplication = false
        permissionSettingsReturnedToApplication = false
        permissionSettingsRecoveryWorkItem?.cancel()
        permissionSettingsRecoveryWorkItem = nil
        didNotifyClose = true
        snapshotValidator.cancel()
        if captureVerification == .checking { updateCaptureVerification(.unchecked) }
        cancelShortcutRecording(); onClose()
    }
    public func windowDidBecomeKey(_ notification: Notification) {
        permissionSettingsDidReturnToApplication()
        onRefreshSystemState?(); updatePermissionStatus(); updatePreview()
    }
    public func windowDidChangeOcclusionState(_ notification: Notification) {
        if window?.occlusionState.contains(.visible) == true {
            hasBeenVisible = true
            occlusionCheckPending = false
            cancelPendingOcclusionClose()
            finishPermissionSettingsInteraction()
            return
        }
        scheduleCloseIfOccluded()
    }

    private func cancelPendingOcclusionClose() {
        pendingOcclusionClose?.cancel()
        pendingOcclusionClose = nil
    }

    private func permissionSettingsDidReturnToApplication() {
        guard permissionSettingsInteraction, permissionSettingsLeftApplication else { return }
        permissionSettingsReturnedToApplication = true
        finishPermissionSettingsInteraction()
    }

    private func beginPermissionSettingsInteraction() {
        cancelPendingOcclusionClose()
        // A native prompt may hand off directly to System Settings without
        // returning to this app. Preserve that in-flight departure state.
        guard !permissionSettingsInteraction else { return }
        permissionSettingsInteraction = true
        permissionSettingsLeftApplication = false
        permissionSettingsReturnedToApplication = false
    }

    private func finishPermissionSettingsInteraction() {
        // Activation/key-window notifications can arrive before visibility has
        // recovered. Keep protection until BOTH have happened, in either order.
        guard permissionSettingsInteraction, permissionSettingsReturnedToApplication,
              window?.occlusionState.contains(.visible) == true else { return }
        guard permissionSettingsRecoveryWorkItem == nil else { return }
        // A late occlusion notification can still describe the closing System
        // Settings window. Require a complete, stable visible interval before
        // ordinary full-coverage auto-close is armed again.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.permissionSettingsRecoveryWorkItem = nil
            guard self.permissionSettingsInteraction,
                  self.permissionSettingsReturnedToApplication,
                  self.window?.occlusionState.contains(.visible) == true,
                  self.window?.isVisible == true else { return }
            self.permissionSettingsInteraction = false
            self.permissionSettingsLeftApplication = false
            self.permissionSettingsReturnedToApplication = false
            self.permissionSettingsRecoveryWorkItem = nil
            self.occlusionCheckPending = false
            self.cancelPendingOcclusionClose()
        }
        permissionSettingsRecoveryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func scheduleCloseIfOccluded() {
        if interactionDepth > 0 { occlusionCheckPending = true; return }
        guard !permissionSettingsInteraction else { return }
        cancelPendingOcclusionClose()
        // Window ordering can briefly report invisibility while returning from
        // a system dialog. Require sustained full occlusion, not one run-loop tick.
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.didNotifyClose, self.hasBeenVisible,
                  !self.permissionSettingsInteraction else { return }
            if self.interactionDepth > 0 { self.occlusionCheckPending = true; return }
            guard
                  let window = self.window, window.isVisible, !window.isMiniaturized,
                  window.isOnActiveSpace, !NSApp.isHidden,
                  window.attachedSheet == nil, NSApp.modalWindow == nil,
                  !window.occlusionState.contains(.visible) else { return }
            window.close()
        }
        pendingOcclusionClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func withSettingsInteraction(_ action: () -> Void) {
        interactionDepth += 1
        defer {
            interactionDepth -= 1
            if interactionDepth == 0, occlusionCheckPending {
                occlusionCheckPending = false
                scheduleCloseIfOccluded()
            }
        }
        action()
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let sidebar = NSVisualEffectView(); sidebar.material = .sidebar; sidebar.blendingMode = .withinWindow
        let host = NSView()
        let ids = ["manual", "lid", "general"], symbols = ["keyboard", "laptopcomputer", "gearshape"]
        for index in 0..<3 {
            let button = SettingsNavigationButton(title: "", target: self, action: #selector(changePage(_:)))
            button.tag = index; button.identifier = NSUserInterfaceItemIdentifier("settingsTab.\(ids[index])")
            button.setButtonType(.toggle); button.isBordered = false; button.alignment = .left
            button.image = NSImage(systemSymbolName: symbols[index], accessibilityDescription: nil); button.imagePosition = .imageLeading
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true; tabs.append(button)
        }
        pin(vertical([label("AgentShade", "AgentShade", size: 17, weight: .semibold)] + tabs, spacing: 10), to: sidebar, inset: 14)
        content.addSubview(sidebar); content.addSubview(host)
        sidebar.translatesAutoresizingMaskIntoConstraints = false; host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor), sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor), sidebar.widthAnchor.constraint(equalToConstant: 185),
            host.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor), host.topAnchor.constraint(equalTo: content.topAnchor),
            host.trailingAnchor.constraint(equalTo: content.trailingAnchor), host.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        for (control, id) in [(manualScene, "manualScene"), (manualScope, "manualScope"), (automaticScope, "automaticScope")] {
            configure(control, id: id, action: #selector(changePreference(_:))); control.menu?.autoenablesItems = false
        }
        configure(chooseMedia, id: "chooseMedia", action: #selector(chooseMediaAction))
        configure(automaticControl, id: "automaticEnabled", action: #selector(toggleAutomaticAction))
        configure(animationControl, id: "angleAnimation", action: #selector(changePreference(_:)))
        configure(dismissalControl, id: "manualDismissRequiresShortcut", action: #selector(changePreference(_:)))
        configure(loginControl, id: "launchAtLogin", action: #selector(toggleLoginAction))
        configure(languageControl, id: "languageControl", action: #selector(toggleLanguageAction))
        configure(enhancedControl, id: "enhancedFrosting", action: #selector(changePreference(_:)))
        configure(lidEnhancedControl, id: "lidEnhancedFrosting", action: #selector(changePreference(_:)))
        configure(permissionButton, id: "permissionRequest", action: #selector(requestScreenPermission))
        configure(permissionRefreshButton, id: "permissionRefresh", action: #selector(refreshPermission))
        configure(permissionHelpButton, id: "configureRecording", action: #selector(configureRecording))
        configure(lidPermissionButton, id: "lidPermissionRequest", action: #selector(requestScreenPermission))
        configure(lidPermissionRefreshButton, id: "lidPermissionRefresh", action: #selector(refreshPermission))
        configure(lidPermissionHelpButton, id: "lidConfigureRecording", action: #selector(configureRecording))
        for (control, id) in [(captureVerifyButton, "captureVerify"), (lidCaptureVerifyButton, "lidCaptureVerify")] {
            configure(control, id: id, action: #selector(verifyCapture))
        }
        for button in [captureVerifyButton, lidCaptureVerifyButton] { button.bezelStyle = .rounded }
        for button in [chooseMedia, languageControl, permissionButton, permissionRefreshButton, permissionHelpButton, lidPermissionButton, lidPermissionRefreshButton, lidPermissionHelpButton ] { button.bezelStyle = .rounded }
        permissionLabel.identifier = NSUserInterfaceItemIdentifier("permissionStatus"); mediaName.identifier = NSUserInterfaceItemIdentifier("mediaName")
        lidPermissionLabel.identifier = NSUserInterfaceItemIdentifier("lidPermissionStatus")
        manualBlurHelp.identifier = NSUserInterfaceItemIdentifier("manualBlurHelp")
        automaticBlurHelp.identifier = NSUserInterfaceItemIdentifier("automaticBlurHelp")
        shortcutRecorder.identifier = NSUserInterfaceItemIdentifier("shortcutRecorder"); shortcutRecorder.heightAnchor.constraint(equalToConstant: 96).isActive = true
        for field in [mediaName, sensorLabel, restoreLabel, permissionLabel, lidPermissionLabel, manualBlurHelp, automaticBlurHelp, previewCaption, lidPreviewCaption, dismissalHint] {
            field.font = .systemFont(ofSize: 12); field.textColor = .secondaryLabelColor
            field.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        pages = [makeManualPage(), makeLidPage(), makeGeneralPage()]
        for (index, page) in pages.enumerated() { page.identifier = NSUserInterfaceItemIdentifier("settingsPage.\(ids[index])"); fill(page, in: host) }
    }
    private func makeManualPage() -> NSView {
        mediaControls = vertical([chooseMedia, mediaName], spacing: 5)
        manualFrostControls = vertical([
            slider("毛玻璃强度", "Frost strength", strengthSlider, id: "manualStrength"),
            manualBlurHelp
        ], spacing: 12)
        let controls = vertical([label("全局快捷键", "Global shortcut", size: 13, weight: .medium), shortcutRecorder,
                                group("遮罩类型", "Shade style", manualScene), group("覆盖屏幕", "Displays", manualScope), mediaControls, manualFrostControls], spacing: 16)
        blackPreview.wantsLayer = true; blackPreview.layer?.backgroundColor = NSColor.black.cgColor
        mediaPreview.imageScaling = .scaleProportionallyUpOrDown; mediaPreview.animates = true
        for view in [blackPreview, manualPreview, mediaPreview] { fill(view, in: previewHost) }
        stylePreview(previewHost)
        let right = vertical([label("效果预览", "Preview", size: 14, weight: .semibold), previewHost, previewCaption,
                              dismissalControl, dismissalHint], spacing: 12)
        return page("快捷键遮罩设置", "Shortcut Shade", "手动触发的设置，独立于合盖渐变。", "Manual shading, configured independently of lid shading.", body: columns(controls, right))
    }
    private func makeLidPage() -> NSView {
        lidPreview.wantsLayer = true
        lidPreview.layer?.cornerRadius = 12
        lidPreview.layer?.masksToBounds = true
        // Match the example desktop instead of squeezing it into a fixed height.
        lidPreview.heightAnchor.constraint(equalTo: lidPreview.widthAnchor, multiplier: 3.0 / 4.0).isActive = true
        automaticBlurControls = vertical([
            slider("模糊半径", "Blur radius", automaticBlurSlider, id: "automaticBlur"), automaticBlurHelp
        ], spacing: 8)
        let controls = vertical([automaticControl, sensorLabel, separator(),
            slider("起效角度 · 41°–95°", "Start angle · 41°–95°", triggerSlider, id: "triggerAngle", accessibility: ("触发开合角度", "Trigger lid angle")),
            restoreLabel, group("覆盖屏幕", "Displays", automaticScope), animationControl, separator(),
            automaticBlurControls, permissionPanel(lid: true)], spacing: 12)
        let right = vertical([label("模拟开合", "Simulate lid angle", size: 14, weight: .semibold), lidPreview,
            slider("模拟角度", "Preview angle", angleSlider, id: "previewAngle", accessibility: ("模拟开合角度", "Simulated lid angle"))], spacing: 8)
        let leftColumn = NSView(), rightColumn = NSView()
        leftColumn.identifier = NSUserInterfaceItemIdentifier("lidConfigurationColumn")
        rightColumn.identifier = NSUserInterfaceItemIdentifier("lidPreviewColumn")
        pin(controls, to: leftColumn, inset: 0); pin(right, to: rightColumn, inset: 0)
        let body = columns(leftColumn, rightColumn)
        // Reserve one stable area for the longest localized/authorized state.
        // Equal heights alone leave both wrapper heights underdetermined.
        leftColumn.heightAnchor.constraint(equalToConstant: 520).isActive = true
        leftColumn.heightAnchor.constraint(equalTo: rightColumn.heightAnchor).isActive = true
        return page("合盖渐变设置", "Lid Gradient", "固定毛玻璃效果，随着合盖逐渐加深。", "Frosted glass that deepens as you close the lid.", body: body)
    }
    private func makeGeneralPage() -> NSView {
        let body = vertical([
            permissionPanel(lid: false),
            horizontal([label("显示语言", "Language", size: 13, weight: .medium), NSView(), languageControl], spacing: 12),
            note("与状态栏菜单同步；首次使用跟随系统语言。", "Synced with the menu bar. First launch follows your system language."),
            separator(), loginControl,
            note("仅影响合盖：开启且已授权时，模糊桌面静止快照；否则使用底图渐变。快捷键毛玻璃始终使用蓝色渐变底图，不会中途换画面。", "Lid shading only: blur a still desktop snapshot when enabled and authorized; otherwise fade built-in artwork. Shortcut frosting always keeps its blue gradient artwork without switching images."),
            note("快照只在本机内存中处理，不保存、不上传、不录制视频。纯黑和自选图片不需要录屏权限。", "Snapshots stay in local memory: no saving, uploading or video recording. Black and custom images need no screen capture access.")], spacing: 18)
        return page("通用设置", "General", "启动、语言与权限，统一管理。", "Startup, language and permissions in one place.", body: body)
    }
    private func permissionPanel(lid: Bool) -> NSView {
        let button = lid ? lidPermissionHelpButton : permissionHelpButton
        let status = lid ? lidRecordingAccessLabel : recordingAccessLabel
        status.identifier = NSUserInterfaceItemIdentifier(lid ? "lidRecordingAccess" : "recordingAccess")
        status.font = .systemFont(ofSize: 12)
        button.widthAnchor.constraint(equalToConstant: 110).isActive = true
        status.setContentHuggingPriority(.required, for: .horizontal)
        let explanation = note("", "")
        explanation.identifier = NSUserInterfaceItemIdentifier(lid ? "lidRecordingExplanation" : "recordingExplanation")
        recordingExplanations.append(explanation)
        return vertical([horizontal([button, status, NSView()], spacing: 10), explanation], spacing: 6)
    }
    private func selectPage(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        if selectedPage != index { cancelShortcutRecording() }
        selectedPage = index
        for (i, page) in pages.enumerated() {
            page.isHidden = i != index; tabs[i].state = i == index ? .on : .off
            tabs[i].needsDisplay = true
        }
        window?.makeFirstResponder(tabs[index]); window?.contentView?.layoutSubtreeIfNeeded()
    }
    private func updateReadouts() {
        // Reset only when the configured start changes. Simulation edits and
        // unrelated refreshes keep their current value within the fixed range.
        if previewStartAngle != preferences.triggerAngle {
            previewStartAngle = preferences.triggerAngle
            angleSlider.doubleValue = preferences.triggerAngle
        }
        let range = "35°–95°"
        previewRangeTitle?.stringValue = text("模拟角度 · \(range)", "Preview angle · \(range)")
        for (slider, value, _, _) in sliderLabels {
            if slider === angleSlider || slider === triggerSlider { value.stringValue = "\(Int(slider.doubleValue.rounded()))°" }
            else if slider === automaticBlurSlider { value.stringValue = "\(Int(slider.doubleValue.rounded()))" }
            else { value.stringValue = "\(Int((slider.doubleValue * 100).rounded()))%" }
        }
        restoreLabel.stringValue = text("从起效角度合盖 30% 时，遮罩达 65% 不透明度，40° 最深；抬至 \(Int(preferences.restoreAngle))° 退出，避免抖动。", "From the start angle, 30% of lid travel reaches 65% opacity; full strength at 40°. Exit at \(Int(preferences.restoreAngle))° to prevent retriggering.")
    }
    private func updatePreview() {
        dismissalHint.stringValue = preferences.manualDismissRequiresShortcut
            ? text("再次按已设置的快捷键恢复，其他按键不会关闭遮罩。仅影响手动遮罩，后台任务继续运行。", "Press your configured shortcut again to dismiss; other keys are ignored. Manual shading only; background tasks keep running.")
            : text("按任意键恢复屏幕，后台任务不受遮罩影响。", "Press any key to dismiss. Shading does not interrupt background tasks.")
        let useSnapshot = preferences.enhancedFrostingEnabled && permissions.isGranted
        automaticBlurControls?.isHidden = !useSnapshot
        automaticBlurSlider.isEnabled = useSnapshot
        manualBlurHelp.stringValue = text("固定蓝色底图，强度调整遮罩深浅。", "Fixed blue artwork; strength adjusts shade depth.")
        automaticBlurHelp.stringValue = text("40° 时达到此半径；越大越模糊，不代表越暗。", "This radius is reached at 40°. Larger means blurrier, not darker.")
        manualFrostControls?.isHidden = !preferences.scene.isFrosted; mediaControls?.isHidden = preferences.scene != .media
        manualPreview.isHidden = !preferences.scene.isFrosted; mediaPreview.isHidden = preferences.scene != .media; blackPreview.isHidden = preferences.scene.isFrosted
        manualPreview.updateLanguage(preferences.language); lidPreview.updateLanguage(preferences.language)
        manualPreview.update(scene: .frostedDark, appearance: preferences.appearance, progress: preferences.manualFrostStrength, usesSnapshot: false, mode: .manual)
        let progress = angleSlider.doubleValue >= preferences.triggerAngle ? 0 : preferences.angleAnimationEnabled ? FrostedAppearance.progress(angle: angleSlider.doubleValue, triggerAngle: preferences.triggerAngle) : 1
        lidPreview.update(scene: .frostedDark, appearance: preferences.automaticAppearance, progress: progress, usesSnapshot: useSnapshot, mode: .lidAngle)
        let caption = useSnapshot ? text("示例桌面 · 增强模糊预览", "Example desktop · enhanced blur preview") : text("内置毛玻璃底图 · 不读取桌面", "Built-in frosted artwork · no desktop capture")
        let manualCaption = text("固定蓝色渐变底图 · 不透出桌面，不会中途更换画面。", "Fixed blue gradient artwork · No desktop showing through or image switching.")
        previewCaption.stringValue = preferences.scene == .black ? text("纯黑遮罩", "Black shade") : preferences.scene == .media ? text("自选图片 / GIF", "Custom image / GIF") : manualCaption
        lidPreviewCaption.stringValue = caption
    }
    private func updateMediaName() { mediaName.stringValue = mediaURL?.lastPathComponent ?? text("尚未选择图片", "No image selected") }
    private func updatePermissionStatus() {
        let allowed = permissions.isGranted
        for label in [recordingAccessLabel, lidRecordingAccessLabel] {
            label.stringValue = allowed ? text("录屏已授权", "Capture authorized") : text("内置毛玻璃可用", "Built-in frost ready")
            if !allowed && permissionRequestAccepted {
                label.stringValue = text("授权待生效", "Restart to apply")
            }
            label.textColor = allowed ? .systemGreen : .secondaryLabelColor
        }
        if previousPermission != allowed {
            snapshotValidator.cancel()
            captureVerification = .unchecked
            previousPermission = allowed
            onCaptureVerificationChange?(.unchecked)
        }
        if allowed {
            permissionRequestAccepted = false
            switch captureVerification {
            case .unchecked: permissionLabel.stringValue = text("屏幕录制：权限可用 · 尚未验证取图", "Screen Recording: available · snapshot not verified")
            case .checking: permissionLabel.stringValue = text("屏幕录制：正在验证取图…", "Screen Recording: verifying capture…")
            case .ready: permissionLabel.stringValue = text("屏幕录制：已验证取图成功", "Screen Recording: capture verified")
            case .failed: permissionLabel.stringValue = text("屏幕录制：权限可用，但取图失败或不完整 · 暂用内置底图，请重试", "Screen Recording: available, but capture failed or incomplete · using artwork; retry")
            }
        }
        else if permissionRequestAccepted { permissionLabel.stringValue = text("屏幕录制：已接受授权，请退出并重新打开 AgentShade", "Screen Recording: request accepted; quit and reopen AgentShade") }
        else { permissionLabel.stringValue = text("内置毛玻璃可正常使用。真实桌面模糊：当前应用未取得权限；需要此可选增强时再授权。", "Built-in frost works without permission. Desktop capture is not available to this app; grant access only for this optional enhancement.") }
        if !preferences.enhancedFrostingEnabled {
            permissionLabel.stringValue = text("内置底图模式 · 无需录屏权限，不模糊真实桌面", "Built-in artwork mode · no capture permission needed; no desktop blur")
        }
        permissionLabel.textColor = preferences.enhancedFrostingEnabled && allowed && captureVerification == .failed ? .systemOrange : .secondaryLabelColor
        let explanation = text("录屏权限仅用于合盖时获取桌面静止快照，在本机内存中模糊，不保存、不上传、不录音。", "Permission is used only for a still desktop snapshot during lid shading: local memory, no saving, uploading or audio.")
        for field in recordingExplanations {
            field.stringValue = permissionLabel.stringValue + "\n" + explanation
            field.textColor = permissionLabel.textColor
        }
        permissionButton.title = allowed ? text("当前应用可用", "Access Available") : text("授权屏幕录制…", "Allow Screen Recording…")
        permissionButton.isEnabled = !allowed && !permissionRequestAccepted
        for button in [permissionButton, lidPermissionButton] { button.isHidden = allowed || !preferences.enhancedFrostingEnabled }
        for button in [captureVerifyButton, lidCaptureVerifyButton] {
            button.isHidden = !allowed || !preferences.enhancedFrostingEnabled
            button.isEnabled = captureVerification != .checking
        }
        lidPermissionLabel.stringValue = permissionLabel.stringValue
        permissionHelpButton.toolTip = permissionLabel.stringValue
        lidPermissionHelpButton.toolTip = permissionLabel.stringValue
        lidPermissionLabel.textColor = permissionLabel.textColor
        lidPermissionButton.title = permissionButton.title
        lidPermissionButton.isEnabled = permissionButton.isEnabled
    }
    public func updateCaptureVerification(_ state: ScreenCaptureVerification) {
        updatePermissionStatus()
        captureVerification = state
        updatePermissionStatus()
        onCaptureVerificationChange?(captureVerification)
    }
    private func invalidateCaptureVerification() {
        snapshotValidator.cancel()
        updateCaptureVerification(.unchecked)
    }
    @objc private func changePage(_ sender: NSButton) { selectPage(sender.tag) }
    @objc private func chooseMediaAction() { withSettingsInteraction { onChooseMedia?() } }
    @objc private func toggleAutomaticAction() {
        guard case .available = lidStatus else { return }
        if let onToggleAutomatic { onToggleAutomatic() } else { preferences.automaticEnabled.toggle(); onChange() }
        updateAngleStatus(lidStatus)
    }
    @objc private func toggleLoginAction() { onToggleLogin?(); updateLoginStatus(loginStatus) }
    @objc private func toggleLanguageAction() {
        preferences.language = preferences.language == .chinese ? .english : .chinese
        refreshLanguage(); onLanguageChanged?()
    }
    @objc private func changePreference(_ sender: NSControl) {
        switch sender {
        case manualScene:
            guard let raw = manualScene.selectedItem?.representedObject as? String, let scene = ShadeScene(rawValue: raw) else { return }
            if scene == .media && mediaURL == nil { chooseMediaAction(); refreshPreferences(); return }
            preferences.scene = scene
        case manualScope: preferences.displayScope = ShadeDisplayScope(rawValue: manualScope.selectedItem?.representedObject as? String ?? "") ?? .all
        case automaticScope:
            preferences.automaticDisplayScope = ShadeDisplayScope(rawValue: automaticScope.selectedItem?.representedObject as? String ?? "") ?? .all
            invalidateCaptureVerification()
        case dismissalControl: preferences.manualDismissRequiresShortcut = dismissalControl.state == .on
        case strengthSlider: preferences.manualFrostStrength = strengthSlider.doubleValue
        case triggerSlider:
            preferences.triggerAngle = triggerSlider.doubleValue.rounded()
            angleSlider.doubleValue = preferences.triggerAngle
            previewStartAngle = preferences.triggerAngle
        case automaticBlurSlider: preferences.automaticBlurRadius = automaticBlurSlider.doubleValue
        case enhancedControl, lidEnhancedControl:
            preferences.enhancedFrostingEnabled = (sender as? NSButton)?.state == .on
            enhancedControl.state = preferences.enhancedFrostingEnabled ? .on : .off
            lidEnhancedControl.state = enhancedControl.state
            invalidateCaptureVerification()
        case animationControl: preferences.angleAnimationEnabled = animationControl.state == .on
        case angleSlider: updateReadouts(); updatePreview(); return
        default: return
        }
        updateReadouts(); updatePermissionStatus(); updatePreview(); onChange()
    }
    @objc private func refreshPermission() { updatePermissionStatus(); updatePreview() }
    @objc private func configureRecording() {
        withSettingsInteraction {
            preferences.enhancedFrostingEnabled = true
            // Begin before requesting access: the system prompt itself may
            // deactivate the app before the Settings launch call returns.
            beginPermissionSettingsInteraction()
            if !permissions.isGranted { permissionRequestAccepted = permissions.requestAccess() }
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                // The native permission prompt can complete an entire return
                // cycle above. System Settings is a separate external interaction.
                beginPermissionSettingsInteraction()
                // Opening another app is asynchronous. The synchronous interaction
                // guard above ends before System Settings can cover this window.
                if !openRecordingSettings(url) {
                    permissionSettingsInteraction = false
                    permissionSettingsLeftApplication = false
                    permissionSettingsReturnedToApplication = false
                    permissionSettingsRecoveryWorkItem?.cancel()
                    permissionSettingsRecoveryWorkItem = nil
                }
            }
            updatePermissionStatus(); updatePreview(); onChange()
        }
    }
    @objc private func verifyCapture() {
        guard permissions.isGranted, preferences.enhancedFrostingEnabled, captureVerification != .checking else { return }
        let ids = NSScreen.screens.compactMap { screen -> CGDirectDisplayID? in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
            return preferences.automaticDisplayScope == .builtIn && CGDisplayIsBuiltin(id) == 0 ? nil : id
        }
        updateCaptureVerification(.checking)
        snapshotValidator.capture(displayIDs: ids) { [weak self] images in
            guard let self, !self.didNotifyClose else { return }
            self.updateCaptureVerification(!ids.isEmpty && ids.allSatisfy { images[$0] != nil } ? .ready : .failed)
        }
    }
    @objc private func requestScreenPermission() {
        withSettingsInteraction { permissionRequestAccepted = permissions.requestAccess(); updatePermissionStatus(); updatePreview() }
    }
    @objc private func showPermissionHelp() {
        withSettingsInteraction { presentPermissionHelp() }
    }
    private func presentPermissionHelp() {
        let alert = NSAlert()
        alert.messageText = text("系统已开启，但当前应用仍不可用？", "Enabled in System Settings, but still unavailable?")
        alert.informativeText = text("1. 在“录屏与系统录音”中开启当前 AgentShade，然后退出并重新打开。\n2. 若开关已开但仍不可用，移除旧 AgentShade 项，再用“＋”添加下面的当前应用并授权。\n\n本地重新编译可能改变临时签名，旧授权无法匹配新版；仅重启不一定能修复。使用稳定代码签名可避免这一类更新问题。\n\n无权限时仍可使用内置底图；它不会读取或模糊真实桌面。\n\n当前应用：\(Bundle.main.bundleURL.path)", "1. Enable this AgentShade in Screen & System Audio Recording, then quit and reopen it.\n2. If access is still unavailable, remove the old AgentShade entry and use + to add the current app below and authorize it again.\n\nLocal rebuilds can change the ad-hoc signature, so an old grant may not match. Restarting alone may not fix this. Stable code signing avoids this class of update issue.\n\nBuilt-in artwork remains available without access; it does not read or blur the real desktop.\n\nCurrent app: \(Bundle.main.bundleURL.path)")
        alert.addButton(withTitle: text("打开系统设置", "Open System Settings")); alert.addButton(withTitle: text("关闭", "Close"))
        if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }
    private func text(_ zh: String, _ en: String) -> String { preferences.language.text(zh, en) }
    private func configure(_ control: NSControl, id: String, action: Selector) { control.identifier = NSUserInterfaceItemIdentifier(id); control.target = self; control.action = action }
    private func populate(_ popup: NSPopUpButton, values: [(String, String)], selected: String) {
        popup.removeAllItems()
        for (raw, title) in values { popup.addItem(withTitle: title); popup.lastItem?.representedObject = raw }
        popup.select(popup.itemArray.first { $0.representedObject as? String == selected })
    }
    private func label(_ zh: String, _ en: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text(zh, en)); field.font = .systemFont(ofSize: size, weight: weight)
        field.setContentCompressionResistancePriority(.required, for: .vertical); localizedFields.append((field, zh, en)); return field
    }
    private func note(_ zh: String, _ en: String) -> NSTextField { let field = label(zh, en, size: 12); field.textColor = .secondaryLabelColor; return field }
    private func slider(_ zh: String, _ en: String, _ slider: NSSlider, id: String, accessibility: (String, String)? = nil) -> NSView {
        let minimum = slider.minValue, maximum = slider.maxValue, valueBeforeCell = slider.doubleValue
        slider.cell = SettingsSliderCell()
        slider.minValue = minimum; slider.maxValue = maximum; slider.doubleValue = valueBeforeCell
        configure(slider, id: id, action: #selector(changePreference(_:))); slider.isContinuous = true
        slider.heightAnchor.constraint(equalToConstant: slider === angleSlider ? 36 : 24).isActive = true
        let value = NSTextField(labelWithString: ""); value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium); value.alignment = .right
        value.setContentHuggingPriority(.required, for: .horizontal)
        sliderLabels.append((slider, value, accessibility?.0 ?? zh, accessibility?.1 ?? en))
        let title = label(zh, en, weight: .medium)
        if slider === angleSlider { previewRangeTitle = title }
        return vertical([horizontal([title, NSView(), value], spacing: 8), slider], spacing: 4)
    }
    private func group(_ zh: String, _ en: String, _ control: NSView) -> NSView { vertical([label(zh, en, weight: .medium), control], spacing: 7) }
    private func separator() -> NSView { let box = NSBox(); box.boxType = .separator; box.heightAnchor.constraint(equalToConstant: 1).isActive = true; return box }
    private func stylePreview(_ view: NSView, height: CGFloat = 260) { view.wantsLayer = true; view.layer?.cornerRadius = 12; view.layer?.masksToBounds = true; view.heightAnchor.constraint(equalToConstant: height).isActive = true }
    private func page(_ zh: String, _ en: String, _ subtitleZH: String, _ subtitleEN: String, body: NSView) -> NSView {
        let heading = vertical([label(zh, en, size: 23, weight: .semibold), note(subtitleZH, subtitleEN)], spacing: 6)
        let result = NSView(); pin(vertical([heading, body], spacing: 16), to: result, inset: 20); return result
    }
    private func columns(_ left: NSView, _ right: NSView) -> NSView {
        left.widthAnchor.constraint(equalToConstant: 290).isActive = true
        let body = horizontal([left, right], spacing: 24); body.alignment = .top
        right.widthAnchor.constraint(equalTo: body.widthAnchor, constant: -314).isActive = true; return body
    }
    private func pin(_ child: NSView, to parent: NSView, inset: CGFloat) {
        parent.addSubview(child); child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset), child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset), child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset), child.bottomAnchor.constraint(lessThanOrEqualTo: parent.bottomAnchor, constant: -inset)])
    }
    private func fill(_ child: NSView, in parent: NSView) {
        parent.addSubview(child); child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo: parent.leadingAnchor), child.trailingAnchor.constraint(equalTo: parent.trailingAnchor), child.topAnchor.constraint(equalTo: parent.topAnchor), child.bottomAnchor.constraint(equalTo: parent.bottomAnchor)])
    }
    private func vertical(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing
        stack.distribution = .fill
        for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }; return stack
    }
    private func horizontal(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views); stack.orientation = .horizontal; stack.alignment = .centerY; stack.spacing = spacing
        stack.distribution = .fill
        return stack
    }
}
