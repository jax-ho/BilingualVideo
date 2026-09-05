import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedVideo: PlayableVideo?
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
        .background {
            NativeVideoPlayerPresenter(
                video: $selectedVideo,
                scenePhase: scenePhase,
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
        switch appModel.todayState {
        case let .playable(pair):
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 24)], spacing: 24) {
                VideoCard(language: .chinese, pairID: pair.id) {
                    selectedVideo = appModel.playableVideo(for: .chinese)
                }
                VideoCard(language: .english, pairID: pair.id) {
                    selectedVideo = appModel.playableVideo(for: .english)
                }
            }

        case .noScheduledItem:
            EmptyTodayView(
                icon: "calendar.badge.minus",
                title: "今天没有可播放的视频",
                detail: "请让家长检查观看计划。"
            )

        case let .scheduledResourceUnavailable(pairID):
            EmptyTodayView(
                icon: "exclamationmark.triangle",
                title: "今天的视频暂不可用",
                detail: "编号 \(pairID) 的中英文资源不完整，请让家长检查。"
            )
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
