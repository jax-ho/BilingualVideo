import SwiftUI
import AVKit

struct StudySessionView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var strictRequest: StrictPlaybackRequest?
    @State private var pdfRequest: PDFReadingRequest?
    @State private var content: StudyContent?
    @State private var errorMessage: String?
    @State private var normalSessionID = UUID()
    @State private var didStart = false
    var startingVideo: PlayableVideo? = nil

    var body: some View {
        ZStack {
            if let errorMessage {
                message(title: "学习暂时无法继续", detail: errorMessage, icon: "exclamationmark.circle")
            } else if content == .pdf, let pdfRequest {
                PDFReaderView(request: pdfRequest, appModel: appModel, onFinished: advance)
            } else if content == .video, let strictRequest {
                StrictVideoPlayerView(request: strictRequest, appModel: appModel, onFinished: advance)
                    .id(strictRequest.id)
            } else if content == .video, appModel.playbackMode == .normal {
                NormalStudyVideoView(appModel: appModel, startingVideo: startingVideo, onFinished: advance)
                    .id(normalSessionID)
            } else if content == nil, didStart {
                message(title: "今天的学习完成了", detail: "视频和 PDF 都已经学完，明天再来吧。", icon: "checkmark.seal.fill")
            } else {
                ProgressView()
            }
        }
        .background(AppTheme.canvas.ignoresSafeArea())
        .interactiveDismissDisabled()
        .task {
            guard !didStart else { return }
            didStart = true
            advance()
        }
    }

    private func advance() {
        appModel.refreshToday()
        content = appModel.nextStudyContent
        strictRequest = nil
        pdfRequest = nil
        do {
            switch content {
            case .pdf: pdfRequest = try appModel.beginPDFReading()
            case .video:
                if appModel.playbackMode == .strict { strictRequest = try appModel.beginStrictPlayback() }
                else { normalSessionID = UUID() }
            case nil: break
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func message(title: String, detail: String, icon: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: icon).font(.system(size: 52)).foregroundStyle(AppTheme.accent)
            Text(title).font(.system(.largeTitle, design: .rounded, weight: .bold))
                .accessibilityIdentifier(errorMessage == nil ? "study.finished" : "study.failure")
            Text(detail).font(.title3).foregroundStyle(AppTheme.muted)
            Button("返回首页") { dismiss() }.buttonStyle(SpringPrimaryButtonStyle())
                .accessibilityIdentifier("study.close")
        }
        .foregroundStyle(AppTheme.ink)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private final class NormalStudyVideoModel: ObservableObject {
    let session = LocalVideoPlaybackSession()
    @Published private(set) var isFinished = false
    @Published private(set) var failure: String?
    @Published private(set) var shouldDismiss = false
    private let appModel: AppModel
    private let startingVideo: PlayableVideo?
    private let day: LocalDay
    private var loadTask: Task<Void, Never>?
    private var isClosed = false

    init(appModel: AppModel, startingVideo: PlayableVideo?) {
        self.appModel = appModel
        self.startingVideo = startingVideo
        day = appModel.scheduleService.day(containing: appModel.currentDate)
        session.nextVideo = { [weak self] _ in
            guard let self, !self.isClosed else { return nil }
            return try self.appModel.nextStudyVideo()
        }
        session.onPlayback = { [weak self] _, date in self?.appModel.recordPlayback(at: date) }
        session.onEpisodeEnded = { [weak self] video in
            guard let self, !self.isClosed else { return }
            try self.appModel.recordNormalEpisodeCompletion(video, on: self.day)
            self.isFinished = self.appModel.videosFinishedToday
        }
        session.onFailure = { [weak self] message in
            self?.session.pause()
            self?.failure = message
        }
        session.onProgress = { [weak self] _, _ in
            guard let self, !self.isClosed else { return }
            if self.day != self.appModel.scheduleService.day(containing: self.appModel.currentDate) {
                self.close()
                self.shouldDismiss = true
            }
        }
    }

    func start() {
        guard loadTask == nil, !isClosed else { return }
        loadTask = Task {
            do {
                guard let video = try startingVideo ?? appModel.nextStudyVideo() else {
                    isFinished = true
                    return
                }
                try await session.prepare(video: video)
                try Task.checkCancellation()
                guard !isClosed else { return }
                session.play()
            } catch is CancellationError {
                return
            } catch { failure = error.localizedDescription }
        }
    }

    func close() {
        isClosed = true
        loadTask?.cancel()
        session.stop()
    }
}

private struct NormalStudyVideoView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: NormalStudyVideoModel
    let onFinished: () -> Void

    init(appModel: AppModel, startingVideo: PlayableVideo?, onFinished: @escaping () -> Void) {
        _model = StateObject(wrappedValue: NormalStudyVideoModel(appModel: appModel, startingVideo: startingVideo))
        self.onFinished = onFinished
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { model.close(); dismiss() } label: { Label("返回", systemImage: "chevron.backward") }
                    .accessibilityIdentifier("study.video.close")
                Spacer()
                Text("今日视频 · 普通模式").font(.headline)
            }
            .padding(20)
            .foregroundStyle(AppTheme.ink)
            NativeStudyVideoController(player: model.session.player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.canvas)
        .task { model.start() }
        .onChange(of: model.isFinished) { _, finished in if finished { onFinished() } }
        .onChange(of: model.shouldDismiss) { _, value in if value { dismiss() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.close(); dismiss() } }
        .onDisappear { model.close() }
        .alert("视频暂时无法播放", isPresented: Binding(
            get: { model.failure != nil }, set: { _ in }
        )) {
            Button("返回首页") { dismiss() }
        } message: { Text(model.failure ?? "") }
    }
}

private struct NativeStudyVideoController: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player = nil
    }
}
