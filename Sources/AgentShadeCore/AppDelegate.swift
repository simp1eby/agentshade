import AppKit
import Carbon
import UniformTypeIdentifiers

public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let mediaStore = MediaStore()
    private let loginItemController = LoginItemController()
    private lazy var shadeController = ShadeController(mediaStore: mediaStore)
    private var statusItem: NSStatusItem?
    private var hotKey: GlobalHotKey?
    private weak var launchAtLoginMenuItem: NSMenuItem?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination(
            "AgentShade must stay available for its global shortcut"
        )
        configureStatusItem()
        registerGlobalHotKey()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        shadeController.deactivate()
        hotKey?.unregister()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = StatusItemIcon.make()
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "AgentShade（⌃⌥⌘D）"
        }

        let menu = NSMenu()
        let shadeItem = NSMenuItem(title: "立即遮罩", action: #selector(shadeNow), keyEquivalent: "d")
        shadeItem.keyEquivalentModifierMask = [.control, .option, .command]
        shadeItem.target = self
        menu.addItem(shadeItem)

        menu.addItem(.separator())
        addMenuItem(title: "选择图片或 GIF…", action: #selector(chooseMedia), to: menu)
        addMenuItem(title: "使用纯黑", action: #selector(useBlack), to: menu)

        menu.addItem(.separator())
        let loginItem = addMenuItem(title: "登录时启动", action: #selector(toggleLaunchAtLogin), to: menu)
        launchAtLoginMenuItem = loginItem
        updateLaunchAtLoginMenuItem()

        menu.addItem(.separator())
        addMenuItem(title: "退出 AgentShade", action: #selector(quit), to: menu)
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    public func menuWillOpen(_ menu: NSMenu) {
        updateLaunchAtLoginMenuItem()
    }

    @discardableResult
    private func addMenuItem(title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    private func registerGlobalHotKey() {
        let hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_D),
            modifiers: UInt32(controlKey | optionKey | cmdKey)
        ) { [weak self] in
            self?.shadeController.toggle()
        }
        self.hotKey = hotKey
        let status = hotKey.register()
        if status != noErr {
            DispatchQueue.main.async { [weak self] in
                self?.showAlert(
                    title: "快捷键注册失败",
                    message: "⌃⌥⌘D 可能已被其他应用占用（错误码 \(status)）。仍可从菜单栏选择“立即遮罩”。"
                )
            }
        }
    }

    @objc private func shadeNow() {
        shadeController.activate()
    }

    @objc private func chooseMedia() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "选择遮罩图片或 GIF"
        panel.prompt = "使用此图片"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.gif, .png, .jpeg, .heic, .webP]

        guard panel.runModal() == .OK, let source = panel.url else { return }
        guard NSImage(contentsOf: source) != nil else {
            showAlert(title: "无法读取图片", message: "请选择有效的 GIF、PNG、JPEG、HEIC 或 WebP 图片。")
            return
        }

        do {
            try mediaStore.importMedia(from: source)
        } catch {
            showAlert(title: "保存图片失败", message: error.localizedDescription)
        }
    }

    @objc private func useBlack() {
        mediaStore.useBlack()
    }

    @objc private func toggleLaunchAtLogin() {
        let intent = loginItemController.status.toggleIntent
        if intent == .showApprovalInstructions {
            showLaunchAtLoginApprovalAlert()
            return
        }

        do {
            try loginItemController.setEnabled(intent == .enable)
            updateLaunchAtLoginMenuItem()
            if loginItemController.status == .requiresApproval {
                showLaunchAtLoginApprovalAlert()
            }
        } catch {
            showAlert(title: "无法修改登录项", message: error.localizedDescription)
        }
    }

    private func updateLaunchAtLoginMenuItem() {
        guard let launchAtLoginMenuItem else { return }
        switch loginItemController.status {
        case .enabled:
            launchAtLoginMenuItem.title = "登录时启动"
            launchAtLoginMenuItem.state = .on
        case .requiresApproval:
            launchAtLoginMenuItem.title = "登录时启动（待系统批准）"
            launchAtLoginMenuItem.state = .mixed
        case .disabled:
            launchAtLoginMenuItem.title = "登录时启动"
            launchAtLoginMenuItem.state = .off
        }
    }

    private func showLaunchAtLoginApprovalAlert() {
        showAlert(
            title: "需要确认",
            message: "请在“系统设置 → 通用 → 登录项与扩展”中允许 AgentShade。"
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
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
