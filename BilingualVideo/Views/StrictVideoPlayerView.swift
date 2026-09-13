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
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                messageScreen(
                    title: "今天的视频已经播放完毕",
                    detail: "今天就看到这里，明天再来吧。",
                    icon: "checkmark.circle",
                    identifier: "strict.finished"
                )
            } else if let failure = model.failure {
                messageScreen(
                    title: "视频暂时无法播放",
                    detail: "\(failure)\n\n请返回首页，让家长帮忙检查。",
                    icon: "exclamationmark.circle",
                    identifier: "strict.failure"
                )
            } else {
                StrictVideoSurface(player: model.session.player)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { revealControls() }
                    .accessibilityLabel("视频画面")
                    .accessibilityIdentifier("strict.surface")
                    .accessibilityAction(named: "显示播放控制") { revealControls() }
                if !model.isReady { ProgressView().tint(.white) }

                if showsControls || isVoiceOverEnabled || !model.isPlaying {
                    controlsOverlay
                }
            }
        }
        .foregroundStyle(.white)
        .font(.title3.bold())
        .buttonStyle(.bordered)
        .tint(.white)
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
        .onChange(of: isVoiceOverEnabled) { _, _ in revealControls() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.close(); dismiss() }
        }
        .onDisappear {
            hideControlsTask?.cancel()
            model.close()
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        }
    }

    private var headerControls: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button {
                        model.close()
                        dismiss()
                    } label: { Label("返回", systemImage: "chevron.backward") }
                    .accessibilityIdentifier("strict.close")
                    Spacer()
                    if model.failure == nil, !model.isFinished {
                        Text("进度会自动保留")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                if let request = model.request {
                    Text("第 \(request.index + 1) / \(request.episodeCount) 集 · 编号 \(request.video.pairID) · \(request.video.language.displayName)")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("strict.currentEpisode")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 12)
            .background(Color.black.opacity(0.82).ignoresSafeArea(edges: .top))
            LinearGradient(
                colors: [.black.opacity(0.82), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 28)
            .allowsHitTesting(false)
        }
    }

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            headerControls
            Spacer(minLength: 24)
            if model.request != nil {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.82)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 28)
                    .allowsHitTesting(false)
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(spacing: 16) { playbackControls }
                        } else {
                            HStack(spacing: 24) { playbackControls }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                    .background(Color.black.opacity(0.82).ignoresSafeArea(edges: .bottom))
                }
            }
        }
    }

    private func messageScreen(title: String, detail: String, icon: String, identifier: String) -> some View {
        VStack(spacing: 0) {
            headerControls
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 20) {
                        Image(systemName: icon)
                            .font(.system(size: 52))
                            .accessibilityHidden(true)
                        Text(title)
                            .font(.largeTitle.bold())
                            .accessibilityIdentifier(identifier)
                        Text(detail)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 680)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    @ViewBuilder
    private var playbackControls: some View {
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

    private func revealControls() {
        showsControls = true
        hideControlsTask?.cancel()
        guard !isVoiceOverEnabled else { return }
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
