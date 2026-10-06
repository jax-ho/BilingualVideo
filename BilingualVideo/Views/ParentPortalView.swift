import SwiftUI

struct ParentPortalView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isAuthenticated = false

    var body: some View {
        Group {
            if isAuthenticated {
                ParentHomeView(onClose: { dismiss() })
            } else {
                ParentGateView(
                    onAuthenticated: { isAuthenticated = true },
                    onCancel: { dismiss() }
                )
            }
        }
        .interactiveDismissDisabled(isAuthenticated)
    }
}

private struct ParentGateView: View {
    private enum Mode: Equatable {
        case loading
        case create
        case confirmCreate
        case verify
        case resetCreate
        case confirmReset
    }

    @EnvironmentObject private var appModel: AppModel
    let onAuthenticated: () -> Void
    let onCancel: () -> Void

    @State private var mode: Mode = .loading
    @State private var pin = ""
    @State private var firstPIN = ""
    @State private var message: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    SpringPortrait()
                        .frame(width: 84, height: 84)

                    VStack(spacing: 10) {
                        Text("家长空间")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.muted)
                        Text(title)
                            .font(.largeTitle.bold())
                        Text(instruction)
                            .foregroundStyle(AppTheme.muted)
                    }
                    .multilineTextAlignment(.center)

                    if mode != .loading {
                        SecureField("4–6 位数字", text: $pin)
                            .font(.system(.title, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .keyboardType(.numberPad)
                            .textContentType(.password)
                            .padding(18)
                            .background(AppTheme.sage, in: RoundedRectangle(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(AppTheme.line, lineWidth: 1)
                            }
                            .accessibilityIdentifier("parent.password")
                            .onChange(of: pin) { _, value in
                                pin = String(value.filter { character in
                                    guard let value = character.asciiValue else { return false }
                                    return value >= Character("0").asciiValue!
                                        && value <= Character("9").asciiValue!
                                }.prefix(6))
                            }

                        if let message {
                            Text(message)
                                .foregroundStyle(AppTheme.warning)
                                .multilineTextAlignment(.center)
                        }

                        Button(action: submit) {
                            Text(primaryButtonTitle)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SpringPrimaryButtonStyle())
                        .disabled(!ParentAccessService.isValidPIN(pin) || isWorking)
                        .accessibilityIdentifier("parent.submit")

                        if mode == .verify {
                            Button("忘记密码？") {
                                authenticateForReset()
                            }
                            .frame(minHeight: 44)
                            .disabled(isWorking)
                        }
                    } else {
                        ProgressView("正在准备家长设置…")
                    }
                }
                .padding(28)
                .frame(maxWidth: 460)
                .springSurface()
                .padding(24)
                .padding(.top, 20)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.canvas)
            .foregroundStyle(AppTheme.ink)
            .tint(AppTheme.accent)
            .navigationTitle("家长验证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("返回首页", action: onCancel)
                        .accessibilityIdentifier("parent.cancel")
                }
            }
            .task {
                await loadMode()
            }
        }
    }

    private var title: String {
        switch mode {
        case .loading: "家长验证"
        case .create: "设置家长密码"
        case .confirmCreate: "再输入一次密码"
        case .verify: "输入家长密码"
        case .resetCreate: "设置新密码"
        case .confirmReset: "确认新密码"
        }
    }

    private var instruction: String {
        switch mode {
        case .loading: ""
        case .create, .resetCreate: "用 4–6 位数字保护家长设置。密码仅保存在这台 iPad。"
        case .confirmCreate, .confirmReset: "确认刚才的 4–6 位数字。"
        case .verify: "进入后可管理视频、PDF、学习计划和播放规则。"
        }
    }

    private var primaryButtonTitle: String {
        switch mode {
        case .create, .resetCreate: "下一步"
        case .confirmCreate, .confirmReset: "保存并进入"
        case .verify: "进入家长设置"
        case .loading: ""
        }
    }

    @MainActor
    private func loadMode() async {
        guard mode == .loading else { return }
        do {
            mode = try appModel.parentAccessService.hasPIN() ? .verify : .create
        } catch {
            message = error.localizedDescription
            mode = .verify
        }
    }

    private func submit() {
        message = nil
        switch mode {
        case .create:
            firstPIN = pin
            pin = ""
            mode = .confirmCreate
        case .resetCreate:
            firstPIN = pin
            pin = ""
            mode = .confirmReset
        case .confirmCreate, .confirmReset:
            guard pin == firstPIN else {
                message = "两次输入不一致，请重新设置。"
                pin = ""
                firstPIN = ""
                mode = mode == .confirmCreate ? .create : .resetCreate
                return
            }
            do {
                try appModel.parentAccessService.setPIN(pin)
                clearPINs()
                onAuthenticated()
            } catch {
                message = error.localizedDescription
            }
        case .verify:
            do {
                if try appModel.parentAccessService.verifyPIN(pin) {
                    clearPINs()
                    onAuthenticated()
                } else {
                    pin = ""
                    message = "密码不正确，请重试。"
                }
            } catch {
                pin = ""
                message = "密码不正确，请重试。"
            }
        case .loading:
            break
        }
    }

    private func authenticateForReset() {
        isWorking = true
        message = nil
        Task { @MainActor in
            do {
                try await appModel.parentAccessService.authenticateDeviceOwnerForReset()
                pin = ""
                firstPIN = ""
                mode = .resetCreate
            } catch {
                message = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func clearPINs() {
        pin = ""
        firstPIN = ""
    }
}

struct ParentHomeView: View {
    private enum Destination: Hashable {
        case resources
        case schedule
        case pdfResources
        case pdfSchedule
        case viewing
    }

    @EnvironmentObject private var appModel: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let onClose: () -> Void
    @State private var selection: Destination? = .resources
    @State private var scheduleDraft: ViewingPlan?
    @State private var pdfScheduleDraft: ViewingPlan?
    @State private var didInitializeDraft = false
    @State private var isShowingDiscardConfirmation = false
    @State private var isShowingResetProgressConfirmation = false
    @State private var resetProgressMessage: String?
    @State private var isShowingResetPDFConfirmation = false

    init(onClose: @escaping () -> Void, startsInScheduleEditor: Bool = false) {
        self.onClose = onClose
        _selection = State(initialValue: startsInScheduleEditor ? .schedule : .resources)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                HStack(spacing: 12) {
                    SpringPortrait()
                        .frame(width: 60, height: 60)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("家长空间")
                            .font(.headline)
                        Text("放牛班的春天")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                }
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section("视频学习") {
                    destinationLabel("视频资源", subtitle: "添加与检查中英文视频", systemImage: "film.stack")
                        .tag(Destination.resources)
                        .accessibilityIdentifier("settings.resources")
                    destinationLabel("视频计划", subtitle: "调整播放顺序与日期", systemImage: "calendar.badge.clock")
                        .tag(Destination.schedule)
                        .accessibilityIdentifier("settings.schedule")
                }
                Section("PDF 阅读") {
                    destinationLabel("RAZ PDF 资源", subtitle: "添加与检查阅读材料", systemImage: "books.vertical")
                        .tag(Destination.pdfResources)
                        .accessibilityIdentifier("settings.pdfResources")
                    destinationLabel("PDF 计划", subtitle: "独立安排阅读顺序与日期", systemImage: "book.closed")
                        .tag(Destination.pdfSchedule)
                        .accessibilityIdentifier("settings.pdfSchedule")
                }
                Section("学习配置") {
                    destinationLabel("学习设置", subtitle: "每日数量、学习顺序与播放规则", systemImage: "slider.horizontal.3")
                        .tag(Destination.viewing)
                        .accessibilityIdentifier("settings.viewing")
                }
            }
            .springList()
            .foregroundStyle(AppTheme.ink)
            .navigationTitle("家长设置")
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 300)
            .safeAreaInset(edge: .bottom) {
                if horizontalSizeClass == .compact {
                    Button(action: requestClose) {
                        Label("返回首页", systemImage: "arrow.turn.up.left")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .padding(16)
                    .background(AppTheme.canvas)
                    .accessibilityIdentifier("parent.sidebar.close")
                }
            }
        } detail: {
            Group {
                switch selection {
                case .resources:
                    ResourceView(onOpenSchedule: { selection = .schedule })
                case .schedule:
                    ScheduleEditorView(
                        draft: $scheduleDraft,
                        onSaveCompleted: requestClose
                    )
                case .pdfResources:
                    PDFResourceView(onOpenSchedule: { selection = .pdfSchedule })
                case .pdfSchedule:
                    ScheduleEditorView(draft: $pdfScheduleDraft, content: .pdf, onSaveCompleted: requestClose)
                case .viewing:
                    learningSettingsView
                case nil:
                    ContentUnavailableView("选择一项", systemImage: "sidebar.left")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("返回首页", action: requestClose)
                    .accessibilityIdentifier("schedule.editor.close")
                }
            }
        }
        .tint(AppTheme.accent)
        .task {
            guard !didInitializeDraft else { return }
            scheduleDraft = appModel.savedPlan
            pdfScheduleDraft = appModel.savedPDFPlan
            didInitializeDraft = true
        }
        .onChange(of: appModel.savedPlan) { oldPlan, newPlan in
            if let oldPlan, let draft = scheduleDraft, draft.hasSameSchedule(as: oldPlan) {
                scheduleDraft = newPlan
            }
        }
        .onChange(of: appModel.savedPDFPlan) { oldPlan, newPlan in
            if let oldPlan, let draft = pdfScheduleDraft, draft.hasSameSchedule(as: oldPlan) {
                pdfScheduleDraft = newPlan
            }
        }
        .alert(
            "放弃未保存的计划更改？",
            isPresented: $isShowingDiscardConfirmation
        ) {
            Button("继续编辑", role: .cancel) {
                selection = hasUnsavedScheduleChanges ? .schedule : .pdfSchedule
            }
            Button("放弃更改并关闭", role: .destructive) {
                onClose()
            }
        } message: {
            Text("学习计划尚未保存。其他学习设置的更改已生效。")
        }
    }

    private var learningSettingsView: some View {
        Form {
            Section {
                Label("更改立即生效", systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityIdentifier("settings.autoSave")
            }
            .listRowBackground(Color.clear)

            learningArrangementSection
            videoPlaybackSection
            progressManagementSection
        }
        .springList()
        .foregroundStyle(AppTheme.ink)
        .navigationTitle("学习设置")
        .alert("提示", isPresented: Binding(
            get: { resetProgressMessage != nil },
            set: { if !$0 { resetProgressMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { resetProgressMessage = nil }
        } message: {
            Text(resetProgressMessage ?? "")
        }
    }

    private var learningArrangementSection: some View {
        Section {
            Stepper(value: Binding(
                get: { appModel.dailyGroupCount },
                set: { appModel.setDailyGroupCount($0) }
            ), in: 1...Int.max) {
                LabeledContent("每日视频", value: "\(appModel.dailyGroupCount) 组")
            }
            .accessibilityIdentifier("settings.dailyGroupCount")
            .accessibilityValue("\(appModel.dailyGroupCount) 组")

            Stepper(value: Binding(
                get: { appModel.dailyPDFCount },
                set: { appModel.setDailyPDFCount($0) }
            ), in: 1...Int.max) {
                LabeledContent("每日 PDF", value: "\(appModel.dailyPDFCount) 份 PDF")
            }
            .accessibilityIdentifier("settings.dailyPDFCount")

            Picker("学习顺序", selection: Binding(
                get: { appModel.learningOrder },
                set: { appModel.setLearningOrder($0) }
            )) {
                ForEach(LearningOrder.allCases) { order in
                    Text(order.displayName).tag(order)
                }
            }
            .accessibilityIdentifier("settings.learningOrder")

            DisclosureGroup("计划如何推进") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("视频：当天实际播放过，次日向前推进一组；没看的日期自动顺延。")
                    Text("PDF：当天打开并显示页面，次日向前推进一份；没读的日期自动顺延。")
                    Text("例如每天安排 3 份：第一天是第 1、2、3 份，第二天是第 2、3、4 份。计划末尾只安排剩余内容。")
                    Text("两份计划独立推进。调整每日数量时，若今日内容变化，会重置对应的 PDF 或严格模式视频进度。")
                }
                .font(.footnote)
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
            }
            .accessibilityIdentifier("settings.scheduleRules")
        } header: {
            Label("学习安排", systemImage: "calendar")
        } footer: {
            Text("一组视频包含中文和英文各一集。视频与 PDF 按所选顺序接续学习。")
                .foregroundStyle(AppTheme.muted)
        }
        .listRowBackground(AppTheme.surface)
    }

    private var videoPlaybackSection: some View {
        Section {
            VStack(spacing: 10) {
                modeOption(.strict)
                modeOption(.normal)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("settings.playbackMode")
            .accessibilityValue(appModel.playbackMode.displayName)

            if appModel.playbackMode == .normal {
                Toggle(isOn: Binding(
                    get: { appModel.isNormalPlaybackLooping },
                    set: { appModel.setNormalPlaybackLooping($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("循环播放")
                        Text("今日最后一集播完后，回到第一集。")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.muted)
                    }
                }
                .accessibilityIdentifier("settings.normalPlaybackLooping")
            }
        } header: {
            Label("视频播放", systemImage: "play.rectangle")
        } footer: {
            Text("两种模式均按“中文 → 英文 → 下一组中文”自动连播。")
                .foregroundStyle(AppTheme.muted)
        }
        .listRowBackground(AppTheme.surface)
    }

    private var progressManagementSection: some View {
        Section {
            Button(role: .destructive) { isShowingResetPDFConfirmation = true } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text("重置今日 PDF 进度")
                        .foregroundStyle(appModel.canResetTodayPDFProgress ? AppTheme.warning : AppTheme.muted)
                    Text(appModel.canResetTodayPDFProgress
                         ? "从今天第一份 PDF 的第一页重新开始。"
                         : "今天暂无可重置的阅读进度。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.muted)
                }
                .padding(.vertical, 4)
            }
            .disabled(!appModel.canResetTodayPDFProgress)
            .accessibilityIdentifier("settings.resetTodayPDFProgress")
            .confirmationDialog("重置今日 PDF 进度？", isPresented: $isShowingResetPDFConfirmation, titleVisibility: .visible) {
                Button("确认重置 PDF", role: .destructive) {
                    do {
                        try appModel.resetTodayPDFProgress()
                        resetProgressMessage = "今日 PDF 进度已重置。"
                    } catch {
                        resetProgressMessage = "PDF 进度重置失败，原进度仍然保留。"
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("从今天第一份 PDF 的第一页重新开始。PDF 计划和视频进度保留，此操作无法撤销。")
            }

            Button(role: .destructive) { isShowingResetProgressConfirmation = true } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text("重置今日视频进度")
                        .foregroundStyle(appModel.canResetTodayPlaybackProgress ? AppTheme.warning : AppTheme.muted)
                    Text(appModel.canResetTodayPlaybackProgress
                         ? "严格模式：从今天第一集重新观看。"
                         : "严格模式：今天暂无可重置的播放进度。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.muted)
                }
                .padding(.vertical, 4)
            }
            .disabled(!appModel.canResetTodayPlaybackProgress)
            .accessibilityIdentifier("settings.resetTodayProgress")
            .alert("重置今日视频进度？", isPresented: $isShowingResetProgressConfirmation) {
                Button("确认重置", role: .destructive) {
                    do {
                        try appModel.resetTodayPlaybackProgress()
                        resetProgressMessage = "今日进度已重置，可从第一集重新观看。"
                    } catch {
                        resetProgressMessage = "重置失败，原进度仍然保留。请检查本地存储后重试。"
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("今天将从第一集重新开始，已播完的内容也可再看。观看计划不变，此操作无法撤销。")
            }
        } header: {
            Label("进度管理", systemImage: "arrow.counterclockwise")
        } footer: {
            Text("只重置对应内容的今日进度，学习计划和日期记录保留。")
                .foregroundStyle(AppTheme.muted)
        }
        .listRowBackground(AppTheme.surface)
    }

    private func requestClose() {
        if hasUnsavedScheduleChanges || hasUnsavedPDFScheduleChanges {
            isShowingDiscardConfirmation = true
        } else {
            onClose()
        }
    }

    private func destinationLabel(_ title: String, subtitle: String, systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(.vertical, 5)
        } icon: {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
        }
    }

    private func modeOption(_ mode: PlaybackMode) -> some View {
        let isSelected = appModel.playbackMode == mode
        return Button {
            appModel.setPlaybackMode(mode)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.muted)
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(mode.displayName)模式")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(mode == .strict
                         ? "按计划依次播放，不能选集或快进。支持暂停和续播，播完今日内容后结束。"
                         : "可以选集、调整播放进度，从选中的视频开始连播。")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AppTheme.sage : Color.clear, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? AppTheme.accent.opacity(0.35) : AppTheme.line.opacity(0.65), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.mode.\(mode.rawValue)")
        .accessibilityLabel("\(mode.displayName)模式")
        .accessibilityValue(isSelected ? "已选择" : "未选择")
        .accessibilityHint(mode == .strict
                           ? "固定顺序，不能选集或快进。可暂停和续播，今天播完就结束。"
                           : "可以选集、调整播放进度，从选中的视频开始连播。")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var hasUnsavedScheduleChanges: Bool {
        guard didInitializeDraft else { return false }
        switch (appModel.savedPlan, scheduleDraft) {
        case (nil, nil): return false
        case (nil, .some), (.some, nil): return true
        case let (.some(saved), .some(draft)):
            return !saved.hasSameSchedule(as: draft)
        }
    }

    private var hasUnsavedPDFScheduleChanges: Bool {
        guard didInitializeDraft else { return false }
        switch (appModel.savedPDFPlan, pdfScheduleDraft) {
        case (nil, nil): return false
        case (nil, .some), (.some, nil): return true
        case let (.some(saved), .some(draft)): return !saved.hasSameSchedule(as: draft)
        }
    }
}
