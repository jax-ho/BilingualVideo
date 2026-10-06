import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var scanResult: LibraryScanResult = .empty
    @Published private(set) var savedPlan: ViewingPlan?
    @Published private(set) var todayStates: [TodayState] = []
    @Published private(set) var dailyGroupCount: Int
    @Published private(set) var playbackMode: PlaybackMode
    @Published private(set) var isNormalPlaybackLooping: Bool
    @Published private(set) var pdfScanResult = PDFLibraryScanResult()
    @Published private(set) var savedPDFPlan: ViewingPlan?
    @Published private(set) var todayPDFIDs: [Int] = []
    @Published private(set) var dailyPDFCount: Int
    @Published private(set) var learningOrder: LearningOrder
    @Published var errorMessage: String?

    let directories: AppDirectories
    let scanner: VideoLibraryScanner
    let scheduleService: ScheduleService
    let scheduleStore: ScheduleStore
    let parentAccessService: ParentAccessService
    let pdfScanner: PDFLibraryScanner
    let pdfScheduleStore: ScheduleStore

    private let now: () -> Date
    private let preferences: UserDefaults
    private static let dailyGroupCountKey = "dailyGroupCount"
    private static let playbackModeKey = "playbackMode"
    private static let normalPlaybackLoopingKey = "normalPlaybackLooping"
    private static let dailyPDFCountKey = "dailyPDFCount"
    private static let learningOrderKey = "learningOrder"
    private var midnightTimer: Timer?

    init(
        directories: AppDirectories = .live,
        scheduleService: ScheduleService = ScheduleService(),
        preferences: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.directories = directories
        self.scanner = VideoLibraryScanner(directories: directories)
        self.scheduleService = scheduleService
        self.scheduleStore = ScheduleStore(
            fileURL: directories.scheduleURL,
            fileManager: directories.fileManager
        )
        self.parentAccessService = ParentAccessService()
        self.pdfScanner = PDFLibraryScanner(directories: directories)
        self.pdfScheduleStore = ScheduleStore(fileURL: directories.pdfScheduleURL, fileManager: directories.fileManager)
        self.now = now
        self.preferences = preferences
        let storedCount = preferences.integer(forKey: Self.dailyGroupCountKey)
        self.dailyGroupCount = storedCount > 0 ? storedCount : 3
        self.playbackMode = preferences.string(forKey: Self.playbackModeKey)
            .flatMap(PlaybackMode.init(rawValue:)) ?? .strict
        self.isNormalPlaybackLooping = preferences.object(forKey: Self.normalPlaybackLoopingKey) as? Bool ?? true
        let storedPDFCount = preferences.integer(forKey: Self.dailyPDFCountKey)
        self.dailyPDFCount = storedPDFCount > 0 ? storedPDFCount : 3
        self.learningOrder = preferences.string(forKey: Self.learningOrderKey)
            .flatMap(LearningOrder.init(rawValue:)) ?? .videosFirst

        bootstrap()
    }

    var currentDate: Date { now() }

    var missingPlannedPairIDs: [Int] {
        guard let savedPlan else { return [] }
        let availableIDs = Set(scanResult.pairs.map(\.id))
        return savedPlan.orderedPairIDs.filter { !availableIDs.contains($0) }
    }

    @discardableResult
    func refreshLibrary() -> LibraryScanResult {
        let result = scanner.scan()
        scanResult = result
        return result
    }

    func makeCandidate(startDate: Date) -> ViewingPlan? {
        let result = refreshLibrary()
        guard result.isValidForGeneration else { return nil }
        return scheduleService.generate(pairs: result.pairs, startDate: startDate, now: now())
    }

    func savePlan(_ plan: ViewingPlan) throws {
        let currentDate = now()
        try settlePlan(at: currentDate)
        if let draftTracking = plan.playbackTracking,
           let savedPlan, let liveTracking = savedPlan.playbackTracking,
           draftTracking.day != liveTracking.day, !plan.hasSameSchedule(as: savedPlan) {
            throw PlanEditingError.staleDraft
        }
        var copy = plan
        copy.updatedAt = currentDate
        copy.playbackTracking = savedPlan?.playbackTracking
            ?? PlanPlaybackTracking(day: scheduleService.day(containing: currentDate), hasPlayed: false)
        copy.strictPlayback = savedPlan?.strictPlayback
        copy.normalCompletion = savedPlan?.normalCompletion
        copy = clearingChangedStrictProgress(in: copy, at: currentDate, groupCount: dailyGroupCount)
        try scheduleStore.save(copy)
        savedPlan = copy
        refreshToday()
    }

    func reloadSavedPlan() {
        do {
            savedPlan = try scheduleStore.load()
        } catch {
            savedPlan = nil
            errorMessage = "已保存的计划无法读取，文件未被覆盖。请让家长检查。"
        }
        refreshToday()
    }

    func refreshToday(at date: Date? = nil) {
        let currentDate = date ?? now()
        refreshPDFToday(at: currentDate)
        do {
            try settlePlan(at: currentDate)
        } catch {
            todayStates = []
            errorMessage = "计划更新未能保存，旧计划与播放进度仍然保留。请检查本地存储后重试。"
            return
        }
        let result = refreshLibrary()
        guard let savedPlan else {
            todayStates = []
            return
        }

        let pairIDs = scheduleService.pairIDs(
            in: savedPlan, on: currentDate, dailyGroupCount: dailyGroupCount
        )
        todayStates = pairIDs.map { pairID in
            guard let pair = result.pair(id: pairID), filesExist(for: pair) else {
                return .scheduledResourceUnavailable(pairID: pairID)
            }
            return .playable(pair)
        }
    }

    func setDailyGroupCount(_ count: Int) {
        guard count >= 1 else { return }
        let currentDate = now()
        do {
            try settlePlan(at: currentDate)
            if let savedPlan {
                let updated = clearingChangedStrictProgress(in: savedPlan, at: currentDate, groupCount: count)
                if updated != savedPlan {
                    try scheduleStore.save(updated)
                    self.savedPlan = updated
                }
            }
        } catch {
            errorMessage = "观看设置未能保存，原设置与播放进度仍然保留。请检查本地存储后重试。"
            return
        }
        preferences.set(count, forKey: Self.dailyGroupCountKey)
        dailyGroupCount = count
        refreshToday()
    }

    func setPlaybackMode(_ mode: PlaybackMode) {
        preferences.set(mode.rawValue, forKey: Self.playbackModeKey)
        playbackMode = mode
        refreshToday()
    }

    func setNormalPlaybackLooping(_ isLooping: Bool) {
        preferences.set(isLooping, forKey: Self.normalPlaybackLoopingKey)
        isNormalPlaybackLooping = isLooping
    }

    /// Called only by the actual playing-state observer, never by a card tap
    /// or successful resource lookup. Repeated playback on a day is a no-op.
    func recordPlayback(at date: Date) {
        guard let savedPlan else { return }
        let day = scheduleService.day(containing: date)
        if let tracking = savedPlan.playbackTracking {
            guard day >= tracking.day else { return }
            if day == tracking.day && tracking.hasPlayed { return }
        }
        var copy = scheduleService.settlingUnplayedDays(in: savedPlan, at: date)
        copy.playbackTracking = PlanPlaybackTracking(day: day, hasPlayed: true)
        do {
            try scheduleStore.save(copy)
            self.savedPlan = copy
            refreshToday(at: date)
        } catch {
            errorMessage = "观看记录未能保存，请检查本地存储，避免下次打开时误顺延。"
        }
    }

    private func settlePlan(at date: Date) throws {
        guard let savedPlan else { return }
        let settled = scheduleService.settlingUnplayedDays(in: savedPlan, at: date)
        let updated = clearingChangedStrictProgress(in: settled, at: date, groupCount: dailyGroupCount)
        guard updated != savedPlan else { return }
        try scheduleStore.save(updated)
        self.savedPlan = updated
    }

    private func clearingChangedStrictProgress(
        in plan: ViewingPlan, at date: Date, groupCount: Int
    ) -> ViewingPlan {
        var updated = plan
        let day = scheduleService.day(containing: date)
        let ids = scheduleService.pairIDs(in: plan, on: date, dailyGroupCount: groupCount)
        if let progress = plan.strictPlayback, progress.day == day, progress.pairIDs != ids {
            updated.strictPlayback = nil
        }
        if let completion = plan.normalCompletion, completion.day == day, completion.pairIDs != ids {
            updated.normalCompletion = nil
        }
        // Keep playbackTracking: real playback still counts for automatic delay.
        return updated
    }

    func nextVideo(after video: PlayableVideo) throws -> PlayableVideo? {
        refreshToday()
        switch playbackMode {
        case .strict:
            // Strict completion must use its day/index ticket, never a card ID.
            return nil
        case .normal:
            guard let currentIndex = todayStates.firstIndex(where: { $0.id == video.pairID }) else {
                return nil
            }
            let nextState: TodayState
            let nextLanguage: VideoLanguage
            switch video.language {
            case .chinese:
                nextState = todayStates[currentIndex]
                nextLanguage = .english
            case .english:
                let nextIndex = currentIndex + 1
                if nextIndex < todayStates.count {
                    nextState = todayStates[nextIndex]
                } else if isNormalPlaybackLooping, let firstState = todayStates.first {
                    nextState = firstState
                } else {
                    return nil
                }
                nextLanguage = .chinese
            }
            guard case let .playable(pair) = nextState else {
                throw PlaybackSequenceError.unavailablePair(nextState.id)
            }
            return PlayableVideo(
                pairID: pair.id,
                language: nextLanguage,
                url: directories.videoURL(for: pair, language: nextLanguage)
            )
        }
    }

    func playableVideo(pairID: Int, for language: VideoLanguage) -> PlayableVideo? {
        guard playbackMode == .normal else { return nil }
        refreshToday()
        guard let state = todayStates.first(where: { $0.id == pairID }),
              case let .playable(pair) = state else { return nil }
        let url = directories.videoURL(for: pair, language: language)
        guard directories.fileManager.fileExists(atPath: url.path) else {
            refreshToday()
            return nil
        }
        return PlayableVideo(pairID: pair.id, language: language, url: url)
    }

    var strictProgressToday: StrictPlaybackProgress? {
        guard let progress = savedPlan?.strictPlayback,
              progress.day == scheduleService.day(containing: now()) else { return nil }
        return progress
    }

    var canResetTodayPlaybackProgress: Bool {
        guard let progress = strictProgressToday else { return false }
        return progress.hasStarted || progress.index > 0 || progress.position > 0
    }

    func resetTodayPlaybackProgress() throws {
        try settlePlan(at: now())
        guard canResetTodayPlaybackProgress, var plan = savedPlan else { return }
        plan.strictPlayback = nil
        // Keep the schedule and actual-playback history used by automatic delay.
        try scheduleStore.save(plan)
        savedPlan = plan
        refreshToday()
    }

    func beginStrictPlayback() throws -> StrictPlaybackRequest? {
        guard playbackMode == .strict else { throw StrictPlaybackError.expired }
        let currentDate = now()
        // Do not continue using stale in-memory data if reconciliation cannot save.
        try settlePlan(at: currentDate)
        refreshToday(at: currentDate)
        guard var plan = savedPlan else { return nil }
        let day = scheduleService.day(containing: currentDate)
        if let progress = plan.strictPlayback, progress.day > day {
            throw StrictPlaybackError.expired
        }
        if plan.strictPlayback?.day != day {
            guard !todayStates.isEmpty else { return nil }
            plan.strictPlayback = StrictPlaybackProgress(day: day, pairIDs: todayStates.map(\.id))
            try scheduleStore.save(plan)
            savedPlan = plan
        }
        return try strictRequest(for: plan.strictPlayback!)
    }

    func saveStrictProgress(
        _ request: StrictPlaybackRequest, seconds: Double, hasPlayed: Bool = false
    ) throws {
        var plan = try strictPlan(matching: request)
        guard seconds.isFinite, seconds >= 0 else { throw StrictPlaybackError.invalidProgress }
        plan.strictPlayback!.position = max(plan.strictPlayback!.position, seconds)
        if hasPlayed {
            plan.strictPlayback!.hasStarted = true
            plan.playbackTracking = PlanPlaybackTracking(day: request.day, hasPlayed: true)
        }
        guard plan != savedPlan else { return }
        try scheduleStore.save(plan)
        savedPlan = plan
    }

    /// Called only after AVPlayer reports a natural end. Commit before loading
    /// the next file, so a failed load or app exit cannot replay the prior item.
    func finishStrictEpisode(_ request: StrictPlaybackRequest) throws -> StrictPlaybackRequest? {
        var plan = try strictPlan(matching: request)
        plan.strictPlayback!.index += 1
        plan.strictPlayback!.position = 0
        plan.strictPlayback!.hasStarted = true
        plan.playbackTracking = PlanPlaybackTracking(day: request.day, hasPlayed: true)
        try scheduleStore.save(plan)
        savedPlan = plan
        return try strictRequest(for: plan.strictPlayback!)
    }

    func isCurrentStrictRequest(_ request: StrictPlaybackRequest) -> Bool {
        (try? strictPlan(matching: request)) != nil
    }

    private func strictPlan(matching request: StrictPlaybackRequest) throws -> ViewingPlan {
        guard playbackMode == .strict,
              request.day == scheduleService.day(containing: now()),
              let plan = savedPlan, let progress = plan.strictPlayback,
              progress.day == request.day, progress.index == request.index,
              progress.sessionID == request.sessionID,
              !progress.isFinished,
              progress.pairIDs[progress.index / 2] == request.video.pairID,
              request.video.language == (progress.index.isMultiple(of: 2) ? .chinese : .english) else {
            throw StrictPlaybackError.expired
        }
        return plan
    }

    private func strictRequest(for progress: StrictPlaybackProgress) throws -> StrictPlaybackRequest? {
        guard !progress.isFinished else { return nil }
        let pairID = progress.pairIDs[progress.index / 2]
        let language: VideoLanguage = progress.index.isMultiple(of: 2) ? .chinese : .english
        guard let pair = refreshLibrary().pair(id: pairID), filesExist(for: pair) else {
            throw PlaybackSequenceError.unavailablePair(pairID)
        }
        return StrictPlaybackRequest(
            day: progress.day, index: progress.index, sessionID: progress.sessionID,
            video: PlayableVideo(pairID: pairID, language: language,
                                 url: directories.videoURL(for: pair, language: language)),
            position: progress.position, episodeCount: progress.episodeCount
        )
    }

    func activate() {
        refreshToday()
        scheduleMidnightRefresh()
    }

    func deactivate() {
        midnightTimer?.invalidate()
        midnightTimer = nil
    }

    private func bootstrap() {
        do {
            try directories.prepareForLaunch()
            savedPlan = try scheduleStore.load()
        } catch {
            errorMessage = "App 初始化失败，请让家长检查本地存储。"
        }
        do {
            savedPDFPlan = try pdfScheduleStore.load()
        } catch {
            errorMessage = "PDF 计划无法读取，文件未被覆盖。请让家长检查。"
        }
        refreshToday()
    }

    private func filesExist(for pair: VideoPair) -> Bool {
        VideoLanguage.allCases.allSatisfy { language in
            directories.fileManager.fileExists(
                atPath: directories.videoURL(for: pair, language: language).path
            )
        }
    }

    private func scheduleMidnightRefresh() {
        midnightTimer?.invalidate()
        let calendar = scheduleService.calendar
        let currentDate = now()
        let startOfToday = calendar.startOfDay(for: currentDate)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return }
        let delay = max(nextDay.timeIntervalSince(currentDate) + 1, 1)

        midnightTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refreshToday()
                self?.scheduleMidnightRefresh()
            }
        }
    }
}

extension AppModel {
    var pdfProgressToday: PDFReadingProgress? {
        guard let progress = savedPDFPlan?.pdfReading,
              progress.day == scheduleService.day(containing: now()) else { return nil }
        return progress
    }

    var missingPlannedPDFIDs: [Int] {
        let available = Set(pdfScanResult.books.map(\.id))
        return savedPDFPlan?.orderedPairIDs.filter { !available.contains($0) } ?? []
    }

    @discardableResult
    func refreshPDFLibrary() -> PDFLibraryScanResult {
        pdfScanResult = pdfScanner.scan()
        return pdfScanResult
    }

    func makePDFCandidate(startDate: Date) -> ViewingPlan? {
        let result = refreshPDFLibrary()
        guard result.isValidForGeneration else { return nil }
        return scheduleService.generate(identifiers: result.books.map(\.id), startDate: startDate, now: now())
    }

    func savePDFPlan(_ plan: ViewingPlan) throws {
        let date = now()
        try settlePDFPlan(at: date)
        if let tracking = plan.playbackTracking, let savedPDFPlan,
           let live = savedPDFPlan.playbackTracking, tracking.day != live.day,
           !plan.hasSameSchedule(as: savedPDFPlan) {
            throw PlanEditingError.staleDraft
        }
        var copy = plan
        copy.updatedAt = date
        copy.playbackTracking = savedPDFPlan?.playbackTracking
            ?? PlanPlaybackTracking(day: scheduleService.day(containing: date), hasPlayed: false)
        copy.pdfReading = savedPDFPlan?.pdfReading
        copy.strictPlayback = nil
        copy.normalCompletion = nil
        copy = clearingChangedPDFProgress(in: copy, at: date, count: dailyPDFCount)
        try pdfScheduleStore.save(copy)
        savedPDFPlan = copy
        refreshPDFToday(at: date)
    }

    func setDailyPDFCount(_ count: Int) {
        guard count >= 1 else { return }
        do {
            try settlePDFPlan(at: now())
            if let savedPDFPlan {
                let copy = clearingChangedPDFProgress(in: savedPDFPlan, at: now(), count: count)
                if copy != savedPDFPlan {
                    try pdfScheduleStore.save(copy)
                    self.savedPDFPlan = copy
                }
            }
            preferences.set(count, forKey: Self.dailyPDFCountKey)
            dailyPDFCount = count
            refreshPDFToday(at: now())
        } catch {
            errorMessage = "PDF 设置未能保存，原设置与阅读进度仍然保留。"
        }
    }

    func setLearningOrder(_ order: LearningOrder) {
        preferences.set(order.rawValue, forKey: Self.learningOrderKey)
        learningOrder = order
    }

    func beginPDFReading() throws -> PDFReadingRequest? {
        let date = now()
        try settlePDFPlan(at: date)
        refreshPDFLibrary()
        guard var plan = savedPDFPlan else { return nil }
        let day = scheduleService.day(containing: date)
        if let progress = plan.pdfReading, progress.day > day { throw PDFReadingError.expired }
        if plan.pdfReading?.day != day {
            let ids = scheduleService.pairIDs(in: plan, on: date, dailyGroupCount: dailyPDFCount)
            guard !ids.isEmpty else { return nil }
            plan.pdfReading = PDFReadingProgress(day: day, bookIDs: ids, sessionID: UUID())
            try pdfScheduleStore.save(plan)
            savedPDFPlan = plan
        }
        return try pdfRequest(for: plan.pdfReading!)
    }

    /// Rendering a page counts as actual reading; loading or a failed open does not.
    func savePDFPage(_ request: PDFReadingRequest, pageIndex: Int, pageCount: Int) throws {
        var plan = try pdfPlan(matching: request)
        guard pageCount > 0, (0..<pageCount).contains(pageIndex) else { throw PDFReadingError.invalidPage }
        plan.pdfReading!.pageIndex = pageIndex
        plan.pdfReading!.pageCount = pageCount
        plan.pdfReading!.hasStarted = true
        plan.playbackTracking = PlanPlaybackTracking(day: request.day, hasPlayed: true)
        guard plan != savedPDFPlan else { return }
        try pdfScheduleStore.save(plan)
        savedPDFPlan = plan
    }

    func finishPDFReading(_ request: PDFReadingRequest) throws -> PDFReadingRequest? {
        var plan = try pdfPlan(matching: request)
        let progress = plan.pdfReading!
        guard progress.pageCount > 0, progress.pageIndex == progress.pageCount - 1 else {
            throw PDFReadingError.invalidPage
        }
        plan.pdfReading!.index += 1
        plan.pdfReading!.pageIndex = 0
        plan.pdfReading!.pageCount = 0
        try pdfScheduleStore.save(plan)
        savedPDFPlan = plan
        return try pdfRequest(for: plan.pdfReading!)
    }

    func isCurrentPDFRequest(_ request: PDFReadingRequest) -> Bool {
        (try? pdfPlan(matching: request)) != nil
    }

    var canResetTodayPDFProgress: Bool { pdfProgressToday?.hasStarted == true }

    func resetTodayPDFProgress() throws {
        try settlePDFPlan(at: now())
        guard canResetTodayPDFProgress, var plan = savedPDFPlan else { return }
        plan.pdfReading = nil
        try pdfScheduleStore.save(plan)
        savedPDFPlan = plan
        refreshPDFToday(at: now())
    }

    var videosFinishedToday: Bool {
        let ids = savedPlan.map { scheduleService.pairIDs(in: $0, on: now(), dailyGroupCount: dailyGroupCount) } ?? []
        if ids.isEmpty { return true }
        if playbackMode == .strict { return strictProgressToday?.isFinished == true }
        return savedPlan?.normalCompletion?.day == scheduleService.day(containing: now())
            && savedPlan?.normalCompletion?.isFinished == true
    }

    var nextStudyContent: StudyContent? {
        let pdfIDs = savedPDFPlan.map { scheduleService.pairIDs(in: $0, on: now(), dailyGroupCount: dailyPDFCount) } ?? []
        return learningOrder.contents.first {
            $0 == .video ? !videosFinishedToday : !pdfIDs.isEmpty && pdfProgressToday?.isFinished != true
        }
    }

    func recordNormalEpisodeCompletion(_ video: PlayableVideo, on day: LocalDay) throws {
        guard playbackMode == .normal, day == scheduleService.day(containing: now()),
              var plan = savedPlan else { throw StrictPlaybackError.expired }
        let ids = scheduleService.pairIDs(in: plan, on: now(), dailyGroupCount: dailyGroupCount)
        guard ids.contains(video.pairID) else { throw StrictPlaybackError.expired }
        if plan.normalCompletion?.day != day || plan.normalCompletion?.pairIDs != ids {
            plan.normalCompletion = NormalVideoCompletion(day: day, pairIDs: ids)
        }
        if plan.normalCompletion!.completedVideoIDs.contains(video.id) { return }
        plan.normalCompletion!.completedVideoIDs.append(video.id)
        try scheduleStore.save(plan)
        savedPlan = plan
    }

    func nextStudyVideo() throws -> PlayableVideo? {
        refreshToday()
        guard !videosFinishedToday else { return nil }
        guard let plan = savedPlan,
              todayStates.map(\.id) == scheduleService.pairIDs(in: plan, on: now(), dailyGroupCount: dailyGroupCount) else {
            throw StrictPlaybackError.invalidProgress
        }
        let completed = savedPlan?.normalCompletion?.day == scheduleService.day(containing: now())
            ? savedPlan?.normalCompletion?.completedVideoIDs ?? [] : []
        for state in todayStates {
            for language in VideoLanguage.allCases where !completed.contains("\(state.id)-\(language.rawValue)") {
                guard case let .playable(pair) = state else {
                    throw PlaybackSequenceError.unavailablePair(state.id)
                }
                return PlayableVideo(pairID: pair.id, language: language,
                                     url: directories.videoURL(for: pair, language: language))
            }
        }
        return nil
    }

    private func refreshPDFToday(at date: Date) {
        do {
            try settlePDFPlan(at: date)
            refreshPDFLibrary()
            todayPDFIDs = savedPDFPlan.map {
                scheduleService.pairIDs(in: $0, on: date, dailyGroupCount: dailyPDFCount)
            } ?? []
        } catch {
            todayPDFIDs = []
            errorMessage = "PDF 计划更新未能保存，原计划与阅读进度仍然保留。"
        }
    }

    private func settlePDFPlan(at date: Date) throws {
        guard let savedPDFPlan else { return }
        let settled = scheduleService.settlingUnplayedDays(in: savedPDFPlan, at: date)
        let copy = clearingChangedPDFProgress(in: settled, at: date, count: dailyPDFCount)
        guard copy != savedPDFPlan else { return }
        try pdfScheduleStore.save(copy)
        self.savedPDFPlan = copy
    }

    private func clearingChangedPDFProgress(in plan: ViewingPlan, at date: Date, count: Int) -> ViewingPlan {
        guard let progress = plan.pdfReading, progress.day == scheduleService.day(containing: date),
              progress.bookIDs != scheduleService.pairIDs(in: plan, on: date, dailyGroupCount: count) else { return plan }
        var copy = plan
        copy.pdfReading = nil
        return copy
    }

    private func pdfPlan(matching request: PDFReadingRequest) throws -> ViewingPlan {
        guard request.day == scheduleService.day(containing: now()),
              let plan = savedPDFPlan, let progress = plan.pdfReading,
              progress.day == request.day, progress.sessionID == request.sessionID,
              progress.index == request.index, !progress.isFinished,
              progress.bookIDs[progress.index] == request.book.id else { throw PDFReadingError.expired }
        return plan
    }

    private func pdfRequest(for progress: PDFReadingProgress) throws -> PDFReadingRequest? {
        guard !progress.isFinished else { return nil }
        let id = progress.bookIDs[progress.index]
        guard let book = refreshPDFLibrary().book(id: id) else { throw PDFReadingError.unavailable(id) }
        return PDFReadingRequest(day: progress.day, index: progress.index, sessionID: progress.sessionID,
                                 book: book, url: directories.razURL.appendingPathComponent(book.fileName),
                                 pageIndex: progress.pageIndex, bookCount: progress.bookIDs.count)
    }
}
