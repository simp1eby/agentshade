import AppKit
@testable import AgentShadeCore

private final class PreviewWithoutCapture: ScreenCapturePermissionChecking {
    var isGranted = false
    func requestAccess() -> Bool { false }
}

private func linkedPreviewChildren(_ view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + linkedPreviewChildren($0) }
}

func runLinkedLidPreviewChecks() throws {
    try runSimpleLidSettingsChecks()
}

func runSharedFrostedPaletteChecks() throws {
    _ = NSApplication.shared
    let bitmap = CGContext(data: nil, width: 384, height: 256, bitsPerComponent: 8, bytesPerRow: 1536,
                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    bitmap.setFillColor(CGColor(gray: 0.8, alpha: 1)); bitmap.fill(CGRect(x: 0, y: 0, width: 384, height: 256))
    let source = bitmap.makeImage()!
    let renderer = FrostedImageRenderer()
    let appearance = FrostedAppearance(blurRadius: 28, tintOpacity: 0.12)
    func color(_ progress: Double) throws -> NSColor {
        guard let image = renderer.render(source: source, scene: .frostedDark, appearance: appearance, progress: progress) else {
            throw CheckFailure.failed("The synthetic palette check requires an available Core Image renderer")
        }
        return NSBitmapImageRep(cgImage: image).colorAt(x: 192, y: 128)!.usingColorSpace(.deviceRGB)!
    }
    let clear = try color(0), early = try color(0.65), deep = try color(1)
    try expect(deep.blueComponent - deep.redComponent > 0.1, "A gray desktop must gain the shared blue material instead of staying gray-white at full lid blur")
    let material = BuiltInFrostedView(frame: NSRect(x: 0, y: 0, width: 384, height: 256))
    let image = linkedPreviewChildren(material).compactMap { $0 as? NSImageView }.first { $0.image != nil }!.image!
    let artwork = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!).colorAt(x: 192, y: 128)!.usingColorSpace(.deviceRGB)!
    try expect(abs(artwork.hueComponent - deep.hueComponent) < 0.08, "Snapshot and manual artwork must use the same blue hue family")
    try expect(early.redComponent < clear.redComponent && early.redComponent > deep.redComponent, "The shared palette at 30% travel must visibly deepen without reaching its final depth")
    try expect(abs(clear.redComponent - clear.blueComponent) < 0.01, "The start angle must preserve the original desktop color")
    print("PASS: shared blue palette in actual rendered pixels with a clear, gentle start")
}
