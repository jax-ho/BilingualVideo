import Foundation
@testable import BilingualVideo

final class TemporaryAppEnvironment {
    let rootURL: URL
    let directories: AppDirectories

    init() throws {
        let fileManager = FileManager.default
        rootURL = fileManager.temporaryDirectory.appendingPathComponent(
            "BilingualVideoTests-\(UUID().uuidString)",
            isDirectory: true
        )
        directories = AppDirectories(
            documentsURL: rootURL.appendingPathComponent("Documents", isDirectory: true),
            applicationSupportURL: rootURL.appendingPathComponent("Application Support", isDirectory: true),
            fileManager: fileManager
        )
        try directories.prepareForLaunch()
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func createFile(_ name: String, language: VideoLanguage, contents: Data = Data([0x00])) throws {
        try contents.write(to: directories.folderURL(for: language).appendingPathComponent(name))
    }

    func createVisibleDirectory(_ name: String, language: VideoLanguage) throws {
        try FileManager.default.createDirectory(
            at: directories.folderURL(for: language).appendingPathComponent(name),
            withIntermediateDirectories: false
        )
    }

    func removeFile(_ name: String, language: VideoLanguage) throws {
        try FileManager.default.removeItem(
            at: directories.folderURL(for: language).appendingPathComponent(name)
        )
    }
}

func testCalendar(timeZoneIdentifier: String = "Asia/Shanghai") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(identifier: timeZoneIdentifier)!
    return calendar
}

func testDate(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    hour: Int = 12,
    calendar: Calendar = testCalendar()
) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}
