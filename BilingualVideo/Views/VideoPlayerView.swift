@preconcurrency import AVFoundation
@preconcurrency import AVKit
import SwiftUI
@preconcurrency import UIKit

@MainActor
final class LocalVideoPlaybackSession {
    enum PlaybackError: LocalizedError {
        case missingFile
        case notPlayable

        var errorDescription: String? {
            switch self {
            case .missingFile:
                "视频文件不存在"
            case .notPlayable:
                "视频文件无法播放"
            }
        }
    }

    let player = AVPlayer()
    var onFailure: ((String) -> Void)?
    var onVideoChanged: ((PlayableVideo) -> Void)?
    var onPlayback: ((PlayableVideo, Date) -> Void)?
    var onProgress: ((PlayableVideo, Double) -> Void)?
    var onPlayingChanged: ((Bool) -> Void)?
    var onEnded: ((PlayableVideo) -> Void)?
    var nextVideo: ((PlayableVideo) throws -> PlayableVideo?)?
    var allowsAutomaticAdvance = true
    private(set) var currentVideo: PlayableVideo?

    private var statusObservation: NSKeyValueObservation?
    private var playbackStatusObservation: NSKeyValueObservation?
    private var playbackTimeObserver: Any?
    private var playingSince: Date?
    private var failedToEndObserver: NSObjectProtocol?
    private var didPlayToEndObserver: NSObjectProtocol?
    private var loadID = UUID()
    private var continuationTask: Task<Void, Never>?
    private var continuationID: UUID?

    func prepare(video: PlayableVideo, resumeAt seconds: Double = 0) async throws {
        try Task.checkCancellation()
        stop()
        try await load(video: video)
        if seconds > 0 {
            let expectedLoadID = loadID
            guard let asset = player.currentItem?.asset else { throw PlaybackError.notPlayable }
            let duration = try await asset.load(.duration).seconds
            try Task.checkCancellation()
            guard loadID == expectedLoadID else { throw CancellationError() }
            guard seconds.isFinite, duration.isFinite, seconds <= duration else {
                throw PlaybackError.notPlayable
            }
            // A checkpoint at the final frame must still reach the natural-end
            // observer after a restart, rather than remain stuck at the end.
            let restored = await player.seek(
                to: CMTime(seconds: min(seconds, max(0, duration - 0.01)), preferredTimescale: 600),
                toleranceBefore: .zero, toleranceAfter: .zero
            )
            try Task.checkCancellation()
            guard loadID == expectedLoadID else { throw CancellationError() }
            guard restored else { throw PlaybackError.notPlayable }
        }
    }

    private func load(video: PlayableVideo) async throws {
        try Task.checkCancellation()
        resetItem()

        let currentLoadID = UUID()
        loadID = currentLoadID
        let url = video.url

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PlaybackError.missingFile
        }

        let asset = AVURLAsset(url: url)
        let isPlayable = try await asset.load(.isPlayable)
        try Task.checkCancellation()
        guard loadID == currentLoadID else { throw CancellationError() }
        guard isPlayable else { throw PlaybackError.notPlayable }

        configureAudioSession()

        let item = AVPlayerItem(asset: asset)
        observe(item: item, loadID: currentLoadID)
        player.replaceCurrentItem(with: item)
        currentVideo = video
        onVideoChanged?(video)
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func stop() {
        continuationID = nil
        continuationTask?.cancel()
        continuationTask = nil
        resetItem()
    }

    private func resetItem() {
        finishPlaying(at: Date())
        loadID = UUID()
        currentVideo = nil
        statusObservation?.invalidate()
        statusObservation = nil
        playbackStatusObservation?.invalidate()
        playbackStatusObservation = nil
        if let playbackTimeObserver {
            player.removeTimeObserver(playbackTimeObserver)
            self.playbackTimeObserver = nil
        }

        if let failedToEndObserver {
            NotificationCenter.default.removeObserver(failedToEndObserver)
            self.failedToEndObserver = nil
        }
        if let didPlayToEndObserver {
            NotificationCenter.default.removeObserver(didPlayToEndObserver)
            self.didPlayToEndObserver = nil
        }

        player.pause()
        onPlayingChanged?(false)
        player.replaceCurrentItem(with: nil)
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func advanceAfterEnd() {
        guard allowsAutomaticAdvance, continuationTask == nil, let currentVideo else { return }
        do {
            guard let next = try nextVideo?(currentVideo) else { return }
            let expectedID = UUID()
            continuationID = expectedID
            continuationTask = Task { [weak self] in
                guard let self, self.continuationID == expectedID else { return }
                defer {
                    if self.continuationID == expectedID {
                        self.continuationID = nil
                        self.continuationTask = nil
                    }
                }
                do {
                    try await self.load(video: next)
                    try Task.checkCancellation()
                    guard self.continuationID == expectedID else { return }
                    if self.allowsAutomaticAdvance {
                        self.play()
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard self.continuationID == expectedID else { return }
                    self.onFailure?(error.localizedDescription)
                }
            }
        } catch {
            onFailure?(error.localizedDescription)
        }
    }

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .moviePlayback)
        try? audioSession.setActive(true)
    }

    private func observe(item: AVPlayerItem, loadID: UUID) {
        playbackStatusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self, weak item] player, _ in
            let status = player.timeControlStatus
            let timestamp = Date()
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.loadID == loadID,
                      self.player.currentItem === item else { return }
                self.onPlayingChanged?(status == .playing)
                if status == .playing, item.status == .readyToPlay, let video = self.currentVideo {
                    self.playingSince = timestamp
                    self.onPlayback?(video, timestamp)
                } else {
                    self.finishPlaying(at: timestamp)
                }
            }
        }
        // A video can span midnight without changing its playing state.
        playbackTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self, weak item] _ in
            let timestamp = Date()
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.loadID == loadID,
                      self.player.currentItem === item, item.status == .readyToPlay,
                      self.player.timeControlStatus == .playing, self.player.rate > 0,
                      let video = self.currentVideo else { return }
                self.onPlayback?(video, timestamp)
                self.onProgress?(video, self.player.currentTime().seconds)
            }
        }
        statusObservation = item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
            guard let item, item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? PlaybackError.notPlayable.localizedDescription
            Task { @MainActor [weak self, weak item] in
                guard let self,
                      let item,
                      self.loadID == loadID,
                      self.player.currentItem === item else { return }
                self.onFailure?(message)
            }
        }

        failedToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak item] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            let message = error?.localizedDescription ?? PlaybackError.notPlayable.localizedDescription
            Task { @MainActor [weak self, weak item] in
                guard let self,
                      let item,
                      self.loadID == loadID,
                      self.player.currentItem === item else { return }
                self.onFailure?(message)
            }
        }

        didPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self,
                      let item,
                      self.loadID == loadID,
                      self.player.currentItem === item else { return }
                if let onEnded = self.onEnded, let video = self.currentVideo {
                    onEnded(video)
                } else {
                    self.advanceAfterEnd()
                }
            }
        }
    }

    private func finishPlaying(at date: Date) {
        guard let started = playingSince, let video = currentVideo else { return }
        playingSince = nil
        // The paused instant itself is not playback (notably exactly midnight).
        onPlayback?(video, max(started, date.addingTimeInterval(-0.000001)))
    }
}

/// Presents AVPlayerViewController itself, rather than embedding it in a
/// SwiftUI cover. AVKit therefore owns the complete auto-hiding control set,
/// including the system Done and replay controls.
struct NativeVideoPlayerPresenter: UIViewControllerRepresentable {
    @Binding var video: PlayableVideo?
    let scenePhase: ScenePhase
    let nextVideo: (PlayableVideo) throws -> PlayableVideo?
    let onPlayback: (PlayableVideo, Date) -> Void
    let onDismiss: () -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .clear
        viewController.view.isUserInteractionEnabled = false
        return viewController
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {
        context.coordinator.update(
            presenter: viewController,
            video: video,
            videoBinding: $video,
            scenePhase: scenePhase,
            nextVideo: nextVideo,
            onPlayback: onPlayback,
            onDismiss: onDismiss,
            onFailure: onFailure
        )
    }

    static func dismantleUIViewController(
        _ viewController: UIViewController,
        coordinator: Coordinator
    ) {
        coordinator.tearDown(presenter: viewController)
    }

    @MainActor
    final class Coordinator: NSObject, @MainActor AVPlayerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
        private let session = LocalVideoPlaybackSession()
        private weak var presenter: UIViewController?
        private weak var playerViewController: AVPlayerViewController?
        private var videoBinding: Binding<PlayableVideo?>?
        private var onDismiss: (() -> Void)?
        private var onFailure: ((String) -> Void)?
        private var loadTask: Task<Void, Never>?
        private var activeVideoID: String?
        private var isSceneActive = true
        private var dismissalInFlight = false
        private var isFinishing = false

        override init() {
            super.init()
            session.onFailure = { [weak self] message in
                self?.handlePlaybackFailure(message)
            }
            session.onVideoChanged = { [weak self] video in
                self?.activeVideoID = video.id
                self?.videoBinding?.wrappedValue = video
            }
        }

        func update(
            presenter: UIViewController,
            video: PlayableVideo?,
            videoBinding: Binding<PlayableVideo?>,
            scenePhase: ScenePhase,
            nextVideo: @escaping (PlayableVideo) throws -> PlayableVideo?,
            onPlayback: @escaping (PlayableVideo, Date) -> Void,
            onDismiss: @escaping () -> Void,
            onFailure: @escaping (String) -> Void
        ) {
            self.presenter = presenter
            self.videoBinding = videoBinding
            self.onDismiss = onDismiss
            self.onFailure = onFailure
            session.nextVideo = nextVideo
            session.onPlayback = onPlayback
            isSceneActive = scenePhase == .active
            session.allowsAutomaticAdvance = isSceneActive && !dismissalInFlight

            guard isSceneActive else {
                session.pause()
                if playerViewController == nil, activeVideoID != nil {
                    loadTask?.cancel()
                    loadTask = nil
                    activeVideoID = nil
                    session.stop()
                }
                return
            }

            guard let video else {
                if activeVideoID != nil {
                    dismissPresentedPlayer(notifyDismiss: true)
                }
                return
            }

            guard video.id != activeVideoID else { return }
            present(video: video, from: presenter)
        }

        func tearDown(presenter: UIViewController) {
            loadTask?.cancel()
            loadTask = nil
            if let playerViewController, playerViewController.presentingViewController != nil {
                playerViewController.dismiss(animated: false)
            } else if presenter.presentedViewController is AVPlayerViewController {
                presenter.dismiss(animated: false)
            }
            finish(notifyDismiss: false, clearBinding: false)
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
        ) {
            guard self.playerViewController === playerViewController else { return }
            dismissalInFlight = true
            session.allowsAutomaticAdvance = false
            session.pause()
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                // The transition context is valid only for this callback. Copy the
                // value before hopping back to MainActor.
                let transitionWasCancelled = context.isCancelled
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard !transitionWasCancelled else {
                        if self.playerViewController === playerViewController {
                            self.dismissalInFlight = false
                            self.session.allowsAutomaticAdvance = self.isSceneActive
                        }
                        return
                    }
                    self.finish(notifyDismiss: true, clearBinding: true)
                }
            }
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            guard let playerViewController,
                  presentationController.presentedViewController === playerViewController else { return }
            dismissalInFlight = true
            finish(notifyDismiss: true, clearBinding: true)
        }

        private func present(video: PlayableVideo, from presenter: UIViewController) {
            guard playerViewController == nil, !dismissalInFlight else { return }

            if let activeVideoID, activeVideoID != video.id {
                loadTask?.cancel()
                loadTask = nil
                self.activeVideoID = nil
                session.stop()
            }

            loadTask?.cancel()
            activeVideoID = video.id
            let expectedVideoID = video.id

            loadTask = Task { [weak self, weak presenter] in
                guard let self else { return }
                do {
                    try await self.session.prepare(video: video)
                    try Task.checkCancellation()
                    guard self.activeVideoID == expectedVideoID else { return }
                    guard self.isSceneActive else {
                        self.loadTask = nil
                        self.activeVideoID = nil
                        self.session.stop()
                        return
                    }
                    guard let presenter, presenter.viewIfLoaded?.window != nil else {
                        self.loadTask = nil
                        self.handlePlaybackFailure("播放器暂时无法打开")
                        return
                    }

                    let playerViewController = AVPlayerViewController()
                    playerViewController.player = self.session.player
                    playerViewController.showsPlaybackControls = true
                    playerViewController.exitsFullScreenWhenPlaybackEnds = false
                    playerViewController.delegate = self
                    playerViewController.presentationController?.delegate = self

                    self.playerViewController = playerViewController
                    self.loadTask = nil
                    presenter.present(playerViewController, animated: true) { [weak self, weak playerViewController] in
                        guard let self,
                              let playerViewController,
                              self.playerViewController === playerViewController,
                              self.isSceneActive else {
                            self?.session.pause()
                            return
                        }
                        self.session.play()
                    }
                    playerViewController.presentationController?.delegate = self
                } catch is CancellationError {
                    return
                } catch {
                    guard self.activeVideoID == expectedVideoID else { return }
                    self.handlePlaybackFailure(error.localizedDescription)
                }
            }
        }

        private func handlePlaybackFailure(_ message: String) {
            guard !dismissalInFlight else { return }
            dismissalInFlight = true
            session.allowsAutomaticAdvance = false
            session.pause()
            let failureHandler = onFailure
            let controller = playerViewController

            if controller?.presentingViewController != nil {
                controller?.dismiss(animated: true) { [weak self] in
                    guard let self else { return }
                    self.finish(notifyDismiss: true, clearBinding: true)
                    failureHandler?("无法播放这个视频。\(message)")
                }
            } else {
                finish(notifyDismiss: true, clearBinding: true)
                failureHandler?("无法播放这个视频。\(message)")
            }
        }

        private func dismissPresentedPlayer(notifyDismiss: Bool) {
            guard !dismissalInFlight else { return }
            dismissalInFlight = true
            session.allowsAutomaticAdvance = false
            session.pause()
            loadTask?.cancel()
            loadTask = nil

            guard let playerViewController,
                  playerViewController.presentingViewController != nil else {
                finish(notifyDismiss: notifyDismiss, clearBinding: false)
                return
            }

            playerViewController.dismiss(animated: true) { [weak self] in
                self?.finish(notifyDismiss: notifyDismiss, clearBinding: false)
            }
        }

        private func finish(notifyDismiss: Bool, clearBinding: Bool) {
            guard !isFinishing else { return }
            guard activeVideoID != nil || playerViewController != nil || loadTask != nil else { return }
            isFinishing = true

            loadTask?.cancel()
            loadTask = nil
            playerViewController?.delegate = nil
            playerViewController?.presentationController?.delegate = nil
            playerViewController?.player = nil
            playerViewController = nil
            activeVideoID = nil
            session.stop()

            if clearBinding {
                videoBinding?.wrappedValue = nil
            }
            if notifyDismiss {
                onDismiss?()
            }

            dismissalInFlight = false
            isFinishing = false
        }
    }
}
