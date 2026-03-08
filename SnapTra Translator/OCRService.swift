import CoreText
import Foundation
import NaturalLanguage
import Vision

struct RecognizedWord: Equatable {
    var text: String
    var boundingBox: CGRect
}

final class OCRService {
    func recognizeWords(in image: CGImage, preferredLanguages: [String]) async throws -> [RecognizedWord] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if !preferredLanguages.isEmpty {
                request.recognitionLanguages = preferredLanguages
            }
            if #available(macOS 13.0, *) {
                request.revision = VNRecognizeTextRequestRevision3
                request.automaticallyDetectsLanguage = true
            }
            let handler = VNImageRequestHandler(cgImage: image)
            try handler.perform([request])
            guard let observations = request.results else {
                return []
            }
            return OCRService.extractWords(from: observations)
        }.value
    }

    nonisolated private static func extractWords(from observations: [VNRecognizedTextObservation]) -> [RecognizedWord] {
        #if DEBUG
        print("[OCR] ========== New OCR Result ==========")
        print("[OCR] Total observations: \(observations.count)")
        #endif

        var words: [RecognizedWord] = []
        for (obsIndex, observation) in observations.enumerated() {
            guard let candidate = observation.topCandidates(1).first else {
                continue
            }
            let text = candidate.string
            let textBoundingBox = observation.boundingBox
            let tokenRanges = tokenRanges(in: text)

            #if DEBUG
            print("[OCR] Observation \(obsIndex): '\(text)', tokenized into \(tokenRanges.count) parts")
            for (i, range) in tokenRanges.enumerated() {
                print("[OCR]   Token \(i): '\(text[range])'")
            }
            #endif

            for tokenRange in tokenRanges {
                for refinedRange in refinedTokenRanges(in: text[tokenRange]) {
                    let substring = text[refinedRange]
                    guard shouldKeepToken(substring) else {
                        continue
                    }

                    guard let boundingBox = boundingBox(
                        for: refinedRange,
                        in: text,
                        candidate: candidate,
                        observationBox: textBoundingBox
                    ) else {
                        continue
                    }

                    #if DEBUG
                    print("[OCR]   '\(substring)' box: x=\(String(format: "%.4f", boundingBox.minX)), w=\(String(format: "%.4f", boundingBox.width))")
                    #endif

                    words.append(RecognizedWord(text: String(substring), boundingBox: boundingBox))
                }
            }
        }
        return words
    }

    nonisolated private static let tokenCharacterSet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

    nonisolated private static func tokenRanges(in text: String) -> [Range<String.Index>] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var ranges: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            ranges.append(range)
            return true
        }

        return ranges
    }

    nonisolated private static func refinedTokenRanges(in token: Substring) -> [Range<String.Index>] {
        guard OCRTokenClassifier.classify(String(token)) == .english else {
            return [token.startIndex..<token.endIndex]
        }

        var ranges: [Range<String.Index>] = []
        let indices = Array(token.indices)
        var tokenStart: String.Index?
        var previousCharacter: Character?

        for (position, index) in indices.enumerated() {
            let currentCharacter = token[index]
            let nextCharacter = position + 1 < indices.count ? token[indices[position + 1]] : nil

            if isTokenCharacter(currentCharacter) {
                if tokenStart == nil {
                    tokenStart = index
                } else if let previousCharacter, shouldSplitCamelCase(previous: previousCharacter, current: currentCharacter, next: nextCharacter) {
                    if let start = tokenStart {
                        ranges.append(start..<index)
                    }
                    tokenStart = index
                }
                previousCharacter = currentCharacter
            } else {
                if let start = tokenStart {
                    ranges.append(start..<index)
                    tokenStart = nil
                }
                previousCharacter = nil
            }
        }

        if let start = tokenStart {
            ranges.append(start..<token.endIndex)
        }

        return ranges
    }

    nonisolated private static func boundingBox(
        for range: Range<String.Index>,
        in text: String,
        candidate: VNRecognizedText,
        observationBox: CGRect
    ) -> CGRect? {
        if let preciseBox = try? candidate.boundingBox(for: range)?.boundingBox,
           preciseBox.width > 0,
           preciseBox.height > 0,
           range == text.startIndex..<text.endIndex || !areBoundingBoxesSimilar(preciseBox, observationBox) {
            return preciseBox
        }

        if let approximateBox = boundingBoxByCharacterRatio(observationBox, text: text, for: range) {
            return approximateBox
        }

        return boundingBoxBySplittingWithCoreText(observationBox, text: text, for: range)
    }

    // 使用简单的字符比例计算边界框（最稳定的方法）
    nonisolated private static func boundingBoxByCharacterRatio(_ textBox: CGRect, text: String, for range: Range<String.Index>) -> CGRect? {
        let totalCount = text.count
        guard totalCount > 0 else { return nil }
        guard range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex else { return nil }

        let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)
        let endOffset = text.distance(from: text.startIndex, to: range.upperBound)

        guard endOffset > startOffset else { return nil }

        let startFraction = CGFloat(startOffset) / CGFloat(totalCount)
        let endFraction = CGFloat(endOffset) / CGFloat(totalCount)

        let x = textBox.minX + textBox.width * startFraction
        let width = textBox.width * (endFraction - startFraction)

        guard width > 0 else { return nil }

        return CGRect(x: x, y: textBox.minY, width: width, height: textBox.height)
    }

    // 使用 Core Text 测量实际字符宽度来计算边界框（备用方法）
    nonisolated private static func boundingBoxBySplittingWithCoreText(_ textBox: CGRect, text: String, for range: Range<String.Index>) -> CGRect? {
        guard range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex else {
            return nil
        }

        // 使用系统字体来估算字符宽度
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let attributes: [CFString: Any] = [kCTFontAttributeName: font]

        // 计算整个字符串的宽度
        let fullAttrString = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
        let fullLine = CTLineCreateWithAttributedString(fullAttrString)
        let fullWidth = CTLineGetTypographicBounds(fullLine, nil, nil, nil)

        guard fullWidth > 0 else { return nil }

        // 计算前缀字符串的宽度
        let prefixRange = text.startIndex..<range.lowerBound
        let prefixString = String(text[prefixRange])
        var prefixWidth: Double = 0
        if !prefixString.isEmpty {
            let prefixAttrString = CFAttributedStringCreate(nil, prefixString as CFString, attributes as CFDictionary)!
            let prefixLine = CTLineCreateWithAttributedString(prefixAttrString)
            prefixWidth = CTLineGetTypographicBounds(prefixLine, nil, nil, nil)
        }

        // 计算目标子串的宽度
        let substring = String(text[range])
        let subAttrString = CFAttributedStringCreate(nil, substring as CFString, attributes as CFDictionary)!
        let subLine = CTLineCreateWithAttributedString(subAttrString)
        let subWidth = CTLineGetTypographicBounds(subLine, nil, nil, nil)

        guard subWidth > 0 else { return nil }

        let startFraction = CGFloat(prefixWidth / fullWidth)
        let widthFraction = CGFloat(subWidth / fullWidth)

        let x = textBox.minX + textBox.width * startFraction
        let width = textBox.width * widthFraction

        return CGRect(x: x, y: textBox.minY, width: width, height: textBox.height)
    }

    // 检查两个边界框是否相似（用于判断 Vision 是否返回了精确的子范围边界框）
    nonisolated private static func areBoundingBoxesSimilar(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 0.02) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance
            && abs(lhs.origin.y - rhs.origin.y) <= tolerance
            && abs(lhs.size.width - rhs.size.width) <= tolerance
            && abs(lhs.size.height - rhs.size.height) <= tolerance
    }

    nonisolated private static func isTokenCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { tokenCharacterSet.contains($0) }
    }


    nonisolated private static func shouldSplitCamelCase(previous: Character, current: Character, next: Character?) -> Bool {
        let previousIsLowercase = isLowercaseLetter(previous)
        let previousIsUppercase = isUppercaseLetter(previous)
        let currentIsUppercase = isUppercaseLetter(current)
        let nextIsLowercase = next.map(isLowercaseLetter) ?? false

        if previousIsLowercase && currentIsUppercase {
            return true
        }

        if previousIsUppercase && currentIsUppercase && nextIsLowercase {
            return true
        }

        return false
    }

    nonisolated private static func isUppercaseLetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.uppercaseLetters.contains($0) }
    }

    nonisolated private static func isLowercaseLetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.lowercaseLetters.contains($0) }
    }

    nonisolated private static func shouldKeepToken(_ token: Substring) -> Bool {
        OCRTokenClassifier.classify(String(token)) != .unknown
    }
}
