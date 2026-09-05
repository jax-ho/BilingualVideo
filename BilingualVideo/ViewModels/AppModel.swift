import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var scanResult: LibraryScanResult = .empty
    @Published private(set) var savedPlan: ViewingPlan?
    @Published private(set) var todayState: TodayState = .noScheduledItem
    @Published var errorMessage: String?

    let directories: AppDirectories
    let scanner: VideoLibraryScanner
    let scheduleService: ScheduleService
    let scheduleStore: ScheduleStore
    let parentAccessService: ParentAccessService

    private let now: () -> Date
    private var midnightTimer: Timer?

    init(
        directories: AppDirectories = .live,
        scheduleService: ScheduleService = ScheduleService(),
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
        self.now = now

        bootstrap()
    }

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
        var copy = plan
        copy.updatedAt = now()
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
        let result = refreshLibrary()
        guard let savedPlan,
              let pairID = scheduleService.pairID(in: savedPlan, on: currentDate) else {
            todayState = .noScheduledItem
            return
        }

        guard let pair = result.pair(id: pairID), filesExist(for: pair) else {
            todayState = .scheduledResourceUnavailable(pairID: pairID)
            return
        }
        todayState = .playable(pair)
    }

    func playableVideo(for language: VideoLanguage) -> PlayableVideo? {
        refreshToday()
        guard case let .playable(pair) = todayState else { return nil }
        let url = directories.videoURL(for: pair, language: language)
        guard directories.fileManager.fileExists(atPath: url.path) else {
            todayState = .scheduledResourceUnavailable(pairID: pair.id)
            return nil
        }
        return PlayableVideo(pairID: pair.id, language: language, url: url)
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
