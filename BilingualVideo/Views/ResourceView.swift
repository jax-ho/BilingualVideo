import SwiftUI

struct ResourceView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        List {
            Section {
                LabeledContent("已配对视频组", value: "\(appModel.scanResult.pairs.count)")
                LabeledContent("扫描问题", value: "\(appModel.scanResult.issues.count)")
                Text("刷新只更新资源列表，当前观看计划不会改变。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !appModel.scanResult.issues.isEmpty {
                Section("需要处理的问题") {
                    ForEach(appModel.scanResult.issues) { issue in
                        IssueRow(issue: issue)
                    }
                }
            }

            if !appModel.missingPlannedPairIDs.isEmpty {
                Section("当前计划引用缺失") {
                    ForEach(appModel.missingPlannedPairIDs, id: \.self) { id in
                        Label("计划中的编号 \(id) 当前没有完整资源", systemImage: "calendar.badge.exclamationmark")
                            .foregroundStyle(.orange)
                    }
                    Text("计划没有被自动修改；补回相同编号的中英文视频即可恢复。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("已配对资源") {
                if appModel.scanResult.pairs.isEmpty {
                    Text("暂无可用的视频组")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appModel.scanResult.pairs) { pair in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("编号 \(pair.id)")
                                .font(.headline)
                            Label(pair.chineseFileName, systemImage: "character.book.closed.zh")
                            Label(pair.englishFileName, systemImage: "text.book.closed")
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("视频资源")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appModel.refreshLibrary()
                } label: {
                    Label("刷新视频", systemImage: "arrow.clockwise")
                }
            }
        }
        .task {
            appModel.refreshLibrary()
        }
    }
}

struct IssueRow: View {
    let issue: LibraryValidationIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            ForEach(issue.relatedFiles, id: \.self) { file in
                Text(file)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 3)
    }
}
