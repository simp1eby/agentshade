import AppKit

public final class ShadeController {
    private let mediaStore: MediaStore
    private let session = ShadeSession()
    private var keyboardMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var previousApplication: NSRunningApplication?
    private var cursorHidden = false

    public init(mediaStore: MediaStore) {
        self.mediaStore = mediaStore
    }

    deinit {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if cursorHidden {
            NSCursor.unhide()
        }
    }

    public var isActive: Bool { session.isActive }

    public func toggle() {
        isActive ? deactivate() : activate()
    }

    public func activate() {
        guard !isActive, !NSScreen.screens.isEmpty else { return }

        let currentApplication = NSWorkspace.shared.frontmostApplication
        if currentApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = currentApplication
        }

        let windows = makeWindows()
        guard session.activate(with: windows) else { return }

        installKeyboardMonitor()
        installScreenObserver()
        NSCursor.hide()
        cursorHidden = true

        NSApp.activate(ignoringOtherApps: true)
        show(windows)
    }

    public func deactivate() {
        guard isActive else { return }

        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }

        _ = session.deactivate()
        if cursorHidden {
            NSCursor.unhide()
            cursorHidden = false
        }

        let applicationToRestore = previousApplication
        previousApplication = nil
        DispatchQueue.main.async {
            _ = applicationToRestore?.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func makeWindows() -> [ShadeWindow] {
        let image: NSImage?
        if let mediaURL = mediaStore.selectedMediaURL {
            image = NSImage(contentsOf: mediaURL)
            if image == nil {
                mediaStore.useBlack()
            }
        } else {
            image = nil
        }

        return NSScreen.screens.map { screen in
            ShadeWindow(screen: screen, image: image) { [weak self] in
                self?.deactivate()
            }
        }
    }

    private func show(_ windows: [ShadeWindow]) {
        for window in windows {
            window.orderFrontRegardless()
        }
        windows.first?.makeKeyAndOrderFront(nil)
    }

    private func installKeyboardMonitor() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.deactivate()
            }
            return nil
        }
    }

    private func installScreenObserver() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildWindowsForCurrentScreens()
        }
    }

    private func rebuildWindowsForCurrentScreens() {
        guard isActive else { return }
        let windows = makeWindows()
        session.replace(with: windows)
        show(windows)
    }
}
