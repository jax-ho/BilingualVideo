import Foundation

final class PDFLibraryScanner {
    private let directories: AppDirectories

    init(directories: AppDirectories) { self.directories = directories }

    func scan() -> PDFLibraryScanResult {
        var result = PDFLibraryScanResult()
        let urls: [URL]
        do {
            urls = try directories.fileManager.contentsOfDirectory(
                at: directories.razURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            result.issues.append(LibraryValidationIssue(
                kind: .missingDirectory, message: "raz 文件夹无法读取", relatedFiles: ["raz/"]
            ))
            return result
        }
        var filesByID: [Int: [String]] = [:]
        for url in urls {
            let name = url.lastPathComponent
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  url.pathExtension.lowercased() == "pdf" else {
                result.issues.append(LibraryValidationIssue(
                    kind: .unsupportedItem, message: "raz 中只支持 PDF 文件", relatedFiles: ["raz/\(name)"]
                ))
                continue
            }
            let stem = url.deletingPathExtension().lastPathComponent
            guard !stem.isEmpty, stem.utf8.allSatisfy({ (48...57).contains($0) }), let id = Int(stem) else {
                result.issues.append(LibraryValidationIssue(
                    kind: .invalidIdentifier, message: "PDF 文件名必须是纯数字", relatedFiles: ["raz/\(name)"]
                ))
                continue
            }
            filesByID[id, default: []].append(name)
        }
        for id in filesByID.keys.sorted() {
            let files = filesByID[id]!
            if files.count == 1 {
                result.books.append(PDFBook(id: id, fileName: files[0]))
            } else {
                result.issues.append(LibraryValidationIssue(
                    kind: .duplicateIdentifier, message: "PDF 编号 \(id) 重复", relatedFiles: files.map { "raz/\($0)" }
                ))
            }
        }
        return result
    }
}
