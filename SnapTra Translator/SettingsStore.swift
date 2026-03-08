import AppKit
import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var playPronunciation: Bool {
        didSet { defaults.set(playPronunciation, forKey: AppSettingKey.playPronunciation) }
    }
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: AppSettingKey.launchAtLogin) }
    }
    @Published var singleKey: SingleKey {
        didSet { defaults.set(singleKey.rawValue, forKey: AppSettingKey.singleKey) }
    }
    @Published var sourceLanguage: String {
        didSet { defaults.set(sourceLanguage, forKey: AppSettingKey.sourceLanguage) }
    }
    @Published var targetLanguage: String {
        didSet { defaults.set(targetLanguage, forKey: AppSettingKey.targetLanguage) }
    }
    @Published var translationMode: TranslationMode {
        didSet { defaults.set(translationMode.rawValue, forKey: AppSettingKey.translationMode) }
    }
    @Published var defaultLookupDirection: LookupDirection {
        didSet { defaults.set(defaultLookupDirection.rawValue, forKey: AppSettingKey.defaultLookupDirection) }
    }
    @Published var debugShowOcrRegion: Bool {
        didSet { defaults.set(debugShowOcrRegion, forKey: AppSettingKey.debugShowOcrRegion) }
    }
    @Published var continuousTranslation: Bool {
        didSet { defaults.set(continuousTranslation, forKey: AppSettingKey.continuousTranslation) }
    }
    @Published var dictionarySources: [DictionarySource] {
        didSet {
            saveDictionarySources()
        }
    }
    @Published var ttsProvider: TTSProvider {
        didSet { defaults.set(ttsProvider.rawValue, forKey: AppSettingKey.ttsProvider) }
    }
    @Published var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: AppSettingKey.appLanguage)
            LocalizationManager.shared.setLanguage(appLanguage)
        }
    }

    private let defaults: UserDefaults
    private static let dictionarySourcesKey = "dictionarySources"

    init(defaults: UserDefaults = .standard, loginItemStatus: Bool? = nil) {
        self.defaults = defaults
        let playPronunciationValue = defaults.object(forKey: AppSettingKey.playPronunciation) as? Bool
        let launchAtLoginValue = defaults.object(forKey: AppSettingKey.launchAtLogin) as? Bool
        let loginStatus = loginItemStatus ?? LoginItemManager.isEnabled()
        let singleKeyValue = defaults.string(forKey: AppSettingKey.singleKey)
        let debugShowOcrRegionValue = defaults.object(forKey: AppSettingKey.debugShowOcrRegion) as? Bool
        let continuousTranslationValue = defaults.object(forKey: AppSettingKey.continuousTranslation) as? Bool
        let translationModeValue = defaults.string(forKey: AppSettingKey.translationMode)
        let defaultLookupDirectionValue = defaults.string(forKey: AppSettingKey.defaultLookupDirection)

        playPronunciation = playPronunciationValue ?? true
        launchAtLogin = launchAtLoginValue ?? loginStatus
        singleKey = SingleKey(rawValue: singleKeyValue ?? "leftControl") ?? .leftControl
        sourceLanguage = defaults.string(forKey: AppSettingKey.sourceLanguage) ?? "en"
        let defaultTarget = Self.defaultTargetLanguage()
        targetLanguage = defaults.string(forKey: AppSettingKey.targetLanguage) ?? defaultTarget
        translationMode = TranslationMode(rawValue: translationModeValue ?? TranslationMode.fixedDirection.rawValue) ?? .fixedDirection
        defaultLookupDirection = LookupDirection(rawValue: defaultLookupDirectionValue ?? LookupDirection.englishToChinese.rawValue) ?? .englishToChinese
        debugShowOcrRegion = debugShowOcrRegionValue ?? false
        continuousTranslation = continuousTranslationValue ?? true

        // Load or migrate dictionary sources
        dictionarySources = Self.loadOrMigrateDictionarySources(defaults: defaults)
        
        // Load TTS provider (migrate removed "edge" → "bing")
        var ttsProviderValue = defaults.string(forKey: AppSettingKey.ttsProvider)
        if ttsProviderValue == "edge" { ttsProviderValue = "bing" }
        ttsProvider = TTSProvider(rawValue: ttsProviderValue ?? "apple") ?? .apple
        
        // Load app language
        let appLanguageValue = defaults.string(forKey: AppSettingKey.appLanguage)
        appLanguage = AppLanguage(rawValue: appLanguageValue ?? "system") ?? .system
    }

    private static func loadOrMigrateDictionarySources(defaults: UserDefaults) -> [DictionarySource] {
        // Try to load existing sources
        if let data = defaults.data(forKey: dictionarySourcesKey),
           let sources = try? JSONDecoder().decode([DictionarySource].self, from: data) {
            return sources
        }

        // Check if ECDICT database is actually installed
        let ecdictInstalled = FileManager.default.fileExists(
            atPath: OfflineDictionaryService.databaseURL.path
        )

        // Create default configuration
        // ECDICT is enabled only if it's already installed
        let sources: [DictionarySource] = [
            DictionarySource(
                id: UUID(),
                name: L("Advanced Dictionary"),
                type: .ecdict,
                isEnabled: ecdictInstalled
            ),
            DictionarySource(
                id: UUID(),
                name: L("System Dictionary"),
                type: .system,
                isEnabled: true
            )
        ]

        return sources
    }

    private func saveDictionarySources() {
        if let data = try? JSONEncoder().encode(dictionarySources) {
            defaults.set(data, forKey: Self.dictionarySourcesKey)
        }
    }

    var hotkeyDisplayText: String {
        singleKey.title
    }

    var isAutoMutualTranslationEnabled: Bool {
        translationMode == .autoMutualChineseEnglish
    }

    var autoTranslateChineseIdentifier: String {
        if targetLanguage.hasPrefix("zh") {
            return targetLanguage
        }

        if sourceLanguage.hasPrefix("zh") {
            return sourceLanguage
        }

        return "zh-Hans"
    }

    var ocrRecognitionLanguageIdentifier: String {
        if isAutoMutualTranslationEnabled {
            return autoTranslateChineseIdentifier
        }
        return sourceLanguage
    }

    func resolvedLanguageIdentifiers(for direction: LookupDirection? = nil) -> (source: String, target: String) {
        if isAutoMutualTranslationEnabled {
            let resolvedDirection = direction ?? defaultLookupDirection
            let chineseIdentifier = autoTranslateChineseIdentifier
            return (
                resolvedDirection.sourceLanguageIdentifier(chineseIdentifier: chineseIdentifier),
                resolvedDirection.targetLanguageIdentifier(chineseIdentifier: chineseIdentifier)
            )
        }

        return (sourceLanguage, targetLanguage)
    }

    func autoMutualLanguagePairs() -> [(source: String, target: String)] {
        let chineseIdentifier = autoTranslateChineseIdentifier
        return [
            ("en", chineseIdentifier),
            (chineseIdentifier, "en"),
        ]
    }

    func setAutoMutualChineseIdentifier(_ identifier: String) {
        let normalizedIdentifier = identifier.hasPrefix("zh") ? identifier : "zh-Hans"

        if sourceLanguage.hasPrefix("zh") {
            sourceLanguage = normalizedIdentifier
            return
        }

        targetLanguage = normalizedIdentifier
    }

    private static func defaultTargetLanguage() -> String {
        let supportedLanguages: Set<String> = [
            "zh-Hans",
            "zh-Hant",
            "en",
            "ja",
            "ko",
            "fr",
            "de",
            "es",
            "it",
            "pt",
            "ru",
            "ar",
            "th",
            "vi",
        ]
        
        let preferredLanguages = Locale.preferredLanguages
        guard let firstPreferred = preferredLanguages.first else {
            return "zh-Hans"
        }
        
        let locale = Locale(identifier: firstPreferred)
        let languageCode = locale.language.languageCode?.identifier ?? ""
        
        if languageCode == "zh" {
            let script = locale.language.script?.identifier
            return script == "Hant" ? "zh-Hant" : "zh-Hans"
        }
        
        if supportedLanguages.contains(languageCode) {
            return languageCode
        }

        return "zh-Hans"
    }
}
