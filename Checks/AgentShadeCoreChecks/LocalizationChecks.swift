import Foundation
import AgentShadeCore

public func runLocalizationChecks() throws {
    let matches: [([String], AppLanguage)] = [
        (["zh"], .chinese),
        (["zh-Hans"], .chinese),
        (["zh-Hant"], .chinese),
        (["zh-TW"], .chinese),
        (["zh_HK"], .chinese),
        (["ZH-hans-CN"], .chinese),
        (["en"], .english),
        (["en-US"], .english),
        (["fr-FR"], .english),
        (["ja-JP"], .english),
        ([], .english),
        ([""], .english),
        (["zho"], .english),
        (["en-US", "zh-Hans"], .english),
        (["fr-FR", "zh-Hant"], .english),
        (["", "zh-Hans"], .english),
        (["zh-Hant", "en-US"], .chinese)
    ]
    for (preferredLanguages, expected) in matches {
        try expect(
            AppLanguage.matching(preferredLanguages: preferredLanguages) == expected,
            "Only the first preferred language must select Chinese for zh variants: \(preferredLanguages)"
        )
    }

    try expect(AppLanguage.chinese.text("中文内容", "English content") == "中文内容", "Chinese selection must display Chinese text")
    try expect(AppLanguage.english.text("中文内容", "English content") == "English content", "English selection must display English text")

    let initialSelections: [([String], AppLanguage, [String], AppLanguage)] = [
        (["zh-Hant"], .chinese, ["en-US"], .english),
        (["fr-FR", "zh-Hans"], .english, ["zh-Hans"], .chinese)
    ]
    for (firstSystemLanguages, initialLanguage, laterSystemLanguages, manualLanguage) in initialSelections {
        let suite = "AgentShadeChecks.Localization.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = ShadePreferences(defaults: defaults, preferredLanguages: firstSystemLanguages)
        try expect(settings.language == initialLanguage, "First launch must use the first system language")

        let reloaded = ShadePreferences(defaults: UserDefaults(suiteName: suite)!, preferredLanguages: laterSystemLanguages)
        try expect(reloaded.language == initialLanguage, "The initial language must persist when the system language changes")

        reloaded.language = manualLanguage
        let manuallySelected = ShadePreferences(defaults: UserDefaults(suiteName: suite)!, preferredLanguages: firstSystemLanguages)
        try expect(manuallySelected.language == manualLanguage, "A manual choice must persist across preference instances")
        try expect(settings.language == manualLanguage, "Existing preference instances must observe the manual language choice")
    }

    let sceneTitles: [(ShadeScene, String)] = [
        (.black, "纯黑"), (.media, "图片 / GIF"), (.frostedDark, "毛玻璃")
    ]
    for (scene, chineseTitle) in sceneTitles {
        try expect(scene.title == chineseTitle && scene.title(in: .chinese) == chineseTitle, "Chinese scene titles must preserve existing display names")
        try expect(!scene.title(in: .english).isEmpty && scene.title(in: .english) != chineseTitle, "Every scene must have an English title")
    }
    let scopeTitles: [(ShadeDisplayScope, String)] = [
        (.all, "全部屏幕（含外接屏）"), (.builtIn, "仅内置屏幕")
    ]
    for (scope, chineseTitle) in scopeTitles {
        try expect(scope.title == chineseTitle && scope.title(in: .chinese) == chineseTitle, "Chinese display titles must preserve existing display names")
        try expect(!scope.title(in: .english).isEmpty && scope.title(in: .english) != chineseTitle, "Every display scope must have an English title")
    }
}
