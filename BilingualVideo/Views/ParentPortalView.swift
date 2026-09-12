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
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: mode == .verify ? "lock.shield.fill" : "person.badge.key.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.largeTitle.bold())
                    Text(instruction)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                if mode != .loading {
                    SecureField("4–6 位数字", text: $pin)
                        .font(.system(.title, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .keyboardType(.numberPad)
                        .textContentType(.password)
                        .frame(maxWidth: 320)
                        .padding()
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                        .onChange(of: pin) { _, value in
                            pin = String(value.filter { character in
                                guard let value = character.asciiValue else { return false }
                                return value >= Character("0").asciiValue!
                                    && value <= Character("9").asciiValue!
                            }.prefix(6))
                        }

                    if let message {
                        Text(message)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button(primaryButtonTitle, action: submit)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!ParentAccessService.isValidPIN(pin) || isWorking)

                    if mode == .verify {
                        Button("忘记 PIN") {
                            authenticateForReset()
                        }
                        .disabled(isWorking)
                    }
                } else {
                    ProgressView("正在检查家长 PIN…")
                }

                Spacer()
            }
            .padding(32)
            .navigationTitle("家长入口")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
            }
            .task {
                await loadMode()
            }
        }
    }

    private var title: String {
        switch mode {
        case .loading: "家长入口"
        case .create: "创建家长 PIN"
        case .confirmCreate: "再次输入 PIN"
        case .verify: "输入家长 PIN"
        case .resetCreate: "设置新的 PIN"
        case .confirmReset: "确认新的 PIN"
        }
    }

    private var instruction: String {
        switch mode {
        case .loading: ""
        case .create, .resetCreate: "请输入 4–6 位数字。PIN 只保存在本机钥匙串中。"
        case .confirmCreate, .confirmReset: "请再次输入相同的数字 PIN。"
        case .verify: "验证成功后才能管理视频资源和观看计划。"
        }
    }

    private var primaryButtonTitle: String {
        switch mode {
        case .create, .resetCreate: "下一步"
        case .confirmCreate, .confirmReset: "保存并进入"
        case .verify: "验证并进入"
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
                    message = "PIN 不正确，请重试。"
                }
            } catch {
                pin = ""
                message = "PIN 不正确，请重试。"
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
                Label("视频资源", systemImage: "film.stack")
                    .tag(Destination.resources)
                Label("计划编辑", systemImage: "calendar.badge.clock")
                    .tag(Destination.schedule)
                Label("观看设置", systemImage: "slider.horizontal.3")
                    .tag(Destination.viewing)
                    .accessibilityIdentifier("settings.viewing")
            }
            .navigationTitle("家长设置")
        } detail: {
            Group {
                switch selection {
                case .resources:
                    ResourceView()
                case .schedule:
                    ScheduleEditorView(
                        draft: $scheduleDraft,
                        onSaveCompleted: onClose
                    )
                case .viewing:
                    Form {
                        Section {
                            Picker("播放模式", selection: Binding(
                                get: { appModel.playbackMode },
                                set: { appModel.setPlaybackMode($0) }
                            )) {
                                ForEach(PlaybackMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("settings.playbackMode")
                            .accessibilityValue(appModel.playbackMode.displayName)
                        } footer: {
                            Text(appModel.playbackMode == .normal
                                 ? "普通模式：按页面顺序自动连播，每组先中文、后英文，再播放下一组中文。从点选的视频开始播放。"
                                 : "严格模式：只有一个播放入口，按中文、英文、下一组的顺序观看。允许暂停，不能选集或调整进度；退出后继续原进度，当天全部播完后不可重播。")
                        }
                        if appModel.playbackMode == .normal {
                            Section {
                                Toggle("循环播放", isOn: Binding(
                                    get: { appModel.isNormalPlaybackLooping },
                                    set: { appModel.setNormalPlaybackLooping($0) }
                                ))
                                .accessibilityIdentifier("settings.normalPlaybackLooping")
                            } footer: {
                                Text("开启后，当天最后一组英文播完会回到当天第一组中文；关闭时播完停止。默认开启，修改后自动保存。")
                            }
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
                        } footer: {
                            Text("一组包含中文和英文两个视频。当天有实际播放，次日向前推进一组；整天未播放则自动顺延，下次打开也会补算。设置为 3 组时依次看第 1、2、3 组，第 2、3、4 组。末尾不足时只显示剩余组数。修改后自动保存并立即生效；若当天视频列表变化，严格模式的当天进度与已播完状态会重置。")
                        }
                        Section {
                            Button("重置今日进度", role: .destructive) {
                                isShowingResetProgressConfirmation = true
                            }
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
                                Text("将清空严格模式今天的播放进度和已播完状态，下次从第一集开头播放。此操作无法撤销。")
                            }
                        } footer: {
                            Text("家长可重置严格模式的今日进度，让孩子重新观看。不会改变观看计划或今天已播放过的记录。没有今日进度时无需重置。")
                        }
                    }
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
                    Button("关闭") {
                        if hasUnsavedScheduleChanges {
                            isShowingDiscardConfirmation = true
                        } else {
                            onClose()
                        }
                    }
                    .accessibilityIdentifier("schedule.editor.close")
                }
            }
        }
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
            Text("如需保留候选计划，请返回计划编辑页并保存。")
        }
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
