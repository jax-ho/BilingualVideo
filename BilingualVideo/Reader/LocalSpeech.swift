import Foundation
import AVFoundation
import CryptoKit
import KokoroCoreML

// One engine and one serial generation queue for all books; no network requests.
actor LocalSpeech {
    private let worker = SpeechWorker()

    func audio(for text: String) async throws -> URL {
        try Task.checkCancellation()
        let worker = worker
        let url = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let thread = Thread {
                do { continuation.resume(returning: try worker.audio(for: text)) }
                catch { continuation.resume(throwing: error) }
            }
            // CoreML prediction needs a larger stack than Swift's cooperative pool.
            thread.stackSize = 8 * 1024 * 1024
            thread.start()
        }
        try Task.checkCancellation()
        return url
    }
}

private final class SpeechWorker: @unchecked Sendable {
    private let lock = NSLock()
    private var engine: KokoroEngine?
    private let voice = "af_heart"
    private let speed: Float = 0.9

    func audio(for text: String) throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        let identity = "kokoro-0.11.2-models-2026-03-23|af_heart|0.9|\(text)"
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PageAudio", isDirectory: true)
        let url = directory.appendingPathComponent("\(hash).wav")
        if let cached = try? AVAudioFile(forReading: url), cached.length > 0 { return url }
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
        let result = try engine.synthesize(text: text, voice: voice, speed: speed)
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
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try FileManager.default.moveItem(at: temporary, to: url)
        return url
    }
}

enum LocalSpeechError: LocalizedError {
    case unavailable
    var errorDescription: String? { "声音暂时没准备好，请再点一次。" }
}
