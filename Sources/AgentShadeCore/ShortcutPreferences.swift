import Foundation

public final class ShortcutPreferences {
    private static let key = "globalShortcut"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var shortcut: Shortcut {
        get {
            guard let data = defaults.data(forKey: Self.key),
                  let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data), shortcut.isValid else { return .default }
            return shortcut
        }
        set {
            guard newValue.isValid, let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Self.key)
        }
    }
}
