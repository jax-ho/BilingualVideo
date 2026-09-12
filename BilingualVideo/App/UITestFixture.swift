#if DEBUG
import Foundation

@MainActor
enum UITestFixture {
    static let scheduleEditorArgument = "--ui-test-schedule-editor"

    static var isShowingScheduleEditor: Bool {
        ProcessInfo.processInfo.arguments.contains(scheduleEditorArgument)
    }

    static var isStrictPlayback: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-strict-playback")
    }

    static func makeScheduleEditorModel() -> AppModel {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("BilingualVideo-ScheduleEditorUITest", isDirectory: true)

        do {
            let preserving = ProcessInfo.processInfo.arguments.contains("--ui-test-preserve")
            if !preserving, fileManager.fileExists(atPath: rootURL.path) {
                try fileManager.removeItem(at: rootURL)
            }

            let directories = AppDirectories(
                documentsURL: rootURL.appendingPathComponent("Documents", isDirectory: true),
                applicationSupportURL: rootURL.appendingPathComponent("Application Support", isDirectory: true),
                fileManager: fileManager
            )
            try directories.prepareForLaunch()

            for pairID in [5, 20, 100] {
                for language in VideoLanguage.allCases {
                    let sample = ProcessInfo.processInfo.environment["UI_TEST_VIDEO_BASE64"]
                        .flatMap { Data(base64Encoded: $0) } ?? Data([0x00])
                    try sample.write(
                        to: directories.folderURL(for: language)
                            .appendingPathComponent("\(pairID).mp4")
                    )
                }
            }

            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "zh_CN")
            calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            let startDate = calendar.date(
                from: DateComponents(year: 2026, month: 9, day: 5, hour: 12)
            )!
            var currentDate = startDate
            let preferencesName = "BilingualVideo-ScheduleEditorUITest"
            let preferences = UserDefaults(suiteName: preferencesName)!
            if !preserving { preferences.removePersistentDomain(forName: preferencesName) }
            let model = AppModel(
                directories: directories,
                scheduleService: ScheduleService(calendar: calendar),
                preferences: preferences,
                now: { currentDate }
            )
            if preserving, model.savedPlan != nil { return model }
            model.setDailyGroupCount(3)
            if !isStrictPlayback,
               !ProcessInfo.processInfo.arguments.contains("--ui-test-viewing-settings") {
                model.setPlaybackMode(.normal)
            }
            if isStrictPlayback {
                model.setDailyGroupCount(1)
            }
            guard let plan = model.makeCandidate(startDate: startDate) else {
                fatalError("Unable to create schedule editor UI-test plan")
            }
            try model.savePlan(plan)
            if ProcessInfo.processInfo.arguments.contains("--ui-test-auto-delay") {
                model.recordPlayback(at: startDate)
                currentDate = calendar.date(byAdding: .day, value: 2, to: startDate)!
                model.refreshToday()
            }
            return model
        } catch {
            fatalError("Unable to prepare schedule editor UI-test fixture: \(error)")
        }
    }
}
#endif
