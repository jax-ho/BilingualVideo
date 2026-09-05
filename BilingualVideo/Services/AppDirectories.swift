import Foundation

struct AppDirectories {
    let documentsURL: URL
    let applicationSupportURL: URL
    let fileManager: FileManager

    static var live: AppDirectories {
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory.appendingPathComponent("Documents", isDirectory: true)
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory.appendingPathComponent("Application Support", isDirectory: true)
        return AppDirectories(
            documentsURL: documents,
            applicationSupportURL: applicationSupport,
            fileManager: fileManager
        )
    }

    var chineseURL: URL {
        documentsURL.appendingPathComponent(VideoLanguage.chinese.folderName, isDirectory: true)
    }

    var englishURL: URL {
        documentsURL.appendingPathComponent(VideoLanguage.english.folderName, isDirectory: true)
    }

    var scheduleURL: URL {
        applicationSupportURL.appendingPathComponent("schedule.json", isDirectory: false)
    }

    func folderURL(for language: VideoLanguage) -> URL {
        switch language {
        case .chinese: chineseURL
        case .english: englishURL
        }
    }

    func videoURL(for pair: VideoPair, language: VideoLanguage) -> URL {
        folderURL(for: language).appendingPathComponent(pair.fileName(for: language), isDirectory: false)
    }

    func prepareForLaunch() throws {
        try createProtectedDirectory(documentsURL)
        try createProtectedDirectory(chineseURL)
        try createProtectedDirectory(englishURL)
        try createProtectedDirectory(applicationSupportURL)
    }

    private func createProtectedDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }
}
