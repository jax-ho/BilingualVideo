import Foundation
import AVFoundation
import CryptoKit
import KokoroCoreML

protocol SpeechProviding: Sendable {
    func audio(for text: String) async throws -> URL
}

// Shared across reader lifetimes: closing/reopening cannot create parallel engines.
final class LocalSpeech: SpeechProviding, @unchecked Sendable {
    static let shared = LocalSpeech()
    private let scheduler: SpeechScheduler

    init() {
        let worker = SpeechWorker()
        scheduler = SpeechScheduler { text, check in try worker.audio(for: text, check: check) }
    }

    func audio(for text: String) async throws -> URL {
        try await scheduler.audio(for: text)
    }
}

// At most one synchronous synthesis and one pending request. The backend cannot
// interrupt a Core ML prediction; cancellation releases the caller immediately.
final class SpeechScheduler: SpeechProviding, @unchecked Sendable {
    typealias Synthesis = (String, () throws -> Void) throws -> URL
    private let lock = NSLock()
    private var pending: SpeechRequest?
    private var running = false
    private let synthesize: Synthesis

    init(synthesize: @escaping Synthesis) { self.synthesize = synthesize }

    // Internal diagnostic used by deterministic tests while synthesis is gated.
    var pendingText: String? {
        lock.lock(); defer { lock.unlock() }
        return pending?.text
    }

    func audio(for text: String) async throws -> URL {
        let request = SpeechRequest(text: text)
        let url: URL = try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                request.install(continuation)
                lock.lock()
                if request.isCancelled { lock.unlock(); return }
                let replaced = pending
                pending = request
                let start = !running
                running = true
                lock.unlock()
                replaced?.cancel()
                if start {
                    let thread = Thread { self.drain() }
                    thread.stackSize = 8 * 1024 * 1024
                    thread.start()
                }
            }
        }, onCancel: {
            request.cancel()
            self.lock.lock()
            if self.pending === request { self.pending = nil }
            self.lock.unlock()
        })
        try Task.checkCancellation()
        return url
    }

    private func drain() {
        while true {
            lock.lock()
            guard let request = pending else {
                running = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()
            do {
                try request.checkCancellation()
                let url = try synthesize(request.text, request.checkCancellation)
                try request.checkCancellation()
                request.finish(.success(url))
            } catch { request.finish(.failure(error)) }
        }
    }
}

private final class SpeechRequest: @unchecked Sendable {
    let text: String
    private let lock = NSLock()
    private var cancelled = false
    private var result: Result<URL, Error>?
    private var continuation: CheckedContinuation<URL, Error>?

    init(text: String) { self.text = text }
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
    func checkCancellation() throws { if isCancelled { throw CancellationError() } }
    func install(_ continuation: CheckedContinuation<URL, Error>) {
        lock.lock()
        if let result { lock.unlock(); continuation.resume(with: result) }
        else { self.continuation = continuation; lock.unlock() }
    }
    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
        finish(.failure(CancellationError()))
    }
    func finish(_ value: Result<URL, Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        // Cancellation wins even if the backend finishes concurrently.
        let value: Result<URL, Error> = cancelled ? .failure(CancellationError()) : value
        result = value
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: value)
    }
}

private final class SpeechWorker: @unchecked Sendable {
    private var engine: KokoroEngine?
    private let voice = "af_heart"
    private let speed: Float = 0.9

    func audio(for text: String, check: () throws -> Void) throws -> URL {
        try check()
        let identity = "kokoro-0.11.2-models-2026-03-23|af_heart|0.9|\(text)"
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PageAudio", isDirectory: true)
        let url = directory.appendingPathComponent("\(hash).wav")
        try? PageAudioCache.prune(directory: directory, protecting: url)
        if let cached = try? AVAudioFile(forReading: url), cached.length > 0 {
            try check()
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            return url
        }
        if engine == nil {
            guard let models = Bundle.main.url(forResource: "KokoroModels", withExtension: nil) else {
                throw LocalSpeechError.unavailable
            }
            #if targetEnvironment(simulator)
            engine = try KokoroEngine(modelDirectory: models, forceCPU: true)
            #else
            engine = try KokoroEngine(modelDirectory: models)
            #endif
        }
        guard let engine else { throw LocalSpeechError.unavailable }
        try check()
        let result = try engine.synthesize(text: text, voice: voice, speed: speed)
        try check()
        guard !result.samples.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(result.samples.count)),
              let channel = buffer.floatChannelData?[0] else { throw LocalSpeechError.unavailable }
        buffer.frameLength = buffer.frameCapacity
        result.samples.withUnsafeBufferPointer { samples in
            channel.update(from: samples.baseAddress!, count: samples.count)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent("\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: temporary) }
        var file: AVAudioFile? = try AVAudioFile(forWriting: temporary, settings: format.settings)
        try file?.write(from: buffer)
        file = nil
        try check()
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try FileManager.default.moveItem(at: temporary, to: url)
        try? PageAudioCache.prune(directory: directory, protecting: url)
        return url
    }
}

enum LocalSpeechError: LocalizedError {
    case unavailable
    var errorDescription: String? { "声音暂时没准备好，请再点一次。" }
}

// Best-effort LRU by last access (modification time). Only owned WAV files are
// removed. Protect the returned file so AVAudioPlayer can open it after return.
enum PageAudioCache {
    static let maximumBytes: Int64 = 128 * 1024 * 1024

    static func prune(directory: URL, protecting protectedURL: URL? = nil,
                      maximumBytes: Int64 = PageAudioCache.maximumBytes) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else { return }
        let files = try manager.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
        let entries = try files.filter { $0.pathExtension == "wav" }.compactMap { url -> (URL, Int64, Date)? in
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard values.isRegularFile == true else { return nil }
            return (url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(Int64(0)) { $0 + $1.1 }
        for (url, size, _) in entries where total > maximumBytes && url != protectedURL {
            try manager.removeItem(at: url)
            total -= size
        }
        // A single protected page may exceed the budget; it is evicted on the
        // next request. The limit is intentionally soft while a page is in use.
    }
}
