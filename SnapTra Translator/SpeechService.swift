import AVFoundation
import Foundation
import Network
import os.log

@MainActor
final class SpeechService {
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private let ttsServiceFactory = TTSServiceFactory()
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "SpeechService")
    
    func speak(
        _ text: String,
        language: String?,
        provider: TTSProvider = .apple,
        useAmericanAccent: Bool = true
    ) {
        logger.info("🔊 Speaking with provider: \(provider.rawValue), text: \(text)")
        
        // Stop current playback
        stopSpeaking()
        
        switch provider {
        case .apple:
            logger.info("🎵 Using Apple System Voice")
            speakWithApple(text, language: language)
        case .youdao, .bing, .google, .baidu, .edge:
            logger.info("🌐 Using online TTS: \(provider.displayName)")
            Task {
                await speakWithOnlineService(
                    text,
                    language: language,
                    provider: provider,
                    useAmericanAccent: useAmericanAccent
                )
            }
        }
    }
    
    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        audioPlayer?.stop()
        audioPlayer = nil
    }
    
    private func speakWithApple(_ text: String, language: String?) {
        let utterance = AVSpeechUtterance(string: text)
        if let language {
            utterance.voice = AVSpeechSynthesisVoice(language: language)
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
    
    private func speakWithOnlineService(
        _ text: String,
        language: String?,
        provider: TTSProvider,
        useAmericanAccent: Bool
    ) async {
        do {
            logger.info("📡 Fetching audio from \(provider.displayName)...")
            let audioData = try await ttsServiceFactory.fetchAudio(
                text: text,
                language: language,
                provider: provider,
                useAmericanAccent: useAmericanAccent
            )
            
            logger.info("✅ Successfully fetched \(audioData.count) bytes from \(provider.displayName)")
            
            try await MainActor.run {
                audioPlayer = try AVAudioPlayer(data: audioData)
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
                logger.info("▶️ Started playing audio")
            }
        } catch {
            logger.error("❌ TTS error: \(error.localizedDescription)")
            logger.info("🔄 Falling back to Apple System Voice")
            // Fallback to Apple TTS
            speakWithApple(text, language: language)
        }
    }
}

// MARK: - TTS Service Factory

@MainActor
final class TTSServiceFactory {
    private let youdaoService = YoudaoTTSService()
    private let bingService = BingTTSService()
    private let edgeService = EdgeTTSService()
    private let googleService = GoogleTTSService()
    private let baiduService = BaiduTTSService()
    
    func fetchAudio(
        text: String,
        language: String?,
        provider: TTSProvider,
        useAmericanAccent: Bool
    ) async throws -> Data {
        switch provider {
        case .youdao:
            return try await youdaoService.fetchAudio(
                text: text,
                language: language,
                useAmericanAccent: useAmericanAccent
            )
        case .bing:
            return try await bingService.fetchAudio(
                text: text,
                language: language
            )
        case .edge:
            return try await edgeService.fetchAudio(
                text: text,
                language: language
            )
        case .google:
            return try await googleService.fetchAudio(
                text: text,
                language: language
            )
        case .baidu:
            return try await baiduService.fetchAudio(
                text: text,
                language: language,
                useAmericanAccent: useAmericanAccent
            )
        case .apple:
            throw TTSError.unsupportedProvider
        }
    }
}

enum TTSError: Error {
    case unsupportedProvider
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case audioDecodeError
    case tokenExpired
    case tokenExtractionFailed(String)
    case webSocketError(String)
}

// MARK: - Youdao TTS Service

final class YoudaoTTSService {
    private let baseURL = "https://dict.youdao.com/dictvoice"
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "YoudaoTTS")
    
    func fetchAudio(
        text: String,
        language: String?,
        useAmericanAccent: Bool
    ) async throws -> Data {
        let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let langCode = languageCode(for: language)
        let accentType = useAmericanAccent ? "2" : "1"
        
        guard let url = URL(string: "\(baseURL)?audio=\(encodedText)&le=\(langCode)&type=\(accentType)") else {
            logger.error("❌ Invalid URL")
            throw TTSError.invalidURL
        }
        
        logger.info("📡 Requesting Youdao TTS: \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("❌ Invalid response type")
            throw TTSError.invalidResponse
        }
        
        logger.info("📊 HTTP Status: \(httpResponse.statusCode), Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
        
        guard httpResponse.statusCode == 200 else {
            logger.error("❌ HTTP error: \(httpResponse.statusCode)")
            throw TTSError.invalidResponse
        }
        
        return data
    }
    
    private func languageCode(for language: String?) -> String {
        guard let language = language else { return "en" }
        
        let languageMap: [String: String] = [
            "en": "en",
            "zh": "zh",
            "zh-Hans": "zh",
            "zh-Hant": "zh",
            "ja": "ja",
            "ko": "ko",
            "fr": "fr",
            "de": "de",
            "es": "es",
            "ru": "ru",
        ]
        
        return languageMap[language] ?? "en"
    }
}

// MARK: - Baidu TTS Service

final class BaiduTTSService {
    private let baseURL = "https://fanyi.baidu.com/gettts"
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "BaiduTTS")
    
    func fetchAudio(
        text: String,
        language: String?,
        useAmericanAccent: Bool
    ) async throws -> Data {
        // Baidu has 1000 character limit
        let trimmedText = String(text.prefix(1000))
        let encodedText = trimmedText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        var langCode = languageCode(for: language)
        
        // Handle UK accent
        if langCode == "en" && !useAmericanAccent {
            langCode = "uk"
        }
        
        let speed = (langCode == "zh") ? "5" : "3"
        
        guard let url = URL(string: "\(baseURL)?text=\(encodedText)&lan=\(langCode)&spd=\(speed)&source=web") else {
            logger.error("❌ Invalid URL")
            throw TTSError.invalidURL
        }
        
        logger.info("📡 Requesting Baidu TTS: \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("❌ Invalid response type")
            throw TTSError.invalidResponse
        }
        
        logger.info("📊 HTTP Status: \(httpResponse.statusCode), Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
        
        guard httpResponse.statusCode == 200 else {
            logger.error("❌ HTTP error: \(httpResponse.statusCode)")
            throw TTSError.invalidResponse
        }
        
        return data
    }
    
    private func languageCode(for language: String?) -> String {
        guard let language = language else { return "en" }
        
        let languageMap: [String: String] = [
            "en": "en",
            "zh": "zh",
            "zh-Hans": "zh",
            "zh-Hant": "zh",
            "ja": "jp",
            "ko": "kor",
            "fr": "fra",
            "de": "de",
            "es": "spa",
            "ru": "ru",
            "yue": "yue",
            "th": "th",
            "ar": "ara",
            "pt": "pt",
            "it": "it",
            "nl": "nl",
            "el": "el",
        ]
        
        return languageMap[language] ?? "en"
    }
}

// MARK: - Edge TTS Service (WebSocket)

final class EdgeTTSService {
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "EdgeTTS")
    private let trustedClientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    private let chromiumVersion = "120.0.0.0"
    
    func fetchAudio(
        text: String,
        language: String?
    ) async throws -> Data {
        logger.info("🌐 Starting Edge TTS WebSocket connection...")
        
        // Build WebSocket URL
        let wsURL = "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=\(trustedClientToken)"
        
        guard let url = URL(string: wsURL) else {
            throw TTSError.invalidURL
        }
        
        // Create WebSocket task
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(chromiumVersion) Safari/537.36 Edg/\(chromiumVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        
        let webSocketTask = URLSession.shared.webSocketTask(with: request)
        
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    var audioData = Data()
                    let voiceName = self.getVoiceName(language: language)
                    let ssml = self.generateSSML(text: text, voiceName: voiceName)
                    
                    // Start WebSocket
                    webSocketTask.resume()
                    
                    // Wait for connection
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                    
                    // Send config message
                    let configMessage = URLSessionWebSocketTask.Message.string(
                        "X-Timestamp:\(self.getTimestamp())\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n{\"context\":[{\"synthesis\":{\"audio\":{\"metadataoptions\":{\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"true\"},\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}]}"
                    )
                    try await webSocketTask.send(configMessage)
                    
                    // Send SSML message
                    let ssmlMessage = URLSessionWebSocketTask.Message.string(
                        "X-Timestamp:\(self.getTimestamp())\r\nContent-Type:application/ssml+xml\r\nPath:ssml\r\n\r\n\(ssml)"
                    )
                    try await webSocketTask.send(ssmlMessage)
                    
                    // Receive audio data
                    var isComplete = false
                    while !isComplete {
                        let message = try await webSocketTask.receive()
                        
                        switch message {
                        case .data(let data):
                            // Check if it's the end marker
                            if data.count < 100 {
                                if let text = String(data: data, encoding: .utf8),
                                   text.contains("Path:turn.end") {
                                    isComplete = true
                                    break
                                }
                            }
                            audioData.append(data)
                            
                        case .string(let text):
                            if text.contains("Path:turn.end") || text.contains("Path:response") {
                                isComplete = true
                            }
                            
                        @unknown default:
                            break
                        }
                        
                        // Timeout check
                        if audioData.count > 10_000_000 { // 10MB limit
                            isComplete = true
                        }
                    }
                    
                    webSocketTask.cancel(with: .normalClosure, reason: nil)
                    
                    if audioData.count > 0 {
                        logger.info("✅ Edge TTS: Received \(audioData.count) bytes of audio")
                        continuation.resume(returning: audioData)
                    } else {
                        throw TTSError.invalidResponse
                    }
                    
                } catch {
                    webSocketTask.cancel(with: .normalClosure, reason: nil)
                    logger.error("❌ Edge TTS error: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func generateSSML(text: String, voiceName: String) -> String {
        let escapedText = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        
        return """
        <speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>
            <voice name='\(voiceName)'>
                <prosody pitch='+0Hz' rate='+0%' volume='+0%'>
                    \(escapedText)
                </prosody>
            </voice>
        </speak>
        """
    }
    
    private func getVoiceName(language: String?) -> String {
        let langCode = language ?? "en"
        
        let voiceMap: [String: String] = [
            "en": "en-US-AriaNeural",
            "zh": "zh-CN-XiaoxiaoNeural",
            "zh-Hans": "zh-CN-XiaoxiaoNeural",
            "zh-Hant": "zh-TW-HsiaoChenNeural",
            "ja": "ja-JP-NanamiNeural",
            "ko": "ko-KR-SunHiNeural",
            "fr": "fr-FR-DeniseNeural",
            "de": "de-DE-KatjaNeural",
            "es": "es-ES-ElviraNeural",
            "it": "it-IT-ElsaNeural",
            "pt": "pt-BR-FranciscaNeural",
            "ru": "ru-RU-SvetlanaNeural",
        ]
        
        return voiceMap[langCode] ?? "en-US-AriaNeural"
    }
    
    private func getTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

// MARK: - Bing TTS Service (Deprecated, redirects to Edge)

final class BingTTSService {
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "BingTTS")
    
    func fetchAudio(
        text: String,
        language: String?
    ) async throws -> Data {
        logger.warning("⚠️ Bing TTS is deprecated, redirecting to Edge TTS")
        // Use Edge TTS instead
        let edgeService = EdgeTTSService()
        return try await edgeService.fetchAudio(text: text, language: language)
    }
}

// MARK: - Google TTS Service (New RPC API)

final class GoogleTTSService {
    private let baseURL = "https://translate.google.com/_/TranslateWebserverUi/data/batchexecute"
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "GoogleTTS")
    
    func fetchAudio(
        text: String,
        language: String?
    ) async throws -> Data {
        logger.info("📡 Requesting Google TTS (RPC API)...")
        
        // Google TTS has 100 character limit per request
        let trimmedText = String(text.prefix(100))
        let langCode = googleLanguageCode(for: language)
        
        // Build RPC request
        let parameter: [Any] = [trimmedText, langCode, NSNull(), "null"]
        let escapedParameter = try JSONSerialization.data(withJSONObject: parameter)
        guard let paramString = String(data: escapedParameter, encoding: .utf8) else {
            throw TTSError.invalidResponse
        }
        
        let rpc: [[[Any]]] = [[["jQ1olc", paramString, NSNull(), "generic"]]]
        let escapedRpc = try JSONSerialization.data(withJSONObject: rpc)
        guard let rpcString = String(data: escapedRpc, encoding: .utf8) else {
            throw TTSError.invalidResponse
        }
        
        let encodedRpc = rpcString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let body = "f.req=\(encodedRpc)"
        
        guard let url = URL(string: baseURL) else {
            throw TTSError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded;charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("https://translate.google.com/", forHTTPHeaderField: "Referer")
        request.httpBody = body.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSError.invalidResponse
        }
        
        logger.info("📊 HTTP Status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            logger.error("❌ HTTP error: \(httpResponse.statusCode)")
            throw TTSError.invalidResponse
        }
        
        // Parse response to extract audio
        guard let responseString = String(data: data, encoding: .utf8) else {
            throw TTSError.invalidResponse
        }
        
        // Extract audio from response
        return try extractAudio(from: responseString)
    }
    
    private func extractAudio(from response: String) throws -> Data {
        // Look for jQ1olc in response
        let pattern = #"jQ1olc","\["([^"]+)"\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: response, options: [], range: NSRange(location: 0, length: response.utf16.count)),
              let range = Range(match.range(at: 1), in: response) else {
            logger.error("❌ Could not find audio data in response")
            throw TTSError.audioDecodeError
        }
        
        let base64Audio = String(response[range])
        
        // Decode base64
        guard let audioData = Data(base64Encoded: base64Audio) else {
            logger.error("❌ Could not decode base64 audio")
            throw TTSError.audioDecodeError
        }
        
        logger.info("✅ Successfully decoded \(audioData.count) bytes of audio")
        return audioData
    }
    
    private func googleLanguageCode(for language: String?) -> String {
        guard let language = language else { return "en" }
        
        let languageMap: [String: String] = [
            "en": "en",
            "zh": "zh-CN",
            "zh-Hans": "zh-CN",
            "zh-Hant": "zh-TW",
            "ja": "ja",
            "ko": "ko",
            "fr": "fr",
            "de": "de",
            "es": "es",
            "ru": "ru",
            "it": "it",
            "pt": "pt",
        ]
        
        return languageMap[language] ?? "en"
    }
}
