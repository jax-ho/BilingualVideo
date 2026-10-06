import SwiftUI
import PDFKit
import AVFoundation
import CryptoKit

@MainActor
final class PDFReaderModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var pages: [ReadingPage] = []
    @Published var pageIndex = 0
    @Published var isSpeaking = false
    @Published var isPreparing = false
    @Published var isLoading = false
    @Published var speechError: String?
    @Published private(set) var request: PDFReadingRequest
    @Published var error: String?
    @Published private(set) var pageImages: [Int: CGImage] = [:]
    private let speech = LocalSpeech()
    private var player: AVAudioPlayer?
    private var generation: Task<Void, Never>?
    private var playbackID = UUID()
    private var document: PDFDocument?
    private var images: [Int: CGImage] = [:]
    private let appModel: AppModel
    private var recognition: Task<[ReadingPage], Error>?
    private var isClosed = false
    private var needsNextBook = false

    init(request: PDFReadingRequest, appModel: AppModel) {
        self.request = request
        self.appModel = appModel
        super.init()
    }

    var current: ReadingPage? { pages.indices.contains(pageIndex) ? pages[pageIndex] : nil }

    func load() async {
        guard !isLoading else { return }
        guard !isClosed else { return }
        stop()
        isLoading = true
        defer { isLoading = false }
        error = nil
        pages = []
        images = [:]
        pageImages = [:]
        pageIndex = request.pageIndex
        do {
            if needsNextBook, let next = try appModel.beginPDFReading() {
                request = next
                pageIndex = next.pageIndex
                needsNextBook = false
            }
            guard appModel.isCurrentPDFRequest(request) else { throw PDFReadingError.expired }
            let url = request.url
            guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else {
                throw ReaderError.missingBook
            }
            self.document = document
            let task = Task.detached(priority: .userInitiated) {
                let data = try Data(contentsOf: url)
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("RAZReader", isDirectory: true)
                let cache = directory.appendingPathComponent("\(hash)-v\(BookRecognizer.ruleVersion).json")
                guard let source = PDFDocument(url: url) else { throw ReaderError.missingBook }
                if let cachedData = try? Data(contentsOf: cache),
                   let cached = try? JSONDecoder().decode([ReadingPage].self, from: cachedData),
                   cached.count == source.pageCount,
                   cached.enumerated().allSatisfy({ $0.offset == $0.element.index }) {
                    return cached
                }
                var results: [ReadingPage] = []
                for index in 0..<source.pageCount {
                    try Task.checkCancellation()
                    guard let page = source.page(at: index) else { throw ReaderError.render }
                    let result = try autoreleasepool { try BookRecognizer.recognize(page, index: index) }
                    results.append(result)
                }
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if let encoded = try? JSONEncoder().encode(results) { try? encoded.write(to: cache, options: .atomic) }
                return results
            }
            recognition = task
            let results = try await withTaskCancellationHandler(operation: {
                try await task.value
            }, onCancel: { task.cancel() })
            try Task.checkCancellation()
            guard !isClosed, appModel.isCurrentPDFRequest(request) else { throw PDFReadingError.expired }
            pages = results
            pageIndex = min(pageIndex, pages.count - 1)
            updateImage()
            if error == nil { try checkpoint() }
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    func finish() async throws -> Bool {
        guard !isLoading, error == nil, pageIndex == pages.count - 1 else { throw PDFReadingError.invalidPage }
        try checkpoint()
        let next: PDFReadingRequest?
        do {
            next = try appModel.finishPDFReading(request)
        } catch {
            if case PDFReadingError.unavailable = error {
                needsNextBook = true
                self.error = error.localizedDescription
            }
            throw error
        }
        stop()
        guard let next else { return true }
        request = next
        await load()
        return false
    }

    func close() {
        isClosed = true
        recognition?.cancel()
        stop()
    }

    func stop() {
        playbackID = UUID()
        generation?.cancel()
        generation = nil
        player?.stop()
        player = nil
        isPreparing = false
        isSpeaking = false
        speechError = nil
    }

    func turn(_ delta: Int) {
        guard delta != 0, !isLoading, error == nil, !isClosed else { return }
        let next = pageIndex + delta
        guard pages.indices.contains(next) else { return }
        let previous = pageIndex
        stop()
        pageIndex = next
        updateImage()
        guard error == nil else { return }
        do {
            try appModel.savePDFPage(request, pageIndex: next, pageCount: pages.count)
        } catch {
            pageIndex = previous
            self.error = "阅读进度未能保存，已停止阅读。\(error.localizedDescription)"
        }
    }

    private func checkpoint() throws {
        try appModel.savePDFPage(request, pageIndex: pageIndex, pageCount: pages.count)
    }

    private func updateImage() {
        // Keep neighboring pages ready so the native pager can reveal them while dragging.
        for index in (pageIndex - 1)...(pageIndex + 1) where pages.indices.contains(index) {
            if images[index] == nil, let page = document?.page(at: index),
               let image = try? BookRecognizer.image(of: page, height: 2000) {
                images[index] = image
            }
        }
        images = images.filter { abs($0.key - pageIndex) <= 2 }
        pageImages = images
        if images[pageIndex] == nil {
            error = ReaderError.render.localizedDescription
        }
    }

    func speak() {
        guard !isClosed, error == nil, appModel.isCurrentPDFRequest(request),
              !isPreparing, let text = current?.text, !text.isEmpty else { return }
        stop()
        let id = playbackID
        isPreparing = true
        generation = Task {
            do {
                let audio = try await speech.audio(for: text)
                guard !Task.isCancelled, playbackID == id else { return }
                #if os(iOS)
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)
                #endif
                let nextPlayer = try AVAudioPlayer(contentsOf: audio)
                nextPlayer.delegate = self
                player = nextPlayer
                guard nextPlayer.play() else { throw LocalSpeechError.unavailable }
                isPreparing = false
                isSpeaking = true
            } catch {
                guard !Task.isCancelled, playbackID == id else { return }
                isPreparing = false
                isSpeaking = false
                speechError = LocalSpeechError.unavailable.localizedDescription
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.isSpeaking = false
            self.player = nil
            if !flag { self.speechError = LocalSpeechError.unavailable.localizedDescription }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.isSpeaking = false
            self.player = nil
            self.speechError = LocalSpeechError.unavailable.localizedDescription
        }
    }
}
