import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedVideo: PlayableVideo?
    @State private var strictRequest: StrictPlaybackRequest?
    @State private var playbackErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(appModel.currentDate.formatted(date: .complete, time: .omitted))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.muted)
                    Text("今天的放映")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                }

                content
            }
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .foregroundStyle(AppTheme.ink)
        .background(AppTheme.canvas.ignoresSafeArea())
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
        .alert("视频暂时无法播放", isPresented: Binding(
            get: { playbackErrorMessage != nil },
            set: { if !$0 { playbackErrorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {
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
                icon: emptyState.icon,
                title: emptyState.title,
                detail: emptyState.detail
            )
            .accessibilityIdentifier("today.empty")
        } else if appModel.playbackMode == .strict {
            if let pairID = unavailableStrictPairID {
                EmptyTodayView(
                    icon: "film.stack",
                    title: "视频还没有准备好",
                    detail: "编号 \(pairID) 的中英文视频需要补齐。请家长从右上角进入「家长入口」检查。"
                )
                .accessibilityIdentifier("today.strict.unavailable")
            } else {
                strictEntry
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("选一个开始，接下来会按顺序播放。")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
                ForEach(Array(appModel.todayStates.enumerated()), id: \.element.id) { index, state in
                    switch state {
                    case let .playable(pair):
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("第 \(index + 1) 组")
                                    .font(.title3.bold())
                                Text("编号 \(pair.id)")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.muted)
                            }
                            if dynamicTypeSize.isAccessibilitySize {
                                VStack(spacing: 16) { languageCards(for: pair) }
                            } else {
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 16) { languageCards(for: pair) }
                                        .frame(minWidth: 440)
                                    VStack(spacing: 16) { languageCards(for: pair) }
                                }
                            }
                        }
                        .padding(20)
                        .springSurface()
                    case let .scheduledResourceUnavailable(pairID):
                        EmptyTodayView(
                            icon: "exclamationmark.triangle",
                            title: "编号 \(pairID) 还没有准备好",
                            detail: "请家长补齐这一组的中英文视频。"
                        )
                    }
                }
            }
        }
    }

    private var strictEntry: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 24) {
                    strictIntroduction
                    strictActions
                    SpringPortrait().frame(width: 72, height: 72)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 32) {
                        SpringPortrait().frame(width: 300, height: 300)
                        VStack(alignment: .leading, spacing: 28) {
                            strictIntroduction
                            strictActions
                        }
                        .frame(minWidth: 320, maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .center, spacing: 16) {
                            SpringPortrait().frame(width: 96, height: 96)
                            strictIntroduction
                        }
                        strictActions
                    }
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .springSurface()
    }

    private var strictIntroduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今天共 \(appModel.todayStates.count) 组视频")
                .font(.system(.title, design: .rounded, weight: .bold))
            Text("每组先看中文，再看英文。")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var strictActions: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let progress = appModel.strictProgressToday, progress.hasStarted,
               progress.pairIDs.indices.contains(progress.index / 2) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("接着看：编号 \(progress.pairIDs[progress.index / 2]) · \(progress.index.isMultiple(of: 2) ? "中文" : "英文")")
                        .font(.headline)
                    Text("今天第 \(progress.index + 1) / \(progress.episodeCount) 个视频 · 已播放 \(Int(progress.position)) 秒")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("today.strict.resumeSummary")
            }
            Button {
                do { strictRequest = try appModel.beginStrictPlayback() }
                catch { playbackErrorMessage = error.localizedDescription }
            } label: {
                Label(appModel.strictProgressToday?.hasStarted == true ? "继续观看" : "开始观看",
                      systemImage: "play.fill")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(SpringPrimaryButtonStyle())
            .accessibilityIdentifier("today.strict.play")
            Text("随时暂停，回来接着看。")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
        }
    }

    private var unavailableStrictPairID: Int? {
        let progress = appModel.strictProgressToday
        let pairID: Int?
        if let progress, progress.pairIDs.indices.contains(progress.index / 2) {
            pairID = progress.pairIDs[progress.index / 2]
        } else {
            pairID = appModel.todayStates.first?.id
        }
        guard let pairID,
              let state = appModel.todayStates.first(where: { $0.id == pairID }),
              case .scheduledResourceUnavailable = state else { return nil }
        return pairID
    }

    private var emptyState: (icon: String, title: String, detail: String) {
        guard let plan = appModel.savedPlan else {
            if appModel.scanResult.pairs.isEmpty {
                return ("film.stack", "准备好视频，就可以开始了", "请家长从右上角的「家长入口」添加视频，再安排观看计划。")
            }
            return ("calendar.badge.plus", "视频已准备好", "请家长从右上角的「家长入口」安排观看计划。")
        }
        let days = appModel.scheduleService.scheduledDays(in: plan)
        let today = appModel.scheduleService.day(containing: appModel.currentDate)
        if let first = days.first, today < first,
           let date = first.date(in: appModel.scheduleService.calendar) {
            return ("calendar", "放映还没开始", "从 \(date.formatted(date: .abbreviated, time: .omitted)) 开始，到时再来吧。")
        }
        if let last = days.last, last < today {
            return ("checkmark.circle", "这一轮放映结束了", "请家长从「家长入口」安排下一轮观看。")
        }
        return ("calendar", "今天没有安排视频", "可以先休息一下，需要调整时请家长查看观看计划。")
    }

    private func languageCards(for pair: VideoPair) -> some View {
        ForEach(VideoLanguage.allCases) { language in
            VideoCard(language: language, pairID: pair.id) {
                if let video = appModel.playableVideo(pairID: pair.id, for: language) {
                    selectedVideo = video
                } else {
                    playbackErrorMessage = "这个视频还没有准备好，请让家长检查中英文视频是否齐全。"
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
            VStack(spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .accessibilityHidden(true)
                Text(language.displayName)
                    .font(.system(.title2, design: .rounded, weight: .bold))
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .padding(20)
        }
        .buttonStyle(LanguageCardStyle(language: language))
        .accessibilityLabel(language.playAccessibilityLabel)
        .accessibilityIdentifier("today.play.\(pairID).\(language.rawValue)")
        .accessibilityValue("编号 \(pairID)")
        .accessibilityHint("从这里开始播放，接下来会按顺序播放")
    }
}

private struct LanguageCardStyle: ButtonStyle {
    let language: VideoLanguage

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppTheme.ink)
            .background(language == .chinese ? AppTheme.sage : AppTheme.wheat,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AppTheme.line.opacity(0.6), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct EmptyTodayView: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
                .foregroundStyle(AppTheme.ink)
        } description: {
            Text(detail)
                .foregroundStyle(AppTheme.muted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 300)
        .springSurface()
    }
}
