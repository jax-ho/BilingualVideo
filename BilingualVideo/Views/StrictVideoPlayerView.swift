@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// Shares decoding and lifecycle handling with normal mode, but exposes no
/// AVKit transport controls, seek gestures, picture-in-picture or media menus.
@MainActor
final class StrictVideoPlayerModel: ObservableObject {
    let session = LocalVideoPlaybackSession()
    @Published private(set) var request: StrictPlaybackRequest?
    @Published private(set) var isReady = false
    @Published private(set) var isPlaying = false
    @Published private(set) var isFinished = false
    @Published private(set) var shouldDismiss = false
    @Published private(set) var failure: String?
    @Published private(set) var position: Double
    private let appModel: AppModel
    private var loadTask: Task<Void, Never>?
    private var lastSavedPosition: Double
    private var isClosed = false

    init(request: StrictPlaybackRequest, appModel: AppModel) {
        self.request = request
        self.appModel = appModel
        position = request.position
        lastSavedPosition = request.position
        session.allowsAutomaticAdvance = false
        session.player.allowsExternalPlayback = false
        session.onPlayingChanged = { [weak self] in self?.isPlaying = $0 }
        session.onFailure = { [weak self] in self?.fail($0) }
        session.onPlayback = { [weak self] video, _ in
            guard let self, !self.isClosed, self.failure == nil,
                  let request = self.request, request.video == video else { return }
            guard self.appModel.strictProgressToday?.hasStarted != true else { return }
            do {
                try self.appModel.saveStrictProgress(
                    request, seconds: self.position, hasPlayed: true
                )
            } catch { self.handle(error) }
        }
        session.onProgress = { [weak self] video, seconds in
            guard let self, !self.isClosed, self.failure == nil,
                  let request = self.request, request.video == video else { return }
            guard self.appModel.isCurrentStrictRequest(request) else {
                self.expire()
                return
            }
            self.position = seconds
            if seconds - self.lastSavedPosition >= 1 { self.checkpoint() }
        }
        session.onEnded = { [weak self] video in self?.finish(video) }
    }

    func start() {
        guard loadTask == nil, !isClosed, let request else { return }
        isReady = false
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.session.prepare(video: request.video, resumeAt: request.position)
                try Task.checkCancellation()
                guard !self.isClosed, self.appModel.isCurrentStrictRequest(request) else {
                    self.expire()
                    return
                }
                self.isReady = true
                self.session.play()
            } catch is CancellationError {
                return
            } catch { self.handle(error) }
            self.loadTask = nil
        }
    }

    func togglePause() {
        guard isReady, failure == nil, !isClosed, let request else { return }
        guard appModel.isCurrentStrictRequest(request) else { expire(); return }
        if session.player.rate > 0 {
            session.pause()
            isPlaying = false
            checkpoint()
        } else {
            session.play()
        }
    }

    func close() {
        guard !isClosed else { return }
        session.pause()
        checkpoint()
        isClosed = true
        loadTask?.cancel()
        loadTask = nil
        session.stop()
    }

    private func checkpoint() {
        guard failure == nil, let request, session.currentVideo == request.video else { return }
        let seconds = session.player.currentTime().seconds
        guard seconds.isFinite, seconds >= 0 else { return }
        do {
            try appModel.saveStrictProgress(request, seconds: seconds)
            position = seconds
            lastSavedPosition = seconds
        } catch { handle(error) }
    }

    private func finish(_ video: PlayableVideo) {
        guard !isClosed, failure == nil, let request, request.video == video else { return }
        do {
            let next = try appModel.finishStrictEpisode(request)
            self.request = next
            isReady = false
            position = 0
            lastSavedPosition = 0
            session.stop()
            if next == nil {
                isFinished = true
            } else {
                start()
            }
        } catch { handle(error) }
    }

    private func handle(_ error: Error) {
        if let error = error as? StrictPlaybackError, case .expired = error {
            expire()
        } else {
            fail("播放或进度保存失败，已停止播放。\(error.localizedDescription)")
        }
    }

    private func fail(_ message: String) {
        guard failure == nil else { return }
        failure = message
        isReady = false
        session.pause()
    }

    private func expire() {
        isClosed = true
        loadTask?.cancel()
        loadTask = nil
        session.stop()
        shouldDismiss = true
    }
}

struct StrictVideoPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: StrictVideoPlayerModel
    @State private var showsControls = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var previousIdleTimerDisabled = false

    init(request: StrictPlaybackRequest, appModel: AppModel) {
        _model = StateObject(wrappedValue: StrictVideoPlayerModel(request: request, appModel: appModel))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if model.isFinished {
                Text("今天的视频已经播放完毕")
                    .font(.largeTitle.bold())
                    .accessibilityIdentifier("strict.finished")
            } else if let failure = model.failure {
                Text(failure).font(.title2).padding(48)
            } else {
                StrictVideoSurface(player: model.session.player)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { revealControls() }
                    .accessibilityLabel("视频画面")
                    .accessibilityIdentifier("strict.surface")
                    .accessibilityAction(named: "显示播放控制") { revealControls() }
                if !model.isReady { ProgressView().tint(.white) }
            }

            if showsControls || !model.isPlaying || model.isFinished || model.failure != nil {
                VStack {
                    HStack {
                        Button {
                            model.close()
                            dismiss()
                        } label: { Label("关闭", systemImage: "xmark") }
                        .accessibilityIdentifier("strict.close")
                        Spacer()
                        if let request = model.request {
                            Text("第 \(request.index + 1) / \(request.episodeCount) 集 · 编号 \(request.video.pairID) · \(request.video.language.displayName)")
                                .accessibilityIdentifier("strict.currentEpisode")
                        }
                    }
                    Spacer()
                    if model.request != nil, model.failure == nil {
                        HStack(spacing: 24) {
                            Button {
                                model.togglePause()
                                revealControls()
                            } label: {
                                Label(model.isPlaying ? "暂停" : "继续播放",
                                      systemImage: model.isPlaying ? "pause.fill" : "play.fill")
                            }
                            .disabled(!model.isReady)
                            .accessibilityIdentifier("strict.pause")
                            Text("已播放 \(Int(max(0, model.position))) 秒")
                                .monospacedDigit()
                                .accessibilityIdentifier("strict.position")
                        }
                    }
                }
                .font(.title3.bold())
                .buttonStyle(.bordered)
                .tint(.white)
                .padding(28)
            }
        }
        .foregroundStyle(.white)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .interactiveDismissDisabled()
        .task {
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            model.start()
            revealControls()
        }
        .onChange(of: model.isPlaying) { _, playing in
            UIApplication.shared.isIdleTimerDisabled = playing || previousIdleTimerDisabled
            if playing { revealControls() }
        }
        .onChange(of: model.shouldDismiss) { _, value in if value { dismiss() } }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.close(); dismiss() }
        }
        .onDisappear {
            hideControlsTask?.cancel()
            model.close()
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        }
    }

    private func revealControls() {
        showsControls = true
        hideControlsTask?.cancel()
        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            showsControls = false
        }
    }
}

private struct StrictVideoSurface: UIViewRepresentable {
    let player: AVPlayer

    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: Surface, context: Context) {
        uiView.playerLayer.player = player
    }

    static func dismantleUIView(_ uiView: Surface, coordinator: ()) {
        uiView.playerLayer.player = nil
    }
}
