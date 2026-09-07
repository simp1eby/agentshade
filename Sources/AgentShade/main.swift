import AppKit
import Carbon
import Foundation
import AgentShadeCore

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

if CommandLine.arguments.contains("--self-test-hotkey") {
    application.finishLaunching()
    let hotKey = GlobalHotKey(
        keyCode: UInt32(kVK_ANSI_D),
        modifiers: UInt32(controlKey | optionKey | cmdKey),
        action: {}
    )
    let status = hotKey.register()
    let outputPath = CommandLine.arguments
        .first(where: { $0.hasPrefix("--self-test-output=") })?
        .replacingOccurrences(of: "--self-test-output=", with: "")
    if status == noErr {
        let result = "PASS: bundled global hotkey registration\n"
        print(result, terminator: "")
        if let outputPath {
            try? result.write(toFile: outputPath, atomically: true, encoding: .utf8)
        }
        hotKey.unregister()
        exit(0)
    }
    let result = "FAIL: bundled global hotkey registration (OSStatus \(status))\n"
    fputs(result, stderr)
    if let outputPath {
        try? result.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }
    exit(1)
}

let delegate = AppDelegate()
application.delegate = delegate
withExtendedLifetime(delegate) {
    application.run()
}
