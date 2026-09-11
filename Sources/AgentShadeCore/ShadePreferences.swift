import Foundation

public enum ShadeScene: String, CaseIterable {
    case black, media, frostedDark

    public var isFrosted: Bool { self == .frostedDark }
    public var title: String { title(in: .chinese) }

    public func title(in language: AppLanguage) -> String {
        switch self {
        case .black: return language.text("纯黑", "Black")
        case .media: return language.text("图片 / GIF", "Image / GIF")
        case .frostedDark: return language.text("毛玻璃", "Frosted Glass")
        }
    }
}

public enum ShadeDisplayScope: String, CaseIterable {
    case all, builtIn
    public var title: String { title(in: .chinese) }

    public func title(in language: AppLanguage) -> String {
        self == .all
            ? language.text("全部屏幕（含外接屏）", "All displays (including external)")
            : language.text("仅内置屏幕", "Built-in display only")
    }
}

public final class ShadePreferences {
    private static let materialTintOpacity = 0.12
    static let fullFrostAngle = 40.0
    // A start must be above the full-frost endpoint, including legacy values.
    static let angleRange = 41.0...95.0
    private static let languageKey = "appLanguage"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        if AppLanguage(rawValue: defaults.string(forKey: Self.languageKey) ?? "") == nil {
            defaults.set(AppLanguage.matching(preferredLanguages: preferredLanguages).rawValue, forKey: Self.languageKey)
        }
        for key in ["shadeScene", "automaticFrostedScene"] where defaults.string(forKey: key) == "frostedLight" {
            defaults.set(ShadeScene.frostedDark.rawValue, forKey: key)
        }
        migrateIndependentFrostingSettings()
    }

    public var language: AppLanguage {
        get { AppLanguage(rawValue: defaults.string(forKey: Self.languageKey) ?? "") ?? .english }
        set { defaults.set(newValue.rawValue, forKey: Self.languageKey) }
    }

    public var scene: ShadeScene {
        get {
            if let value = defaults.string(forKey: "shadeScene") {
                return ShadeScene(rawValue: value) ?? .black
            }
            return defaults.string(forKey: MediaStore.preferenceKey) == nil ? .black : .media
        }
        set { defaults.set(newValue.rawValue, forKey: "shadeScene") }
    }

    public var automaticScene: ShadeScene { .frostedDark }

    public var automaticEnabled: Bool {
        get { defaults.bool(forKey: "lidAutomationEnabled") }
        set { defaults.set(newValue, forKey: "lidAutomationEnabled") }
    }

    public var manualDismissRequiresShortcut: Bool {
        get { defaults.bool(forKey: "manualDismissRequiresShortcut") }
        set { defaults.set(newValue, forKey: "manualDismissRequiresShortcut") }
    }

    public var displayScope: ShadeDisplayScope {
        get { ShadeDisplayScope(rawValue: defaults.string(forKey: "shadeDisplayScope") ?? "") ?? .all }
        set { defaults.set(newValue.rawValue, forKey: "shadeDisplayScope") }
    }

    public var automaticDisplayScope: ShadeDisplayScope {
        get { ShadeDisplayScope(rawValue: defaults.string(forKey: "automaticShadeDisplayScope") ?? "") ?? .all }
        set { defaults.set(newValue.rawValue, forKey: "automaticShadeDisplayScope") }
    }

    public var triggerAngle: Double {
        get { number("triggerAngle", fallback: 80, range: Self.angleRange).rounded() }
        set { setNumber(newValue.rounded(), key: "triggerAngle", fallback: 80, range: Self.angleRange) }
    }
    public var restoreAngle: Double { triggerAngle + 5 }
    public var blurRadius: Double {
        get { number("frostedBlurRadius", fallback: FrostedAppearance.defaultBlurRadius, range: 0...60) }
        set { setNumber(newValue, key: "frostedBlurRadius", fallback: FrostedAppearance.defaultBlurRadius, range: 0...60) }
    }
    // Preserve legacy stored values for compatibility; rendering now uses the
    // shared fixed material tint instead of these removed settings.
    public var tintOpacity: Double {
        get { number("frostedTintOpacity", fallback: 0.12, range: 0...0.45) }
        set { setNumber(newValue, key: "frostedTintOpacity", fallback: 0.12, range: 0...0.45) }
    }
    public var automaticBlurRadius: Double {
        get { number("automaticFrostedBlurRadius", fallback: FrostedAppearance.defaultBlurRadius, range: 0...60) }
        set { setNumber(newValue, key: "automaticFrostedBlurRadius", fallback: FrostedAppearance.defaultBlurRadius, range: 0...60) }
    }
    public var automaticTintOpacity: Double {
        get { number("automaticFrostedTintOpacity", fallback: 0.12, range: 0...0.45) }
        set { setNumber(newValue, key: "automaticFrostedTintOpacity", fallback: 0.12, range: 0...0.45) }
    }
    public var manualFrostStrength: Double {
        get { number("manualFrostStrength", fallback: 0.5, range: 0...1) }
        set { setNumber(newValue, key: "manualFrostStrength", fallback: 0.5, range: 0...1) }
    }
    /// Legacy compatibility only. Vertical stretch is no longer part of frosting.
    public var stretchAmount: Double {
        get { 0 }
        set {}
    }
    public var enhancedFrostingEnabled: Bool {
        get { defaults.object(forKey: "enhancedFrostingEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enhancedFrostingEnabled") }
    }
    public var angleAnimationEnabled: Bool {
        get { defaults.object(forKey: "angleAnimationEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "angleAnimationEnabled") }
    }
    public var appearance: FrostedAppearance {
        FrostedAppearance(blurRadius: blurRadius, tintOpacity: Self.materialTintOpacity)
    }
    public var automaticAppearance: FrostedAppearance {
        FrostedAppearance(blurRadius: automaticBlurRadius, tintOpacity: Self.materialTintOpacity)
    }

    private func migrateIndependentFrostingSettings() {
        let marker = "independentFrostingSettingsMigrated"
        guard !defaults.bool(forKey: marker) else { return }
        // Capture the old shared values before any accessor can mutate its now
        // manual-only setting. Existing independent keys always take precedence.
        if defaults.object(forKey: "automaticShadeDisplayScope") == nil {
            defaults.set(displayScope.rawValue, forKey: "automaticShadeDisplayScope")
        }
        if defaults.object(forKey: "automaticFrostedBlurRadius") == nil {
            defaults.set(blurRadius, forKey: "automaticFrostedBlurRadius")
        }
        if defaults.object(forKey: "automaticFrostedTintOpacity") == nil {
            defaults.set(tintOpacity, forKey: "automaticFrostedTintOpacity")
        }
        defaults.set(true, forKey: marker)
    }

    private func number(_ key: String, fallback: Double, range: ClosedRange<Double>) -> Double {
        let value = (defaults.object(forKey: key) as? NSNumber)?.doubleValue ?? fallback
        return value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }

    private func setNumber(_ value: Double, key: String, fallback: Double, range: ClosedRange<Double>) {
        defaults.set(value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback, forKey: key)
    }
}
