import Foundation

public final class MediaStore {
    public static let preferenceKey = "selectedMediaPath"

    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let mediaDirectory: URL

    public convenience init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.init(
            fileManager: .default,
            defaults: .standard,
            applicationSupportURL: base.appendingPathComponent("AgentShade", isDirectory: true)
        )
    }

    public init(
        fileManager: FileManager,
        defaults: UserDefaults,
        applicationSupportURL: URL
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.mediaDirectory = applicationSupportURL
    }

    public var selectedMediaURL: URL? {
        guard let path = defaults.string(forKey: Self.preferenceKey) else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            defaults.removeObject(forKey: Self.preferenceKey)
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    @discardableResult
    public func importMedia(from source: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw CocoaError(.fileNoSuchFile)
        }

        try fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let pathExtension = source.pathExtension.lowercased()
        let filename = pathExtension.isEmpty ? "shade-background" : "shade-background.\(pathExtension)"
        let destination = mediaDirectory.appendingPathComponent(filename)
        let staged = mediaDirectory.appendingPathComponent("import-\(UUID().uuidString)")

        do {
            try fileManager.copyItem(at: source, to: staged)
            try removeCopiedMedia(except: staged)
            try fileManager.moveItem(at: staged, to: destination)
            defaults.set(destination.path, forKey: Self.preferenceKey)
            return destination
        } catch {
            try? fileManager.removeItem(at: staged)
            throw error
        }
    }

    public func useBlack() {
        try? removeCopiedMedia(except: nil)
        defaults.removeObject(forKey: Self.preferenceKey)
    }

    private func removeCopiedMedia(except excludedURL: URL?) throws {
        guard fileManager.fileExists(atPath: mediaDirectory.path) else { return }
        let files = try fileManager.contentsOfDirectory(
            at: mediaDirectory,
            includingPropertiesForKeys: nil
        )
        for file in files where file.lastPathComponent.hasPrefix("shade-background") && file != excludedURL {
            try fileManager.removeItem(at: file)
        }
    }
}
