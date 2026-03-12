import XCTest
@testable import SnapTra_Translator

final class OCRParagraphGroupingTests: XCTestCase {
    func testGroupsAlignedEnglishLinesIntoSingleParagraph() {
        let lines = [
            RecognizedTextLine(
                text: "This is the first line of a paragraph.",
                boundingBox: CGRect(x: 0.10, y: 0.72, width: 0.46, height: 0.05)
            ),
            RecognizedTextLine(
                text: "This is the second line of the paragraph.",
                boundingBox: CGRect(x: 0.10, y: 0.64, width: 0.48, height: 0.05)
            ),
        ]

        let paragraphs = OCRService.groupParagraphs(from: lines)

        XCTAssertEqual(paragraphs.count, 1)
        XCTAssertEqual(
            paragraphs.first?.text,
            "This is the first line of a paragraph.\nThis is the second line of the paragraph."
        )
    }

    func testSelectsParagraphContainingPointerBeforeNearbyParagraph() {
        let paragraphs = [
            RecognizedParagraph(
                text: "First paragraph line one\nFirst paragraph line two",
                lines: [],
                boundingBox: CGRect(x: 0.10, y: 0.60, width: 0.40, height: 0.14)
            ),
            RecognizedParagraph(
                text: "Second paragraph line one\nSecond paragraph line two",
                lines: [],
                boundingBox: CGRect(x: 0.58, y: 0.58, width: 0.28, height: 0.12)
            ),
        ]

        let selected = OCRService.selectParagraph(
            from: paragraphs,
            normalizedPoint: CGPoint(x: 0.22, y: 0.66)
        )

        XCTAssertEqual(selected?.text, paragraphs[0].text)
    }

    func testIgnoresShortEnglishUiLabelsWhenBuildingParagraphs() {
        let lines = [
            RecognizedTextLine(
                text: "Download",
                boundingBox: CGRect(x: 0.10, y: 0.72, width: 0.12, height: 0.04)
            ),
            RecognizedTextLine(
                text: "Settings",
                boundingBox: CGRect(x: 0.10, y: 0.64, width: 0.12, height: 0.04)
            ),
        ]

        let paragraphs = OCRService.groupParagraphs(from: lines)

        XCTAssertTrue(paragraphs.isEmpty)
    }

    func testParsesBulletLinesIntoListItemBlocks() {
        let lines = [
            RecognizedTextLine(
                text: "• Unlimited multi-agent parallel execution",
                boundingBox: CGRect(x: 0.10, y: 0.72, width: 0.42, height: 0.04)
            ),
            RecognizedTextLine(
                text: "• Automated orchestration from analysis to deployment",
                boundingBox: CGRect(x: 0.10, y: 0.66, width: 0.50, height: 0.04)
            ),
        ]

        let structure = ParagraphTextStructure.fromRecognizedLines(lines)

        XCTAssertEqual(
            structure.blocks,
            [
                ParagraphTextBlock(
                    kind: .listItem(marker: "•"),
                    bodyLines: ["Unlimited multi-agent parallel execution"]
                ),
                ParagraphTextBlock(
                    kind: .listItem(marker: "•"),
                    bodyLines: ["Automated orchestration from analysis to deployment"]
                ),
            ]
        )
        XCTAssertEqual(
            structure.renderedText,
            "• Unlimited multi-agent parallel execution\n• Automated orchestration from analysis to deployment"
        )
    }

    func testMergesIndentedContinuationIntoPreviousListItem() {
        let lines = [
            RecognizedTextLine(
                text: "• CLI compatibility: Claude, Gemini, Codex,",
                boundingBox: CGRect(x: 0.10, y: 0.72, width: 0.44, height: 0.04)
            ),
            RecognizedTextLine(
                text: "OpenCode, Qwen, OpenClaw",
                boundingBox: CGRect(x: 0.15, y: 0.66, width: 0.34, height: 0.04)
            ),
            RecognizedTextLine(
                text: "• Visual interface combined with command-line power",
                boundingBox: CGRect(x: 0.10, y: 0.60, width: 0.48, height: 0.04)
            ),
        ]

        let structure = ParagraphTextStructure.fromRecognizedLines(lines)

        XCTAssertEqual(
            structure.blocks,
            [
                ParagraphTextBlock(
                    kind: .listItem(marker: "•"),
                    bodyLines: [
                        "CLI compatibility: Claude, Gemini, Codex,",
                        "OpenCode, Qwen, OpenClaw",
                    ]
                ),
                ParagraphTextBlock(
                    kind: .listItem(marker: "•"),
                    bodyLines: ["Visual interface combined with command-line power"]
                ),
            ]
        )
    }

    func testApplyingTranslationsPreservesListMarkersAndOrder() {
        let structure = ParagraphTextStructure(
            blocks: [
                ParagraphTextBlock(kind: .listItem(marker: "•"), bodyLines: ["Unlimited multi-agent parallel execution"]),
                ParagraphTextBlock(kind: .plainLine, bodyLines: ["Keep existing shell behavior."]),
            ]
        )

        let rebuilt = structure.applyingTranslations(
            [
                "无限多代理并行执行",
                "保持现有面板行为。",
            ]
        )

        XCTAssertEqual(
            rebuilt,
            "• 无限多代理并行执行\n保持现有面板行为。"
        )
    }
}
