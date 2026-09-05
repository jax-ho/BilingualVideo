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
    }

    @EnvironmentObject private var appModel: AppModel
    let onClose: () -> Void
    @State private var selection: Destination? = .resources
    @State private var scheduleDraft: ViewingPlan?
    @State private var didInitializeDraft = false
    @State private var isShowingDiscardConfirmation = false

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
            return saved.startDay != draft.startDay || saved.orderedPairIDs != draft.orderedPairIDs
        }
    }
}
