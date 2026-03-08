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
    
    private func analyzeAudioData(_ data: Data, provider: TTSProvider) {
        guard data.count >= 4 else {
            logger.error("❌ Audio data too small: \(data.count) bytes")
            return
        }
        
        let header = data.prefix(4)
        let hexString = header.map { String(format: "%02x", $0) }.joined(separator: " ")
        logger.info("🔍 Audio header (hex): \(hexString)")
        
        // Check for MP3
        if header[0] == 0xFF && (header[1] & 0xE0) == 0xE0 {
            logger.info("✅ Detected MP3 format (MPEG audio)")
        } else if header.starts(with: [0x49, 0x44, 0x33]) {
            logger.info("✅ Detected MP3 format with ID3 tag")
        } else if header.starts(with: [0x52, 0x49, 0x46, 0x46]) {
            logger.info("✅ Detected WAV format (RIFF)")
        } else if header.starts(with: [0x4F, 0x67, 0x67, 0x53]) {
            logger.info("✅ Detected OGG format")
        } else {
            logger.warning("⚠️ Unknown audio format")
        }
        
        // Check if data is valid
        if data.count < 100 {
            logger.warning("⚠️ Audio data suspiciously small: \(data.count) bytes")
        }
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
            
            // Debug: Save audio to file for inspection
            #if DEBUG
            let debugURL = FileManager.default.temporaryDirectory.appendingPathComponent("tts_\(provider.rawValue).mp3")
            try? audioData.write(to: debugURL)
            logger.debug("💾 Debug: Audio saved to \(debugURL.path)")
            #endif
            
            try await MainActor.run {
                // Analyze audio data
                self.analyzeAudioData(audioData, provider: provider)
                
                do {
                    audioPlayer = try AVAudioPlayer(data: audioData)
                    audioPlayer?.prepareToPlay()
                    
                    // Log audio player details
                    if let player = audioPlayer {
                        logger.info("🔊 Audio format: \(player.format)")
                        logger.info("⏱️ Duration: \(player.duration) seconds")
                        logger.info("🔢 Number of channels: \(player.numberOfChannels)")
                    }
                    
                    let success = audioPlayer?.play() ?? false
                    if success {
                        logger.info("▶️ Started playing audio")
                    } else {
                        logger.error("❌ AVAudioPlayer.play() returned false")
                        logger.error("📊 Audio data size: \(audioData.count) bytes")
                        self.speakWithApple(text, language: language)
                    }
                } catch {
                    logger.error("❌ Failed to create AVAudioPlayer: \(error)")
                    logger.error("📊 Audio data size: \(audioData.count) bytes")
                    logger.error("📄 First 20 bytes: \(audioData.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " "))")
                    self.speakWithApple(text, language: language)
                }
            }
        } catch {
            logger.error("❌ TTS error: \(error)")
            logger.error("❌ Error details: \(error.localizedDescription)")
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

enum TTSError: Error, LocalizedError {
    case unsupportedProvider
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case audioDecodeError
    case tokenExpired
    case tokenExtractionFailed(String)
    case webSocketError(String)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "Unsupported TTS provider"
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .audioDecodeError:
            return "Failed to decode audio data"
        case .tokenExpired:
            return "Token expired"
        case .tokenExtractionFailed(let msg):
            return "Token extraction failed: \(msg)"
        case .webSocketError(let msg):
            return "WebSocket error: \(msg)"
        }
    }
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
        logger.info("📦 Data size: \(data.count) bytes")
        
        guard httpResponse.statusCode == 200 else {
            logger.error("❌ HTTP error: \(httpResponse.statusCode)")
            throw TTSError.invalidResponse
        }
        
        // Verify it's MP3 data
        if data.count > 2 {
            let header = data.prefix(2)
            if header[0] == 0xFF && (header[1] & 0xE0) == 0xE0 {
                logger.info("✅ Valid MP3 header detected")
            } else {
                logger.warning("⚠️ Data does not start with MP3 header")
            }
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
        logger.info("📦 Data size: \(data.count) bytes")
        
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

// MARK: - Edge TTS Service
//
// Uses NWConnection with raw TLS (no WebSocket protocol layer) so that system
// proxies handle the connection as ordinary HTTPS via CONNECT tunnel.
// The WebSocket upgrade and framing are implemented manually inside the
// encrypted tunnel, giving full control over HTTP headers (Origin, User-Agent)
// that Microsoft requires while remaining invisible to the proxy.

final class EdgeTTSService {
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "EdgeTTS")
    private let trustedClientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    private let queue = DispatchQueue(label: "com.yelog.SnapTra-Translator.edge-tts")

    /// Scratch buffer for TCP stream → WebSocket frame reassembly.
    private var rxBuffer = Data()

    func fetchAudio(text: String, language: String?) async throws -> Data {
        logger.info("🌐 Starting Edge TTS (raw TLS + manual WS)...")
        rxBuffer = Data()

        let connectionId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let path = "/consumer/speech/synthesize/readaloud/edge/v1"
            + "?TrustedClientToken=\(trustedClientToken)"
            + "&Retry-After=3600"
            + "&ConnectionId=\(connectionId)"

        // Raw TLS — no NWProtocolWebSocket.  Proxies handle this as regular
        // HTTPS via CONNECT tunnel; the WebSocket upgrade happens inside the
        // encrypted tunnel where the proxy cannot see or interfere.
        let connection = NWConnection(
            host: "speech.platform.bing.com",
            port: 443,
            using: .tls
        )

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                defer { connection.cancel() }

                try await self.waitForReady(connection)
                self.logger.debug("✅ TLS connected")

                try await self.performWebSocketHandshake(
                    connection, path: path, connectionId: connectionId
                )
                self.logger.debug("✅ WebSocket upgraded")

                try await self.sendTextFrame(connection, self.createConfigMessage())
                self.logger.debug("📤 Config sent")

                let voiceName = self.getVoiceName(language: language)
                let ssml = self.generateSSML(text: text, voiceName: voiceName)
                try await self.sendTextFrame(connection, self.createSSMLMessage(ssml: ssml))
                self.logger.debug("📤 SSML sent")

                self.logger.info("⏳ Receiving audio frames...")
                return try await self.receiveAudio(connection)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                self.logger.error("⏰ Edge TTS timed out after 30s")
                throw TTSError.networkError(URLError(.timedOut))
            }

            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw TTSError.invalidResponse
            }
            return result
        }
    }

    // MARK: - Connection Lifecycle

    private func waitForReady(_ conn: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    conn.stateUpdateHandler = nil
                    cont.resume()
                case .failed(let error):
                    self?.logger.error("❌ Connection failed: \(error)")
                    conn.stateUpdateHandler = nil
                    cont.resume(throwing: error)
                case .waiting(let error):
                    self?.logger.error("❌ Connection waiting: \(error)")
                    conn.stateUpdateHandler = nil
                    cont.resume(throwing: error)
                case .cancelled:
                    conn.stateUpdateHandler = nil
                    cont.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            conn.start(queue: self.queue)
        }
    }

    // MARK: - Manual WebSocket Handshake

    private func performWebSocketHandshake(
        _ conn: NWConnection,
        path: String,
        connectionId: String
    ) async throws {
        let wsKey = generateWebSocketKey()
        let upgrade = "GET \(path) HTTP/1.1\r\n"
            + "Host: speech.platform.bing.com\r\n"
            + "Upgrade: websocket\r\n"
            + "Connection: Upgrade\r\n"
            + "Sec-WebSocket-Key: \(wsKey)\r\n"
            + "Sec-WebSocket-Version: 13\r\n"
            + "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
            + " (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36 Edg/134.0.0.0\r\n"
            + "Origin: chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold\r\n"
            + "Pragma: no-cache\r\n"
            + "Cache-Control: no-cache\r\n"
            + "Accept-Language: en-US,en;q=0.9\r\n"
            + "X-ConnectionId: \(connectionId)\r\n"
            + "\r\n"

        try await sendRaw(conn, upgrade.data(using: .utf8)!)

        // Read until end of HTTP headers
        let terminator = Data([0x0D, 0x0A, 0x0D, 0x0A])
        while rxBuffer.range(of: terminator) == nil {
            let chunk = try await recvRaw(conn, max: 4096)
            rxBuffer.append(chunk)
            guard rxBuffer.count < 16384 else {
                throw TTSError.webSocketError("Handshake response too large")
            }
        }

        let range = rxBuffer.range(of: terminator)!
        let headersData = rxBuffer[..<range.upperBound]
        rxBuffer.removeSubrange(..<range.upperBound)

        let headers = String(data: headersData, encoding: .utf8) ?? ""
        logger.debug("📨 Upgrade response: \(headers.prefix(200))")

        guard headers.contains("101") else {
            throw TTSError.webSocketError("WebSocket upgrade rejected: \(headers.prefix(120))")
        }
    }

    private func generateWebSocketKey() -> String {
        Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
    }

    // MARK: - Raw I/O

    private func sendRaw(_ conn: NWConnection, _ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    private func recvRaw(_ conn: NWConnection, max: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            conn.receive(minimumIncompleteLength: 1, maximumLength: max) { data, _, _, error in
                if let error { cont.resume(throwing: error); return }
                guard let data, !data.isEmpty else {
                    cont.resume(throwing: TTSError.webSocketError("Connection closed"))
                    return
                }
                cont.resume(returning: data)
            }
        }
    }

    /// Read exactly `n` bytes, pulling from rxBuffer first.
    private func readExact(_ conn: NWConnection, _ n: Int) async throws -> Data {
        while rxBuffer.count < n {
            let chunk = try await recvRaw(conn, max: max(n - rxBuffer.count, 4096))
            rxBuffer.append(chunk)
        }
        let result = Data(rxBuffer.prefix(n))
        rxBuffer.removeFirst(n)
        return result
    }

    // MARK: - WebSocket Framing (RFC 6455)

    /// Build a masked client→server WebSocket frame.
    private func buildFrame(opcode: UInt8, payload: Data) -> Data {
        var f = Data()
        f.append(0x80 | opcode)

        let len = payload.count
        if len < 126 {
            f.append(UInt8(len) | 0x80)
        } else if len < 65536 {
            f.append(126 | 0x80)
            f.append(UInt8((len >> 8) & 0xFF))
            f.append(UInt8(len & 0xFF))
        } else {
            f.append(127 | 0x80)
            for i in (0..<8).reversed() { f.append(UInt8((len >> (i * 8)) & 0xFF)) }
        }

        let mask: [UInt8] = (0..<4).map { _ in UInt8.random(in: 0...255) }
        f.append(contentsOf: mask)
        for (i, b) in payload.enumerated() { f.append(b ^ mask[i % 4]) }
        return f
    }

    private func sendTextFrame(_ conn: NWConnection, _ text: String) async throws {
        try await sendRaw(conn, buildFrame(opcode: 0x01, payload: text.data(using: .utf8)!))
    }

    /// Read one WebSocket frame → (opcode, payload). Auto-replies to pings.
    private func readFrame(_ conn: NWConnection) async throws -> (UInt8, Data) {
        let hdr = try await readExact(conn, 2)
        let opcode = hdr[0] & 0x0F
        let masked = (hdr[1] & 0x80) != 0
        var len = UInt64(hdr[1] & 0x7F)

        if len == 126 {
            let ext = try await readExact(conn, 2)
            len = UInt64(ext[0]) << 8 | UInt64(ext[1])
        } else if len == 127 {
            let ext = try await readExact(conn, 8)
            len = 0; for b in ext { len = len << 8 | UInt64(b) }
        }
        guard len < 20_000_000 else {
            throw TTSError.webSocketError("Frame too large: \(len)")
        }

        var maskKey: [UInt8]?
        if masked { maskKey = Array(try await readExact(conn, 4)) }

        var payload = len > 0 ? try await readExact(conn, Int(len)) : Data()
        if let key = maskKey {
            for i in 0..<payload.count { payload[i] ^= key[i % 4] }
        }

        if opcode == 0x09 { // Ping → Pong
            try await sendRaw(conn, buildFrame(opcode: 0x0A, payload: payload))
            return try await readFrame(conn)
        }
        return (opcode, payload)
    }

    // MARK: - Audio Reception

    private func receiveAudio(_ conn: NWConnection) async throws -> Data {
        var audioData = Data()
        var msgCount = 0

        receiveLoop: while true {
            let (opcode, payload) = try await readFrame(conn)
            msgCount += 1

            switch opcode {
            case 0x02: // binary
                guard payload.count >= 2 else { continue receiveLoop }
                let hdrLen = (Int(payload[0]) << 8) | Int(payload[1])
                let hdrEnd = 2 + hdrLen
                guard hdrEnd <= payload.count,
                      let hdr = String(data: payload[2..<hdrEnd], encoding: .utf8)
                else { continue receiveLoop }

                if hdr.contains("Path:audio"), hdrEnd < payload.count {
                    audioData.append(contentsOf: payload[hdrEnd...])
                    logger.debug("🎵 chunk \(payload.count - hdrEnd)B  total \(audioData.count)B")
                } else if hdr.contains("Path:turn.end") {
                    logger.info("✅ turn.end after \(msgCount) msgs")
                    break receiveLoop
                }

                if audioData.count > 10_000_000 {
                    logger.warning("⚠️ >10 MB, stopping")
                    break receiveLoop
                }

            case 0x01: // text
                let text = String(data: payload, encoding: .utf8) ?? ""
                logger.debug("📨 text \(msgCount): \(text.prefix(80))")
                if text.contains("Path:turn.end") {
                    logger.info("✅ turn.end (text) after \(msgCount) msgs")
                    break receiveLoop
                }

            case 0x08: // close
                logger.info("🔒 Server close frame")
                break receiveLoop

            default:
                break
            }
        }

        logger.info("📊 total audio: \(audioData.count) bytes")
        guard !audioData.isEmpty else {
            logger.error("❌ No audio received")
            throw TTSError.invalidResponse
        }
        return audioData
    }

    // MARK: - Protocol Message Builders

    private func createConfigMessage() -> String {
        let config: [String: Any] = [
            "context": [
                "synthesis": [
                    "audio": [
                        "metadataoptions": [
                            "sentenceBoundaryEnabled": "false",
                            "wordBoundaryEnabled": "false",
                        ],
                        "outputFormat": "audio-24khz-48kbitrate-mono-mp3",
                    ],
                ],
            ],
        ]
        let json = String(data: try! JSONSerialization.data(withJSONObject: config), encoding: .utf8)!
        return "X-Timestamp:\(getTimestamp())\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n\(json)"
    }

    private func createSSMLMessage(ssml: String) -> String {
        let requestId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return "X-Timestamp:\(getTimestamp())\r\nContent-Type:application/ssml+xml\r\nX-RequestId:\(requestId)\r\nPath:ssml\r\n\r\n\(ssml)"
    }

    private func generateSSML(text: String, voiceName: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>"
            + "<voice name='\(voiceName)'>"
            + "<prosody pitch='+0Hz' rate='+0%' volume='+0%'>\(escaped)</prosody>"
            + "</voice></speak>"
    }

    private func getVoiceName(language: String?) -> String {
        let voiceMap: [String: String] = [
            "en":      "en-US-AriaNeural",
            "zh":      "zh-CN-XiaoxiaoNeural",
            "zh-Hans": "zh-CN-XiaoxiaoNeural",
            "zh-Hant": "zh-TW-HsiaoChenNeural",
            "ja":      "ja-JP-NanamiNeural",
            "ko":      "ko-KR-SunHiNeural",
            "fr":      "fr-FR-DeniseNeural",
            "de":      "de-DE-KatjaNeural",
            "es":      "es-ES-ElviraNeural",
            "it":      "it-IT-ElsaNeural",
            "pt":      "pt-BR-FranciscaNeural",
            "ru":      "ru-RU-SvetlanaNeural",
        ]
        return voiceMap[language ?? "en"] ?? "en-US-AriaNeural"
    }

    private func getTimestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }
}

// MARK: - Bing TTS Service (Redirects to Edge)

final class BingTTSService {
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "BingTTS")
    
    func fetchAudio(
        text: String,
        language: String?
    ) async throws -> Data {
        logger.info("🔄 Bing TTS using Edge TTS backend")
        let edgeService = EdgeTTSService()
        return try await edgeService.fetchAudio(text: text, language: language)
    }
}

// MARK: - Google TTS Service

final class GoogleTTSService {
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "GoogleTTS")

    func fetchAudio(
        text: String,
        language: String?
    ) async throws -> Data {
        logger.info("📡 Requesting Google TTS...")

        // Google TTS has 100 character limit per request
        let trimmedText = String(text.prefix(100))
        let langCode = googleLanguageCode(for: language)
        let encodedText = trimmedText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        // Use the translate_tts endpoint which directly returns MP3 audio.
        // The previous RPC batchexecute approach embedded audio as base64 inside
        // an escaped JSON string, and the regex failed to match the \" delimiters.
        guard let url = URL(string: "https://translate.google.com/translate_tts?ie=UTF-8&q=\(encodedText)&tl=\(langCode)&client=tw-ob") else {
            throw TTSError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://translate.google.com/", forHTTPHeaderField: "Referer")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSError.invalidResponse
        }

        logger.info("📊 HTTP Status: \(httpResponse.statusCode), size: \(data.count) bytes")

        guard httpResponse.statusCode == 200, data.count > 100 else {
            logger.error("❌ HTTP error or empty response: \(httpResponse.statusCode)")
            throw TTSError.invalidResponse
        }

        return data
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
