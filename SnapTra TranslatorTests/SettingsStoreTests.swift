import XCTest
@testable import SnapTra_Translator

@MainActor
final class LookupLanguagePairTests: XCTestCase {
    func testFixedLanguagePairPreservesIdentifiers() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "ja")

        XCTAssertEqual(pair.sourceIdentifier, "en")
        XCTAssertEqual(pair.targetIdentifier, "ja")
    }

    func testSameLanguageDetection() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "en")
        XCTAssertTrue(pair.isSameLanguage)
    }

    func testDifferentLanguageDetection() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "zh-Hans")
        XCTAssertFalse(pair.isSameLanguage)
    }
}

@MainActor
final class SettingsStoreMigrationTests: XCTestCase {
    func testSingleKeyMigrationMapsLegacyLeftAndRightValuesToGenericModifier() {
        XCTAssertEqual(SingleKey.migrated(from: "leftCommand"), .command)
        XCTAssertEqual(SingleKey.migrated(from: "rightCommand"), .command)
        XCTAssertEqual(SingleKey.migrated(from: "leftOption"), .option)
        XCTAssertEqual(SingleKey.migrated(from: "rightControl"), .control)
        XCTAssertEqual(SingleKey.migrated(from: "leftShift"), .shift)
    }

    func testSettingsStorePersistsMigratedSingleKeyValue() {
        let suiteName = "SettingsStoreMigrationTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("rightCommand", forKey: AppSettingKey.singleKey)

        let store = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertEqual(store.singleKey, .command)
        XCTAssertEqual(defaults.string(forKey: AppSettingKey.singleKey), SingleKey.command.rawValue)
    }

    func testDefaultDictionarySources() {
        let sources = SettingsStore.defaultDictionarySources(ecdictInstalled: false)

        XCTAssertEqual(
            sources.map(\.type),
            [.ecdict, .system]
        )
        XCTAssertTrue(sources.contains { $0.type == .system && $0.isEnabled })
    }

    func testMigrationPreservesSources() {
        let existing: [DictionarySource] = [
            DictionarySource(id: UUID(), name: "System Dictionary", type: .system, isEnabled: true),
            DictionarySource(id: UUID(), name: "Advanced Dictionary", type: .ecdict, isEnabled: false),
        ]
        let migrated = SettingsStore.migrateDictionarySources(existing)

        XCTAssertEqual(
            migrated.map(\.type),
            [.system, .ecdict]
        )
        XCTAssertTrue(migrated[0].isEnabled)
        XCTAssertFalse(migrated[1].isEnabled)
    }
}
