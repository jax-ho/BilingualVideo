#if DEBUG
import Foundation

@MainActor
enum UITestFixture {
    static let scheduleEditorArgument = "--ui-test-schedule-editor"

    static var isShowingScheduleEditor: Bool {
        ProcessInfo.processInfo.arguments.contains(scheduleEditorArgument)
    }

    static func makeScheduleEditorModel() -> AppModel {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("BilingualVideo-ScheduleEditorUITest", isDirectory: true)

        do {
            if fileManager.fileExists(atPath: rootURL.path) {
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
                    try Data([0x00]).write(
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
            let model = AppModel(
                directories: directories,
                scheduleService: ScheduleService(calendar: calendar),
                now: { startDate }
            )
            guard let plan = model.makeCandidate(startDate: startDate) else {
                fatalError("Unable to create schedule editor UI-test plan")
            }
            try model.savePlan(plan)
            return model
        } catch {
            fatalError("Unable to prepare schedule editor UI-test fixture: \(error)")
        }
    }
}
#endif
