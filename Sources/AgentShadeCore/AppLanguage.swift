public enum AppLanguage: String, CaseIterable {
    case chinese = "zh-Hans"
    case english = "en"

    public static func matching(preferredLanguages: [String]) -> AppLanguage {
        let first = preferredLanguages.first?.lowercased() ?? ""
        return first == "zh" || first.hasPrefix("zh-") || first.hasPrefix("zh_") ? .chinese : .english
    }

    public func text(_ chinese: String, _ english: String) -> String {
        self == .chinese ? chinese : english
    }
}
