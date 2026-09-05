import Foundation

enum VideoLanguage: String, CaseIterable, Codable, Hashable, Identifiable {
    case chinese
    case english

    var id: String { rawValue }

    var folderName: String {
        switch self {
        case .chinese: "Chinese"
        case .english: "English"
        }
    }

    var displayName: String {
        switch self {
        case .chinese: "中文"
        case .english: "英文"
        }
    }

    var playAccessibilityLabel: String {
        "播放\(displayName)视频"
    }
}

struct VideoPair: Codable, Identifiable, Hashable {
    let id: Int
    let chineseFileName: String
    let englishFileName: String

    func fileName(for language: VideoLanguage) -> String {
        switch language {
        case .chinese: chineseFileName
        case .english: englishFileName
        }
    }
}

/// A calendar date without a time or time zone. Persisting a civil day avoids
/// moving a plan to the previous or next day when the iPad changes time zones.
struct LocalDay: Codable, Hashable, Comparable {
    let year: Int
    let month: Int
    let day: Int

    init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = components.year!
        self.month = components.month!
        self.day = components.day!
    }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    func date(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        ))
    }

    func adding(days: Int, calendar: Calendar) -> LocalDay? {
        guard let sourceDate = date(in: calendar),
              let result = calendar.date(byAdding: .day, value: days, to: sourceDate) else {
            return nil
        }
        return LocalDay(date: result, calendar: calendar)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let year = try container.decode(Int.self, forKey: .year)
        let month = try container.decode(Int.self, forKey: .month)
        let day = try container.decode(Int.self, forKey: .day)

        var validationCalendar = Calendar(identifier: .gregorian)
        validationCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = validationCalendar.date(from: components) else {
            throw DecodingError.dataCorruptedError(
                forKey: .day,
                in: container,
                debugDescription: "Invalid local calendar day"
            )
        }
        let roundTrip = validationCalendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else {
            throw DecodingError.dataCorruptedError(
                forKey: .day,
                in: container,
                debugDescription: "Invalid local calendar day"
            )
        }

        self.init(year: year, month: month, day: day)
    }
}

struct ViewingPlan: Codable, Equatable {
    var startDay: LocalDay
    var orderedPairIDs: [Int]
    var updatedAt: Date
}

struct ScheduledPair: Identifiable, Equatable {
    let index: Int
    let pairID: Int
    let day: LocalDay

    var id: Int { pairID }
}

struct LibraryValidationIssue: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case missingDirectory
        case unsupportedItem
        case invalidIdentifier
        case duplicateIdentifier
        case unmatchedIdentifier
        case emptyLibrary
        case missingPlannedPair
    }

    let kind: Kind
    let message: String
    let relatedFiles: [String]

    var id: String {
        "\(kind.rawValue)|\(message)|\(relatedFiles.joined(separator: "|"))"
    }
}

struct LibraryScanResult: Equatable {
    var pairs: [VideoPair]
    var issues: [LibraryValidationIssue]

    static let empty = LibraryScanResult(pairs: [], issues: [])

    var isValidForGeneration: Bool {
        !pairs.isEmpty && issues.isEmpty
    }

    func pair(id: Int) -> VideoPair? {
        pairs.first { $0.id == id }
    }
}

enum TodayState: Equatable {
    case noScheduledItem
    case scheduledResourceUnavailable(pairID: Int)
    case playable(VideoPair)
}

struct PlayableVideo: Identifiable {
    let pairID: Int
    let language: VideoLanguage
    let url: URL

    var id: String { "\(pairID)-\(language.rawValue)" }
}
