import XCTest
@testable import BilingualVideo

final class VideoLibraryScannerTests: XCTestCase {
    func testPairsDifferentPaddingAndSortsNumerically() throws {
        let environment = try TemporaryAppEnvironment()
        try environment.createFile("100.mp4", language: .chinese)
        try environment.createFile("005.mp4", language: .chinese)
        try environment.createFile("20.MP4", language: .chinese)
        try environment.createFile("100.mp4", language: .english)
        try environment.createFile("5.mp4", language: .english)
        try environment.createFile("020.mp4", language: .english)
        try environment.createFile(".DS_Store", language: .chinese)

        let result = VideoLibraryScanner(directories: environment.directories).scan()

        XCTAssertTrue(result.isValidForGeneration)
        XCTAssertEqual(result.pairs.map(\.id), [5, 20, 100])
        XCTAssertEqual(result.pairs[0].chineseFileName, "005.mp4")
        XCTAssertEqual(result.pairs[0].englishFileName, "5.mp4")
    }

    func testAggregatesInvalidVisibleItemsAndUnmatchedIDs() throws {
        let environment = try TemporaryAppEnvironment()
        try environment.createFile("1.mp4", language: .chinese)
        try environment.createFile("abc.mp4", language: .chinese)
        try environment.createFile("notes.txt", language: .chinese)
        try environment.createVisibleDirectory("folder.mp4", language: .chinese)
        try environment.createFile("2.mp4", language: .english)

        let result = VideoLibraryScanner(directories: environment.directories).scan()

        XCTAssertFalse(result.isValidForGeneration)
        XCTAssertEqual(result.pairs, [])
        XCTAssertEqual(result.issues.filter { $0.kind == .invalidIdentifier }.count, 1)
        XCTAssertEqual(result.issues.filter { $0.kind == .unsupportedItem }.count, 2)
        XCTAssertEqual(result.issues.filter { $0.kind == .unmatchedIdentifier }.count, 2)
    }

    func testDetectsNumericDuplicateWithLeadingZeros() throws {
        let environment = try TemporaryAppEnvironment()
        try environment.createFile("5.mp4", language: .chinese)
        try environment.createFile("005.mp4", language: .chinese)
        try environment.createFile("5.mp4", language: .english)

        let result = VideoLibraryScanner(directories: environment.directories).scan()

        let duplicate = try XCTUnwrap(result.issues.first { $0.kind == .duplicateIdentifier })
        XCTAssertEqual(Set(duplicate.relatedFiles), ["Chinese/5.mp4", "Chinese/005.mp4"])
        XCTAssertTrue(result.issues.filter { $0.kind == .unmatchedIdentifier }.isEmpty)
        XCTAssertNil(result.pair(id: 5))
    }

    func testRejectsUnicodeDigitsWhitespaceSignAndOverflow() throws {
        let environment = try TemporaryAppEnvironment()
        let invalidNames = ["１２.mp4", " 12.mp4", "-12.mp4", "999999999999999999999999.mp4"]
        for name in invalidNames {
            try environment.createFile(name, language: .chinese)
        }

        let result = VideoLibraryScanner(directories: environment.directories).scan()

        XCTAssertEqual(result.issues.filter { $0.kind == .invalidIdentifier }.count, invalidNames.count)
    }

    func testReportsMissingDirectory() throws {
        let environment = try TemporaryAppEnvironment()
        try FileManager.default.removeItem(at: environment.directories.englishURL)

        let result = VideoLibraryScanner(directories: environment.directories).scan()

        XCTAssertTrue(result.pairs.isEmpty)
        XCTAssertEqual(result.issues.map(\.kind), [.missingDirectory])
    }

    func testUnreadableDirectoryDoesNotCascadeIntoFalseMissingPairIssues() throws {
        let environment = try TemporaryAppEnvironment()
        try environment.createFile("1.mp4", language: .chinese)
        let englishURL = environment.directories.englishURL
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: englishURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: englishURL.path)
        }

        let result = VideoLibraryScanner(directories: environment.directories).scan()

        XCTAssertTrue(result.pairs.isEmpty)
        XCTAssertEqual(result.issues.map(\.kind), [.unsupportedItem])
        XCTAssertEqual(result.issues.first?.message, "无法读取 English 文件夹")
    }

    func testEmptyLibraryCannotGeneratePlan() throws {
        let environment = try TemporaryAppEnvironment()

        let result = VideoLibraryScanner(directories: environment.directories).scan()

        XCTAssertFalse(result.isValidForGeneration)
        XCTAssertEqual(result.issues.map(\.kind), [.emptyLibrary])
    }
}
