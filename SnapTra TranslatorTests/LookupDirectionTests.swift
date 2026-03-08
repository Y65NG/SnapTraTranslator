import XCTest
@testable import SnapTra_Translator

final class OCRTokenClassifierTests: XCTestCase {
    func testClassifiesEnglishToken() {
        let result = OCRTokenClassifier.classify("hello")
        XCTAssertEqual(result, .english)
    }

    func testClassifiesChineseToken() {
        let result = OCRTokenClassifier.classify("你好")
        XCTAssertEqual(result, .chinese)
    }

    func testClassifiesNumericTokenAsUnknown() {
        let result = OCRTokenClassifier.classify("2026")
        XCTAssertEqual(result, .unknown)
    }

    func testClassifiesMixedToken() {
        let result = OCRTokenClassifier.classify("hello你好")
        XCTAssertEqual(result, .mixed)
    }
}
