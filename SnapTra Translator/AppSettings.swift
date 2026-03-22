import Foundation

enum SingleKey: String, CaseIterable, Identifiable {
    case shift
    case control
    case option
    case command
    case fn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shift:
            return L("Shift")
        case .control:
            return L("Control")
        case .option:
            return L("Option")
        case .command:
            return L("Command")
        case .fn:
            return "Fn"
        }
    }

    static func migrated(from storedValue: String?) -> SingleKey {
        switch storedValue {
        case Self.shift.rawValue, "leftShift", "rightShift":
            return .shift
        case Self.control.rawValue, "leftControl", "rightControl", nil:
            return .control
        case Self.option.rawValue, "leftOption", "rightOption":
            return .option
        case Self.command.rawValue, "leftCommand", "rightCommand":
            return .command
        case Self.fn.rawValue:
            return .fn
        default:
            return .control
        }
    }
}

enum TTSProvider: String, CaseIterable, Identifiable {
    case apple = "apple"
    case youdao = "youdao"
    case bing = "bing"
    case google = "google"
    case baidu = "baidu"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple:
            return L("Apple")
        case .youdao:
            return L("Youdao")
        case .bing:
            return L("Bing")
        case .google:
            return L("Google")
        case .baidu:
            return L("Baidu")
        }
    }

    var requiresNetwork: Bool {
        self != .apple
    }

    var description: String {
        switch self {
        case .apple:
            return L("System built-in, works offline")
        case .youdao:
            return L("Clear word pronunciation")
        case .bing:
            return L("High quality neural voice")
        case .google:
            return L("Google Translate voice")
        case .baidu:
            return L("Natural pronunciation")
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return L("Follow System")
        case .english:
            return "English"
        case .chineseSimplified:
            return "简体中文"
        case .chineseTraditional:
            return "繁體中文"
        case .japanese:
            return "日本語"
        case .korean:
            return "한국어"
        case .spanish:
            return "Español"
        }
    }

    var localeIdentifier: String? {
        switch self {
        case .system:
            return nil
        default:
            return rawValue
        }
    }
}

enum AppSettingKey {
    static let playPronunciation = "playPronunciation"
    static let playWordPronunciation = "playWordPronunciation"
    static let playSentencePronunciation = "playSentencePronunciation"
    static let launchAtLogin = "launchAtLogin"
    static let singleKey = "singleKey"
    static let sourceLanguage = "sourceLanguage"
    static let targetLanguage = "targetLanguage"
    static let debugShowOcrRegion = "debugShowOcrRegion"
    static let continuousTranslation = "continuousTranslation"
    static let lastScreenRecordingStatus = "lastScreenRecordingStatus"
    static let ttsProvider = "ttsProvider"
    static let wordTTSProvider = "wordTTSProvider"
    static let sentenceTTSProvider = "sentenceTTSProvider"
    static let appLanguage = "appLanguage"
    static let englishAccent = "englishAccent"
    static let sentenceTranslationEnabled = "sentenceTranslationEnabled"
    static let autoCheckUpdates = "autoCheckUpdates"
    static let updateChannel = "updateChannel"
    static let debugShowChannelSelector = "debugShowChannelSelector"
    static let showMenuBarIcon = "showMenuBarIcon"
}

enum EnglishAccent: String, CaseIterable, Identifiable {
    case american = "en-US"
    case british = "en-GB"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .american:
            return L("American (US)")
        case .british:
            return L("British (UK)")
        }
    }
    
    var isAmerican: Bool {
        self == .american
    }
}

enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable
    case beta

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stable:
            return L("Stable")
        case .beta:
            return L("Beta")
        }
    }

    var description: String {
        switch self {
        case .stable:
            return L("Receive stable releases only")
        case .beta:
            return L("Receive beta releases for early access to new features")
        }
    }
}
