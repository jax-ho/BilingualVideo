import Foundation

final class VideoLibraryScanner {
    private struct IndexedFile {
        let id: Int
        let fileName: String
    }

    private struct DirectoryScan {
        var filesByID: [Int: IndexedFile] = [:]
        var fileNamesByID: [Int: [String]] = [:]
        var allParsedIDs: Set<Int> = []
        var ambiguousIDs: Set<Int> = []
        var issues: [LibraryValidationIssue] = []
        var directoryExists = true
        var directoryReadable = true
    }

    private let directories: AppDirectories
    private let fileManager: FileManager

    init(directories: AppDirectories) {
        self.directories = directories
        self.fileManager = directories.fileManager
    }

    func scan() -> LibraryScanResult {
        let chinese = scanDirectory(language: .chinese)
        let english = scanDirectory(language: .english)
        var issues = chinese.issues + english.issues

        if chinese.directoryExists, chinese.directoryReadable,
           english.directoryExists, english.directoryReadable {
            let chineseIDs = chinese.allParsedIDs
            let englishIDs = english.allParsedIDs

            let missingEnglish = chineseIDs.subtracting(englishIDs).sorted()
            let missingChinese = englishIDs.subtracting(chineseIDs).sorted()

            for id in missingEnglish {
                let fileNames = chinese.fileNamesByID[id] ?? ["\(id).mp4"]
                issues.append(LibraryValidationIssue(
                    kind: .unmatchedIdentifier,
                    message: "编号 \(id) 缺少英文视频",
                    relatedFiles: fileNames.map { "Chinese/\($0)" }.sorted()
                ))
            }

            for id in missingChinese {
                let fileNames = english.fileNamesByID[id] ?? ["\(id).mp4"]
                issues.append(LibraryValidationIssue(
                    kind: .unmatchedIdentifier,
                    message: "编号 \(id) 缺少中文视频",
                    relatedFiles: fileNames.map { "English/\($0)" }.sorted()
                ))
            }
        }

        let usableIDs = Set(chinese.filesByID.keys)
            .intersection(english.filesByID.keys)
            .subtracting(chinese.ambiguousIDs)
            .subtracting(english.ambiguousIDs)
            .sorted()

        let pairs = usableIDs.compactMap { id -> VideoPair? in
            guard let chineseFile = chinese.filesByID[id],
                  let englishFile = english.filesByID[id] else {
                return nil
            }
            return VideoPair(
                id: id,
                chineseFileName: chineseFile.fileName,
                englishFileName: englishFile.fileName
            )
        }

        if chinese.directoryExists, chinese.directoryReadable,
           english.directoryExists, english.directoryReadable,
           pairs.isEmpty, issues.isEmpty {
            issues.append(LibraryValidationIssue(
                kind: .emptyLibrary,
                message: "至少需要一组编号相同的中英文 MP4 视频",
                relatedFiles: []
            ))
        }

        return LibraryScanResult(pairs: pairs, issues: stableSort(issues))
    }

    private func scanDirectory(language: VideoLanguage) -> DirectoryScan {
        let folderURL = directories.folderURL(for: language)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return DirectoryScan(
                issues: [LibraryValidationIssue(
                    kind: .missingDirectory,
                    message: "缺少 \(language.folderName) 文件夹",
                    relatedFiles: [language.folderName]
                )],
                directoryExists: false,
                directoryReadable: false
            )
        }

        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isHiddenKey, .isRegularFileKey],
                options: []
            )
        } catch {
            return DirectoryScan(
                issues: [LibraryValidationIssue(
                    kind: .unsupportedItem,
                    message: "无法读取 \(language.folderName) 文件夹",
                    relatedFiles: [language.folderName]
                )],
                directoryReadable: false
            )
        }

        var result = DirectoryScan()
        var filesGroupedByID: [Int: [IndexedFile]] = [:]

        for url in urls.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let fileName = url.lastPathComponent
            let resourceValues = try? url.resourceValues(forKeys: [.isHiddenKey, .isRegularFileKey])
            if fileName.hasPrefix(".") || resourceValues?.isHidden == true {
                continue
            }

            guard resourceValues?.isRegularFile == true,
                  url.pathExtension.caseInsensitiveCompare("mp4") == .orderedSame else {
                result.issues.append(LibraryValidationIssue(
                    kind: .unsupportedItem,
                    message: "\(language.folderName) 中只允许 MP4 文件",
                    relatedFiles: ["\(language.folderName)/\(fileName)"]
                ))
                continue
            }

            let stem = url.deletingPathExtension().lastPathComponent
            guard isASCIIDigits(stem), let id = Int(stem) else {
                result.issues.append(LibraryValidationIssue(
                    kind: .invalidIdentifier,
                    message: "视频文件名必须是可转换为整数的纯数字",
                    relatedFiles: ["\(language.folderName)/\(fileName)"]
                ))
                continue
            }

            filesGroupedByID[id, default: []].append(IndexedFile(id: id, fileName: fileName))
        }

        for id in filesGroupedByID.keys.sorted() {
            guard let files = filesGroupedByID[id] else { continue }
            result.allParsedIDs.insert(id)
            result.fileNamesByID[id] = files.map(\.fileName)
            if files.count > 1 {
                result.ambiguousIDs.insert(id)
                let relatedFiles = files.map { "\(language.folderName)/\($0.fileName)" }.sorted()
                result.issues.append(LibraryValidationIssue(
                    kind: .duplicateIdentifier,
                    message: "\(language.folderName) 中编号 \(id) 重复",
                    relatedFiles: relatedFiles
                ))
            } else if let file = files.first {
                result.filesByID[id] = file
            }
        }

        return result
    }

    private func isASCIIDigits(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { byte in
            byte >= Character("0").asciiValue! && byte <= Character("9").asciiValue!
        }
    }

    private func stableSort(_ issues: [LibraryValidationIssue]) -> [LibraryValidationIssue] {
        issues.sorted {
            let left = "\($0.kind.rawValue)|\($0.relatedFiles.joined(separator: "|"))|\($0.message)"
            let right = "\($1.kind.rawValue)|\($1.relatedFiles.joined(separator: "|"))|\($1.message)"
            return left < right
        }
    }
}
