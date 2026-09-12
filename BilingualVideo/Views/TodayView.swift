import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedVideo: PlayableVideo?
    @State private var strictRequest: StrictPlaybackRequest?
    @State private var playbackErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("今天看什么？")
                        .font(.largeTitle.bold())
                    Text(Date.now.formatted(date: .complete, time: .omitted))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 32)

                content
                    .frame(maxWidth: 900)

                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
        }
        .background {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.12), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .navigationTitle("放牛班的春天")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $strictRequest, onDismiss: { appModel.refreshToday() }) { request in
            StrictVideoPlayerView(request: request, appModel: appModel)
        }
        .background {
            NativeVideoPlayerPresenter(
                video: $selectedVideo,
                scenePhase: scenePhase,
                nextVideo: { try appModel.nextVideo(after: $0) },
                onPlayback: { _, date in appModel.recordPlayback(at: date) },
                onDismiss: { appModel.refreshToday() },
                onFailure: { playbackErrorMessage = $0 }
            )
            .frame(width: 0, height: 0)
        }
        .alert("播放失败", isPresented: Binding(
            get: { playbackErrorMessage != nil },
            set: { if !$0 { playbackErrorMessage = nil } }
        )) {
            Button("好", role: .cancel) {
                playbackErrorMessage = nil
            }
        } message: {
            Text(playbackErrorMessage ?? "请让家长检查今天的视频资源。")
        }
    }

    @ViewBuilder
    private var content: some View {
        if appModel.playbackMode == .strict, appModel.strictProgressToday?.isFinished == true {
            EmptyTodayView(
                icon: "checkmark.seal.fill",
                title: "今天的视频已经播放完毕",
                detail: "明天再来吧。"
            )
            .accessibilityIdentifier("today.strict.finished")
        } else if appModel.todayStates.isEmpty {
            EmptyTodayView(
                icon: "calendar.badge.minus",
                title: "今天没有可播放的视频",
                detail: "请让家长检查观看计划。"
            )

        } else if appModel.playbackMode == .strict {
            VStack(spacing: 20) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 64))
                Text("今天共 \(appModel.todayStates.count) 组视频")
                    .font(.title2.bold())
                Text("按顺序播放，可以暂停，退出后继续观看。")
                    .foregroundStyle(.secondary)
                Button {
                    do { strictRequest = try appModel.beginStrictPlayback() }
                    catch { playbackErrorMessage = error.localizedDescription }
                } label: {
                    Label(appModel.strictProgressToday?.hasStarted == true ? "继续观看" : "开始观看",
                          systemImage: "play.fill")
                        .font(.title2.bold())
                        .padding(16)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("today.strict.play")
            }
            .frame(maxWidth: .infinity, minHeight: 360)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28))
        } else {
            LazyVStack(spacing: 28) {
                ForEach(appModel.todayStates) { state in
                    switch state {
                    case let .playable(pair):
                        VStack(alignment: .leading, spacing: 12) {
                            Text("编号 \(pair.id)")
                                .font(.title2.bold())
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 24)], spacing: 24) {
                                ForEach(VideoLanguage.allCases) { language in
                                    VideoCard(language: language, pairID: pair.id) {
                                        selectedVideo = appModel.playableVideo(pairID: pair.id, for: language)
                                    }
                                }
                            }
                        }
                    case let .scheduledResourceUnavailable(pairID):
                        EmptyTodayView(
                            icon: "exclamationmark.triangle",
                            title: "编号 \(pairID) 暂不可用",
                            detail: "中英文资源不完整，请让家长检查。"
                        )
                    }
                }
            }
        }
    }
}

private struct VideoCard: View {
    let language: VideoLanguage
    let pairID: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 18) {
                Image(systemName: language == .chinese ? "character.book.closed.fill.zh" : "text.book.closed.fill")
                    .font(.system(size: 58, weight: .semibold))
                Text(language.displayName)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("视频编号 \(pairID)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Label("点这里播放", systemImage: "play.circle.fill")
                    .font(.title3.bold())
            }
            .frame(maxWidth: .infinity, minHeight: 290)
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.24), lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.playAccessibilityLabel)
        .accessibilityIdentifier("today.play.\(pairID).\(language.rawValue)")
        .accessibilityValue("编号 \(pairID)")
        .accessibilityHint("打开全屏播放器，可不限次数重播")
    }
}

private struct EmptyTodayView: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(detail)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
