import SwiftUI

struct ResourceView: View {
    @EnvironmentObject private var appModel: AppModel
    var onOpenSchedule: (() -> Void)? = nil

    var body: some View {
        List {
            Section {
                resourceCount("已配对视频", value: "\(appModel.scanResult.pairs.count) 组", needsAttention: false)
                resourceCount("文件问题", value: "\(appModel.scanResult.issues.count) 项", needsAttention: !appModel.scanResult.issues.isEmpty)
                if !appModel.missingPlannedPairIDs.isEmpty {
                    resourceCount("计划缺失", value: "\(appModel.missingPlannedPairIDs.count) 组", needsAttention: true)
                }
            } header: {
                Text("资源概览")
            } footer: {
                Text("每组包含同编号的中文和英文视频。刷新视频不会改变观看计划。")
                    .foregroundStyle(AppTheme.muted)
                    .accessibilityIdentifier("resources.pairingSummary")
            }
            .listRowBackground(AppTheme.surface)

            if !appModel.scanResult.issues.isEmpty {
                Section("需要处理的问题") {
                    ForEach(appModel.scanResult.issues) { issue in
                        IssueRow(issue: issue)
                    }
                }
                .listRowBackground(AppTheme.surface)
            }

            if !appModel.missingPlannedPairIDs.isEmpty {
                Section("计划中有视频缺失") {
                    ForEach(appModel.missingPlannedPairIDs, id: \.self) { id in
                        Label("编号 \(id) 的中英文视频不完整", systemImage: "calendar.badge.exclamationmark")
                            .foregroundStyle(AppTheme.warning)
                    }
                    Text("补回相同编号的中英文视频即可恢复播放，原计划会保留。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.muted)
                }
                .listRowBackground(AppTheme.surface)
            }

            if appModel.scanResult.pairs.isEmpty {
                Section("添加第一组视频") {
                    importInstructions
                        .padding(.vertical, 8)
                }
                .listRowBackground(AppTheme.surface)
            } else {
                Section {
                    DisclosureGroup("如何添加视频") {
                        importInstructions
                            .padding(.vertical, 8)
                    }
                    .accessibilityIdentifier("resources.importHelp")
                }
                .listRowBackground(AppTheme.surface)

                if let onOpenSchedule {
                    Section {
                        Button(action: onOpenSchedule) {
                            Label(
                                appModel.savedPlan == nil ? "创建观看计划" : "查看与调整计划",
                                systemImage: "calendar"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SpringPrimaryButtonStyle())
                        .accessibilityIdentifier("resources.openSchedule")
                    } footer: {
                        Text("新增视频后，到计划编辑中重新生成并保存，才会加入观看安排。")
                            .foregroundStyle(AppTheme.muted)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }

                Section("已配对视频") {
                    ForEach(appModel.scanResult.pairs) { pair in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("编号 \(pair.id)")
                                .font(.headline)
                            fileRow("中文", fileName: pair.chineseFileName)
                            fileRow("英文", fileName: pair.englishFileName)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .listRowBackground(AppTheme.surface)
            }
        }
        .springList()
        .foregroundStyle(AppTheme.ink)
        .tint(AppTheme.accent)
        .navigationTitle("视频资源")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appModel.refreshLibrary()
                } label: {
                    Label("刷新视频", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("resources.refresh")
            }
        }
        .task {
            appModel.refreshLibrary()
        }
    }

    private func resourceCount(_ title: String, value: String, needsAttention: Bool) -> some View {
        LabeledContent {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(needsAttention ? AppTheme.warning : AppTheme.ink)
        } label: {
            Text(title)
                .foregroundStyle(AppTheme.muted)
        }
        .padding(.vertical, 4)
    }

    private func fileRow(_ language: String, fileName: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(language)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.muted)
            Text(fileName)
                .font(.subheadline)
                .textSelection(.enabled)
        }
    }

    private var importInstructions: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("1. 打开“文件”App")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.ink)
                Text("进入“我的 iPad”→“放牛班的春天”。")
                    .accessibilityIdentifier("resources.importPath")
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("2. 按语言放入 MP4 视频")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.ink)
                Text("中文放进 Chinese 文件夹，英文放进 English 文件夹。两边使用相同的数字编号。")
                    .accessibilityIdentifier("resources.pairingRule")
                Text("例如：Chinese/1.mp4 和 English/1.mp4")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .accessibilityIdentifier("resources.pairingExample")
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("3. 回到这里，刷新视频")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.ink)
                Text("识别到完整的中英文视频组后，就可以创建或调整观看计划。")
            }
        }
        .font(.subheadline)
        .foregroundStyle(AppTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("resources.importInstructions")
    }
}

struct IssueRow: View {
    let issue: LibraryValidationIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.warning)
            ForEach(issue.relatedFiles, id: \.self) { file in
                Text(file)
                    .font(.caption.monospaced())
                    .foregroundStyle(AppTheme.muted)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 3)
    }
}
