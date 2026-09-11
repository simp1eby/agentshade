import AppKit
import Carbon
import UniformTypeIdentifiers

public protocol LoginItemManaging: AnyObject {
    var status: LoginItemStatus { get }
    func setEnabled(_ enabled: Bool) throws
}

extension LoginItemController: LoginItemManaging {}

public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let mediaStore: MediaStore
    private let preferences: ShadePreferences
    private let permissions: ScreenCapturePermissionChecking
    private let shortcutPreferences: ShortcutPreferences
    private let lidMonitor = LidAngleMonitor()
    private let loginItemController: LoginItemManaging
    private var lastCaptureContext = ""
    private var captureContext: String {
        let ids = NSScreen.screens.compactMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
        return preferences.automaticDisplayScope.rawValue + ":" + ids.sorted().map(String.init).joined(separator: ",")
    }
    private var lastCaptureVerification: ScreenCaptureVerification = .unchecked {
        didSet { lastCaptureContext = captureContext }
    }
    private lazy var shadeController: ShadeController = {
        let controller = ShadeController(mediaStore: mediaStore, preferences: preferences)
        controller.onSnapshotStatusChange = { [weak self] state in
            self?.lastCaptureVerification = state
            self?.settingsController?.updateCaptureVerification(state)
        }
        return controller
    }()
    private var statusItem: NSStatusItem?
    private lazy var shortcutManager = ShortcutManager(preferences: shortcutPreferences) { [weak self] in
        self?.shadeController.toggle()
    }
    private var isTerminating = false
    private weak var automaticMenuItem: NSMenuItem?
    private weak var currentMenu: NSMenu?
    private var sleepObservers: [NSObjectProtocol] = []
    private var lidStatus: LidAngleStatus = .stopped
    private var lidSensorAvailable = false
    private var settingsController: FrostedSettingsWindowController?
    private var menuLanguage: AppLanguage?

    public init(preferences: ShadePreferences = ShadePreferences(), permissions: ScreenCapturePermissionChecking = SystemScreenCapturePermission(), shortcutPreferences: ShortcutPreferences = ShortcutPreferences(), mediaStore: MediaStore = MediaStore(), loginItemController: LoginItemManaging = LoginItemController()) {
        self.preferences = preferences
        self.permissions = permissions
        self.shortcutPreferences = shortcutPreferences
        self.mediaStore = mediaStore
        self.loginItemController = loginItemController
        super.init()
    }

    private func text(_ chinese: String, _ english: String) -> String {
        preferences.language.text(chinese, english)
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination(
            "AgentShade must stay available for its global shortcut"
        )
        configureStatusItem()
        registerGlobalHotKey()
        configureLidAutomation()
        if CommandLine.arguments.contains("--settings") { showFrostedSettings() }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        settingsController?.cancelShortcutRecording()
        lidMonitor.stop()
        for observer in sleepObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        shadeController.deactivate(isUserInitiated: false)
        shortcutManager.unregister()
    }

    private func configureStatusItem() {
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = StatusItemIcon.make()
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "AgentShade (\(shortcutManager.shortcut.displayText))"
        }
        statusItem = item
        item.menu = makeMenu(item.menu ?? currentMenu ?? NSMenu())
    }

    func makeMenu(_ menu: NSMenu = NSMenu()) -> NSMenu {
        menuLanguage = preferences.language
        currentMenu = menu
        menu.removeAllItems()
        menu.autoenablesItems = false
        let shadeItem = NSMenuItem(title: text("立即遮罩", "Shade Now"), action: #selector(shadeNow), keyEquivalent: shortcutManager.shortcut.keyEquivalent)
        shadeItem.keyEquivalentModifierMask = shortcutManager.shortcut.modifierFlags
        shadeItem.target = self
        menu.addItem(shadeItem)

        automaticMenuItem = addMenuItem(title: "", action: #selector(toggleAutomatic), to: menu)
        automaticMenuItem?.identifier = NSUserInterfaceItemIdentifier("automaticShadingToggle")

        menu.addItem(.separator())
        let settingsItem = addMenuItem(title: text("设置…", "Settings…"), action: #selector(showFrostedSettings), to: menu)
        settingsItem.identifier = NSUserInterfaceItemIdentifier("openSettings")
        let languageButton = addMenuItem(title: preferences.language == .chinese ? "English" : "中文", action: #selector(selectLanguage(_:)), to: menu)
        languageButton.identifier = NSUserInterfaceItemIdentifier("languageToggle")
        languageButton.toolTip = text("切换为英文", "Switch to Chinese")

        menu.addItem(.separator())
        addMenuItem(title: text("退出 AgentShade", "Quit AgentShade"), action: #selector(quit), to: menu)
        menu.delegate = self
        updateMenuItems()
        return menu
    }

    public func menuWillOpen(_ menu: NSMenu) {
        if lidStatus == .stopped { lidMonitor.start() }
        refreshSettingsState()
        updateMenuItems()
    }

    @discardableResult
    private func addMenuItem(title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    private func registerGlobalHotKey() {
        if case .failure(let error) = shortcutManager.start() {
            DispatchQueue.main.async { [weak self] in
                self?.showAlert(
                    title: self?.text("快捷键注册失败", "Shortcut Unavailable") ?? "AgentShade",
                    message: error.message(in: self?.preferences.language ?? .english)
                )
            }
        }
    }

    @objc private func shadeNow() {
        shadeController.activate()
    }

    @objc private func chooseMedia() {
        defer {
            refreshSettingsState()
            updateMenuItems()
        }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = text("选择遮罩图片或 GIF", "Choose a Shade Image or GIF")
        panel.prompt = text("使用此图片", "Use Image")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.gif, .png, .jpeg, .heic, .webP]

        guard panel.runModal() == .OK, let source = panel.url else { return }
        guard NSImage(contentsOf: source) != nil else {
            showAlert(title: text("无法读取图片", "Cannot Read Image"), message: text("请选择有效的 GIF、PNG、JPEG、HEIC 或 WebP 图片。", "Choose a valid GIF, PNG, JPEG, HEIC, or WebP image."))
            return
        }

        do {
            try mediaStore.importMedia(from: source)
            preferences.scene = .media
            shadeController.refreshPreferences()
        } catch {
            showAlert(title: text("保存图片失败", "Cannot Save Image"), message: error.localizedDescription)
        }
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        preferences.language = preferences.language == .chinese ? .english : .chinese
        languageDidChange()
    }

    private func languageDidChange() {
        settingsController?.refreshLanguage()
        refreshSettingsState()
        updateMenuItems()
    }

    @objc private func toggleAutomatic() {
        defer { refreshSettingsState(); updateMenuItems() }
        guard lidSensorAvailable else { return }
        preferences.automaticEnabled.toggle()
        shadeController.suspendAutomation(resetSuppression: true)
        if preferences.automaticEnabled || settingsController != nil { lidMonitor.start() } else { lidMonitor.stop() }
    }

    private func updateMenuItems() {
        if menuLanguage != preferences.language {
            if let currentMenu { _ = makeMenu(currentMenu) }
            return
        }
        automaticMenuItem?.isEnabled = lidSensorAvailable
        automaticMenuItem?.state = preferences.automaticEnabled && lidSensorAvailable ? .on : .off
        automaticMenuItem?.toolTip = lidSensorAvailable ? nil : text("需要本机具有可读取的开合角度传感器，手动遮罩仍可用", "Requires a readable lid-angle sensor. Manual shading remains available.")
        automaticMenuItem?.title = text("开合自动遮罩", "Auto Lid Shading")
        settingsController?.updateAngleStatus(lidStatus)
    }

    private func refreshSettingsState() {
        guard let settingsController else { return }
        settingsController.refreshPreferences()
        settingsController.updateAngleStatus(lidStatus)
        settingsController.updateLoginStatus(loginItemController.status)
        settingsController.updateMediaURL(mediaStore.selectedMediaURL)
    }

    @objc private func showFrostedSettings() {
        if settingsController == nil {
            settingsController = FrostedSettingsWindowController(preferences: preferences, permissions: permissions,
                shortcut: shortcutManager.shortcut, onShortcutChange: { [weak self] candidate in
                    guard let self else { return .failure(.registrationFailed(OSStatus(eventNotHandledErr))) }
                    let result = self.shortcutManager.replace(with: candidate)
                    if case .success = result {
                        self.configureStatusItem()
                    }
                    return result
                }, onShortcutRecordingChanged: { [weak self] recording in
                    guard let self, !self.isTerminating else { return }
                    if recording {
                        // Registered Carbon shortcuts consume their key events.
                        // Pause ours so the settings recorder can receive them.
                        self.shortcutManager.unregister()
                    } else if case .failure(let error) = self.shortcutManager.start() {
                        self.settingsController?.showShortcutError(error)
                    }
                }, onChange: { [weak self] in
                self?.shadeController.refreshPreferences()
                self?.updateMenuItems()
            }, onClose: { [weak self] in
                guard let self else { return }
                if !self.isTerminating { self.shadeController.automationPaused = false }
                if !self.preferences.automaticEnabled { self.lidMonitor.stop() }
                self.settingsController = nil
            })
            settingsController?.onChooseMedia = { [weak self] in self?.chooseMedia() }
            settingsController?.onRestart = { [weak self] in self?.restartApplication() }
            settingsController?.onCaptureVerificationChange = { [weak self] state in self?.lastCaptureVerification = state }
            settingsController?.onToggleAutomatic = { [weak self] in self?.toggleAutomatic() }
            settingsController?.onToggleLogin = { [weak self] in self?.toggleLaunchAtLogin() }
            settingsController?.onLanguageChanged = { [weak self] in self?.languageDidChange() }
            settingsController?.onRefreshSystemState = { [weak self] in
                guard let self else { return }
                self.settingsController?.updateLoginStatus(self.loginItemController.status)
            }
        }
        shadeController.automationPaused = true
        lidMonitor.start()
        refreshSettingsState()
        settingsController?.show()
        if lastCaptureContext != captureContext { lastCaptureVerification = .unchecked }
        if lastCaptureVerification != .checking { settingsController?.updateCaptureVerification(lastCaptureVerification) }
    }

    private func restartApplication() {
        guard !isTerminating else { return }
        isTerminating = true
        settingsController?.cancelShortcutRecording()
        shortcutManager.unregister()
        lidMonitor.stop()
        shadeController.automationPaused = true
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--settings"]
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] app, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if app != nil, error == nil { NSApp.terminate(nil) }
                else {
                    self.isTerminating = false
                    self.shadeController.automationPaused = self.settingsController != nil
                    self.registerGlobalHotKey(); self.lidMonitor.start()
                    self.showAlert(title: self.text("重启失败", "Restart Failed"), message: error?.localizedDescription ?? self.text("请手动退出并重新打开 AgentShade。", "Quit and reopen AgentShade manually."))
                }
            }
        }
    }

    private func configureLidAutomation() {
        lidMonitor.onUpdate = { [weak self] status in
            self?.updateLidStatus(status)
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            sleepObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.lidMonitor.stop()
                self?.shadeController.displayWillSleep()
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            sleepObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.shadeController.displayDidWake()
                if self.preferences.automaticEnabled || self.settingsController != nil { self.lidMonitor.start() }
            })
        }
        // Probe capability even when automation is off. Stop after one result
        // unless live readings are needed; opening the menu/settings retries.
        lidMonitor.start()
    }

    func updateLidStatus(_ status: LidAngleStatus) {
        lidStatus = status
        switch status {
        case .available(let angle):
            lidSensorAvailable = true
            shadeController.updateLidAngle(angle)
        case .unavailable:
            lidSensorAvailable = false
            shadeController.updateLidAngle(nil)
        case .stopped, .detecting: break
        }
        updateMenuItems()
        if !preferences.automaticEnabled, settingsController == nil {
            switch status {
            case .available, .unavailable: lidMonitor.stop()
            case .stopped, .detecting: break
            }
        }
    }

    @objc private func toggleLaunchAtLogin() {
        defer { refreshSettingsState() }
        let intent = loginItemController.status.toggleIntent
        if intent == .showApprovalInstructions {
            showLaunchAtLoginApprovalAlert()
            return
        }

        do {
            try loginItemController.setEnabled(intent == .enable)
            if loginItemController.status == .requiresApproval {
                showLaunchAtLoginApprovalAlert()
            }
        } catch {
            showAlert(title: text("无法修改登录项", "Cannot Change Login Item"), message: error.localizedDescription)
        }
    }

    private func showLaunchAtLoginApprovalAlert() {
        showAlert(
            title: text("需要确认", "Approval Required"),
            message: text("请在“系统设置 → 通用 → 登录项与扩展”中允许 AgentShade。", "Allow AgentShade in System Settings → General → Login Items & Extensions.")
        )
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: text("好", "OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
