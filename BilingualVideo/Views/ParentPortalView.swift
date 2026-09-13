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
        case .verify: "进入后可管理视频、观看计划和播放规则。"
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
        case viewing
    }

    @EnvironmentObject private var appModel: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let onClose: () -> Void
    @State private var selection: Destination? = .resources
    @State private var scheduleDraft: ViewingPlan?
    @State private var didInitializeDraft = false
    @State private var isShowingDiscardConfirmation = false
    @State private var isShowingResetProgressConfirmation = false
    @State private var resetProgressMessage: String?

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

                destinationLabel("视频资源", subtitle: "添加与检查中英文视频", systemImage: "film.stack")
                    .tag(Destination.resources)
                    .accessibilityIdentifier("settings.resources")
                destinationLabel("计划编辑", subtitle: "调整播放顺序与日期", systemImage: "calendar.badge.clock")
                    .tag(Destination.schedule)
                    .accessibilityIdentifier("settings.schedule")
                destinationLabel("观看设置", subtitle: "每天看多少、怎样播放", systemImage: "slider.horizontal.3")
                    .tag(Destination.viewing)
                    .accessibilityIdentifier("settings.viewing")
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
                        onSaveCompleted: onClose
                    )
                case .viewing:
                    Form {
                        Section {
                            Label("更改立即生效", systemImage: "checkmark.circle")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppTheme.accent)
                                .accessibilityIdentifier("settings.autoSave")
                        }
                        .listRowBackground(Color.clear)
                        Section {
                            VStack(spacing: 0) {
                                modeOption(.strict)
                                Spacer().frame(height: 10)
                                modeOption(.normal)
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("settings.playbackMode")
                            .accessibilityValue(appModel.playbackMode.displayName)
                        } header: {
                            Text("播放模式")
                        } footer: {
                            Text("两种模式都会自动连播：中文 → 英文 → 下一组中文。")
                                .foregroundStyle(AppTheme.muted)
                        }
                        .listRowBackground(AppTheme.surface)
                        if appModel.playbackMode == .normal {
                            Section {
                                Toggle("循环播放", isOn: Binding(
                                    get: { appModel.isNormalPlaybackLooping },
                                    set: { appModel.setNormalPlaybackLooping($0) }
                                ))
                                .accessibilityIdentifier("settings.normalPlaybackLooping")
                            } header: {
                                Text("普通模式")
                            } footer: {
                                Text("今天的最后一集播完后，回到第一集。关闭则播完停止。")
                                    .foregroundStyle(AppTheme.muted)
                            }
                            .listRowBackground(AppTheme.surface)
                        }
                        Section {
                            Stepper(value: Binding(
                                get: { appModel.dailyGroupCount },
                                set: { appModel.setDailyGroupCount($0) }
                            ), in: 1...Int.max) {
                                LabeledContent("每天可看", value: "\(appModel.dailyGroupCount) 组")
                            }
                            .accessibilityIdentifier("settings.dailyGroupCount")
                            .accessibilityValue("\(appModel.dailyGroupCount) 组")

                            DisclosureGroup("观看安排如何推进") {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("当天只要实际播放过，次日就向前推进一组。某一天完全没看，那天及之后的安排会自动顺延；下次打开时也会补算。")
                                    Text("例如每天 3 组：第一天看第 1、2、3 组，第二天看第 2、3、4 组。接近计划末尾时，只看剩余组数。")
                                }
                                .font(.footnote)
                                .foregroundStyle(AppTheme.muted)
                                .padding(.vertical, 4)
                            }
                            .accessibilityIdentifier("settings.scheduleRules")
                        } header: {
                            Text("每日安排")
                        } footer: {
                            Text("一组包含中文和英文两个视频。若修改组数改变了今天的视频，严格模式的今日进度也会重置。")
                                .foregroundStyle(AppTheme.muted)
                        }
                        .listRowBackground(AppTheme.surface)
                        Section {
                            Button("重置今日进度", role: .destructive) {
                                isShowingResetProgressConfirmation = true
                            }
                            .foregroundStyle(appModel.canResetTodayPlaybackProgress ? AppTheme.warning : AppTheme.muted)
                            .opacity(appModel.canResetTodayPlaybackProgress ? 1 : 0.5)
                            .accessibilityIdentifier("settings.resetTodayProgress")
                            .disabled(!appModel.canResetTodayPlaybackProgress)
                            .alert(
                                "重置今日进度？",
                                isPresented: $isShowingResetProgressConfirmation
                            ) {
                                Button("确认重置", role: .destructive) {
                                    do {
                                        try appModel.resetTodayPlaybackProgress()
                                        resetProgressMessage = "今日进度已重置，可从第一集重新观看。"
                                    } catch {
                                        resetProgressMessage = "重置失败，原进度仍然保留。请检查本地存储后重试。"
                                    }
                                }
                                Button("取消", role: .cancel) { }
                            } message: {
                                Text("今天将从第一集重新开始，已播完的内容也可再看。观看计划不变，此操作无法撤销。")
                            }
                        } header: {
                            Text("严格模式 · 今日进度")
                        } footer: {
                            Text(appModel.canResetTodayPlaybackProgress
                                 ? "让孩子从今天的第一集重新观看。不会影响观看计划或已播放过的日期记录。"
                                 : "今天还没有需要重置的严格模式进度。")
                                .foregroundStyle(AppTheme.muted)
                        }
                        .listRowBackground(AppTheme.surface)
                    }
                    .springList()
                    .foregroundStyle(AppTheme.ink)
                    .navigationTitle("观看设置")
                    .alert("提示", isPresented: Binding(
                        get: { resetProgressMessage != nil },
                        set: { if !$0 { resetProgressMessage = nil } }
                    )) {
                        Button("知道了", role: .cancel) { resetProgressMessage = nil }
                    } message: {
                        Text(resetProgressMessage ?? "")
                    }
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
            didInitializeDraft = true
        }
        .onChange(of: appModel.savedPlan) { oldPlan, newPlan in
            if let oldPlan, let draft = scheduleDraft, draft.hasSameSchedule(as: oldPlan) {
                scheduleDraft = newPlan
            }
        }
        .alert(
            "放弃未保存的计划更改？",
            isPresented: $isShowingDiscardConfirmation
        ) {
            Button("继续编辑", role: .cancel) {
                selection = .schedule
            }
            Button("放弃更改并关闭", role: .destructive) {
                onClose()
            }
        } message: {
            Text("观看计划尚未保存。其他观看设置的更改已生效。")
        }
    }

    private func requestClose() {
        if hasUnsavedScheduleChanges {
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
                         ? "固定顺序，不能选集或快进。可暂停，退出后续播；今天播完就结束。"
                         : "可以自由选集和调整进度，从选中的视频开始连播。")
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
                           : "可以自由选集和调整进度，从选中的视频开始连播。")
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
}
