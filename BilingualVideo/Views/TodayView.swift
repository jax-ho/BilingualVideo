import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedVideo: PlayableVideo?
    @State private var strictRequest: StrictPlaybackRequest?
    @State private var playbackErrorMessage: String?
    @State private var isShowingStudySession = false
    @State private var startingStudyVideo: PlayableVideo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(appModel.currentDate.formatted(date: .complete, time: .omitted))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.muted)
                    Text(appModel.savedPDFPlan == nil ? "今天的放映" : "今天的学习")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                }

                if !appModel.todayPDFIDs.isEmpty { studyEntry }
                else { content }
                if appModel.todayPDFIDs.isEmpty, appModel.savedPDFPlan != nil {
                    Text("今天没有安排 PDF。需要调整时，请家长查看 PDF 计划。")
                        .font(.subheadline).foregroundStyle(AppTheme.muted)
                }
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
        .fullScreenCover(isPresented: $isShowingStudySession, onDismiss: { appModel.refreshToday() }) {
            StudySessionView(startingVideo: startingStudyVideo).environmentObject(appModel)
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

    private var studyEntry: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 20) {
                SpringPortrait().frame(width: 100, height: 100)
                VStack(alignment: .leading, spacing: 8) {
                    Text("今天共 \(appModel.todayStates.count) 组视频 · \(appModel.todayPDFIDs.count) 份 PDF")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text(appModel.learningOrder.displayName).font(.subheadline).foregroundStyle(AppTheme.muted)
                }
            }
            ForEach(appModel.learningOrder.contents) { content in
                HStack(spacing: 12) {
                    let finished = content == .video ? appModel.videosFinishedToday : appModel.pdfProgressToday?.isFinished == true
                    Image(systemName: finished ? "checkmark.circle.fill" : content == .video ? "play.circle" : "book.closed")
                        .font(.title2).foregroundStyle(AppTheme.accent)
                    Text(content.displayName).font(.headline)
                    Spacer()
                    if finished { Text("已完成").foregroundStyle(AppTheme.accent) }
                    else if content == .pdf, let progress = appModel.pdfProgressToday, progress.hasStarted {
                        Text("第 \(progress.index + 1) 份 · 第 \(progress.pageIndex + 1) 页").foregroundStyle(AppTheme.muted)
                    } else if content == .video, let progress = appModel.strictProgressToday, progress.hasStarted {
                        Text("第 \(progress.index + 1) / \(progress.episodeCount) 集").foregroundStyle(AppTheme.muted)
                    } else if content == .video, appModel.playbackMode == .normal,
                              let progress = appModel.savedPlan?.normalCompletion,
                              progress.day == appModel.scheduleService.day(containing: appModel.currentDate) {
                        Text("已看 \(progress.completedVideoIDs.count) / \(progress.videoIDs.count) 集").foregroundStyle(AppTheme.muted)
                    } else { Text("待学习").foregroundStyle(AppTheme.muted) }
                }
            }
            if appModel.nextStudyContent != nil {
                Button { startingStudyVideo = nil; isShowingStudySession = true } label: {
                    Label(hasStartedStudyToday ? "继续学习" : "开始学习",
                          systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SpringPrimaryButtonStyle())
                .accessibilityIdentifier("today.study.start")
                Text("随时返回，下次接着学。PDF 读到最后一页，点“结束观看”完成这份学习。")
                    .font(.subheadline).foregroundStyle(AppTheme.muted)
                if appModel.playbackMode == .normal, appModel.nextStudyContent == .video {
                    Text("也可以选择今天的视频开始播放。").font(.subheadline).foregroundStyle(AppTheme.muted)
                    ForEach(appModel.todayStates) { state in
                        if case let .playable(pair) = state {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("编号 \(pair.id)").font(.headline)
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 16) { languageCards(for: pair) }.frame(minWidth: 440)
                                    VStack(spacing: 16) { languageCards(for: pair) }
                                }
                            }
                        }
                    }
                }
            } else {
                Text("今天的学习完成了，明天再来吧。")
                    .font(.title3.bold()).foregroundStyle(AppTheme.accent)
                    .accessibilityIdentifier("today.study.finished")
            }
        }
        .padding(28)
        .springSurface()
    }

    private var hasStartedStudyToday: Bool {
        if appModel.pdfProgressToday?.hasStarted == true || appModel.strictProgressToday?.hasStarted == true { return true }
        guard let tracking = appModel.savedPlan?.playbackTracking else { return false }
        return tracking.day == appModel.scheduleService.day(containing: appModel.currentDate) && tracking.hasPlayed
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
                    if !appModel.todayPDFIDs.isEmpty {
                        startingStudyVideo = video
                        isShowingStudySession = true
                    } else { selectedVideo = video }
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
