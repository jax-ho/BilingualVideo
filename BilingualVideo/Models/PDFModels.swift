import Foundation

enum StudyContent: String, CaseIterable, Identifiable {
    case video, pdf

    var id: String { rawValue }
    var displayName: String { self == .video ? "视频" : "RAZ PDF" }
    var unit: String { self == .video ? "组" : "份" }
}

enum LearningOrder: String, CaseIterable, Identifiable {
    case videosFirst, pdfsFirst

    var id: String { rawValue }
    var displayName: String { self == .videosFirst ? "先看视频，再读 PDF" : "先读 PDF，再看视频" }
    var contents: [StudyContent] { self == .videosFirst ? [.video, .pdf] : [.pdf, .video] }
}

struct PDFBook: Identifiable, Equatable {
    let id: Int
    let fileName: String
}

struct PDFLibraryScanResult: Equatable {
    var books: [PDFBook] = []
    var issues: [LibraryValidationIssue] = []

    var isValidForGeneration: Bool { !books.isEmpty && issues.isEmpty }
    func book(id: Int) -> PDFBook? { books.first { $0.id == id } }
}

struct PDFReadingProgress: Codable, Equatable {
    let day: LocalDay
    let bookIDs: [Int]
    var index = 0
    var pageIndex = 0
    var pageCount = 0
    var hasStarted = false
    let sessionID: UUID

    var isFinished: Bool { index == bookIDs.count }
}

struct PDFReadingRequest: Identifiable, Equatable {
    let day: LocalDay
    let index: Int
    let sessionID: UUID
    let book: PDFBook
    let url: URL
    let pageIndex: Int
    let bookCount: Int

    var id: String { "\(sessionID)-\(index)-\(book.id)" }
}

struct NormalVideoCompletion: Codable, Equatable {
    let day: LocalDay
    let pairIDs: [Int]
    var completedVideoIDs: [String] = []

    var videoIDs: [String] {
        pairIDs.flatMap { id in VideoLanguage.allCases.map { "\(id)-\($0.rawValue)" } }
    }
    var isFinished: Bool { Set(completedVideoIDs) == Set(videoIDs) }
}

enum PDFReadingError: LocalizedError {
    case expired, invalidPage, unavailable(Int)

    var errorDescription: String? {
        switch self {
        case .expired: "日期或 PDF 计划已变化，请返回首页重新开始今天的学习。"
        case .invalidPage: "请读到最后一页，再结束这份 PDF 的学习。"
        case let .unavailable(id): "编号 \(id) 的 PDF 无法打开，请让家长检查 raz 文件夹。"
        }
    }
}
