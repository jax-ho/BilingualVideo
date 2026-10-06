import Foundation
import PDFKit
import Vision
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct ReadingLine: Codable {
    let text: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let confidence: Float
}

struct ReadingPage: Codable {
    let index: Int
    let text: String
    let lines: [ReadingLine]
}

enum BookRecognizer {
    static let ruleVersion = 2

    static func image(of page: PDFPage, height: CGFloat) throws -> CGImage {
        let bounds = page.bounds(for: .mediaBox)
        let size = CGSize(width: height * bounds.width / bounds.height, height: height)
        let thumbnail = page.thumbnail(of: size, for: .mediaBox)
        #if os(iOS)
        guard let image = thumbnail.cgImage else { throw ReaderError.render }
        #else
        guard let image = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ReaderError.render
        }
        #endif
        return image
    }

    static func recognize(_ page: PDFPage, index: Int) throws -> ReadingPage {
        var result = try recognize(page, index: index, height: 1800)
        if result.text.isEmpty {
            result = try recognize(page, index: index, height: 2600)
        }
        return result
    }

    private static func recognize(_ page: PDFPage, index: Int, height: CGFloat) throws -> ReadingPage {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image(of: page, height: height)).perform([request])
        let lines = (request.results ?? []).compactMap { observation -> ReadingLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return ReadingLine(text: candidate.string, x: box.minX, y: box.minY,
                               width: box.width, height: box.height, confidence: candidate.confidence)
        }
        let selected = selectReadingLines(lines)
        return ReadingPage(index: index, text: selected.map(\.text).joined(separator: " "), lines: selected)
    }

    static func selectReadingLines(_ lines: [ReadingLine]) -> [ReadingLine] {
        let candidates = lines.filter { line in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = text.lowercased()
            let metadata = ["written by", "illustrated by", "leveled book", "level aa",
                            "word count", "reading a-z", "reading a–z",
                            "copyright", "www."]
            guard text.rangeOfCharacter(from: .letters) != nil,
                  !metadata.contains(where: lower.contains),
                  lower != "nature", lower != "reading a-z",
                  text.range(of: "^\\*?\\s*[Aa]{1,2}\\s*\\d+", options: .regularExpression) == nil,
                  line.height >= 0.018 else { return false }
            return true
        }
        guard let largest = candidates.map(\.height).max() else { return [] }
        // Keep a coherent text block; distant publisher logos can be as large as a title.
        let prominent = candidates.filter { $0.height >= largest * 0.56 }
            .sorted { lhs, rhs in
                if abs(lhs.y - rhs.y) < min(lhs.height, rhs.height) * 0.5 { return lhs.x < rhs.x }
                return lhs.y > rhs.y
            }
        var groups: [[ReadingLine]] = []
        for line in prominent {
            if let previous = groups.last?.last {
                let gap = previous.y - (line.y + line.height)
                if gap <= max(previous.height, line.height) * 1.5 + 0.025 {
                    groups[groups.count - 1].append(line)
                    continue
                }
            }
            groups.append([line])
        }
        return groups.max { lhs, rhs in
            (lhs.map(\.height).max() ?? 0) < (rhs.map(\.height).max() ?? 0)
        } ?? []
    }
}

enum ReaderError: LocalizedError {
    case render, missingBook
    var errorDescription: String? {
        switch self {
        case .render: return "这页暂时没能打开。"
        case .missingBook: return "暂时没能打开这本书。"
        }
    }
}
