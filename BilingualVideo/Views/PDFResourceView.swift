import SwiftUI

struct PDFResourceView: View {
    @EnvironmentObject private var appModel: AppModel
    let onOpenSchedule: () -> Void

    var body: some View {
        List {
            Section {
                LabeledContent("可用 PDF", value: "\(appModel.pdfScanResult.books.count) 份")
                LabeledContent("计划缺失", value: "\(appModel.missingPlannedPDFIDs.count) 份")
                Button { appModel.refreshToday() } label: {
                    Label("刷新 PDF", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("pdf.resources.refresh")
            }
            .listRowBackground(AppTheme.surface)
            Section("添加 RAZ PDF") {
                Text("在“文件”App →“我的 iPad”→“放牛班的春天”→ raz 中放入 PDF。")
                Text("使用纯数字命名，例如 1.pdf、2.pdf、003.pdf。相同数字的 3.pdf 与 003.pdf 会被判定为重复编号。")
                    .font(.subheadline).foregroundStyle(AppTheme.muted)
                Text("PDF 计划独立生成和保存；新增文件后，到 PDF 计划中重新生成并保存。")
                    .font(.subheadline).foregroundStyle(AppTheme.muted)
            }
            .listRowBackground(AppTheme.surface)
            if !appModel.pdfScanResult.issues.isEmpty {
                Section("需要检查的文件") {
                    ForEach(appModel.pdfScanResult.issues) { IssueRow(issue: $0) }
                }
                .listRowBackground(AppTheme.surface)
            }
            if !appModel.missingPlannedPDFIDs.isEmpty {
                Section("计划中有 PDF 缺失") {
                    ForEach(appModel.missingPlannedPDFIDs, id: \.self) { id in Text("编号 \(id)") }
                    Text("补回相同编号的 PDF 即可继续，计划与阅读进度会保留。")
                        .font(.subheadline).foregroundStyle(AppTheme.muted)
                }
                .listRowBackground(AppTheme.surface)
            }
            Section("PDF 列表") {
                ForEach(appModel.pdfScanResult.books) { book in
                    LabeledContent("编号 \(book.id)", value: book.fileName)
                }
                Button(action: onOpenSchedule) {
                    Label(appModel.savedPDFPlan == nil ? "创建 PDF 计划" : "查看与调整 PDF 计划",
                          systemImage: "calendar.badge.plus")
                }
                .disabled(appModel.pdfScanResult.books.isEmpty && appModel.savedPDFPlan == nil)
            }
            .listRowBackground(AppTheme.surface)
        }
        .springList()
        .foregroundStyle(AppTheme.ink)
        .navigationTitle("RAZ PDF 资源")
        .task { appModel.refreshToday() }
    }
}
