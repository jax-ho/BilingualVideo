import SwiftUI

struct ScheduleEditorView: View {
    @EnvironmentObject private var appModel: AppModel
    @Binding var draft: ViewingPlan?
    let onSaveCompleted: () -> Void
    @State private var chosenStartDate = Date()
    @State private var generationAttempted = false
    @State private var isShowingRegenerateConfirmation = false
    @State private var isShowingSavePreview = false
    @State private var shouldCloseAfterSave = false
    @State private var saveError: String?
    @State private var calendarFocusDate = Date()

    init(
        draft: Binding<ViewingPlan?>,
        onSaveCompleted: @escaping () -> Void = {}
    ) {
        _draft = draft
        self.onSaveCompleted = onSaveCompleted
    }

    var body: some View {
        List {
            Section {
                Text("扫描、顺序调整和日期修改只会改变候选计划。点击右上角“保存”后才会覆盖当前计划。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if generationAttempted, !appModel.scanResult.issues.isEmpty {
                Section("无法生成计划") {
                    ForEach(appModel.scanResult.issues) { issue in
                        IssueRow(issue: issue)
                    }
                    Text("当前已保存计划没有改变。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if draft == nil {
                Section("创建候选计划") {
                    DatePicker("开始日期", selection: $chosenStartDate, displayedComponents: .date)
                    Button {
                        generateCandidate()
                    } label: {
                        Label("扫描并生成计划", systemImage: "calendar.badge.plus")
                    }
                }
            } else {
                planSummarySection
                orderSection
                calendarSection
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("计划编辑")
        .toolbar {
            if draft != nil {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        if hasUnsavedChanges {
                            isShowingRegenerateConfirmation = true
                        } else {
                            generateCandidate()
                        }
                    } label: {
                        Label("重新生成", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Button("保存") {
                        isShowingSavePreview = true
                    }
                    .bold()
                    .disabled(!hasUnsavedChanges)
                    .accessibilityIdentifier("schedule.editor.save")
                }
            }
        }
        .task {
            loadPersistedDraftIfNeeded()
            focusCalendarOnDraftIfNeeded()
            appModel.refreshLibrary()
        }
        .confirmationDialog(
            "按当前资源重新生成候选计划？",
            isPresented: $isShowingRegenerateConfirmation,
            titleVisibility: .visible
        ) {
            Button("重新生成候选计划", role: .destructive) {
                generateCandidate()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这只会重置尚未保存的候选顺序；已保存计划要等你再次确认保存后才会改变。")
        }
        .sheet(isPresented: $isShowingSavePreview, onDismiss: finishSavingIfNeeded) {
            if let draft {
                SavePlanPreviewView(
                    oldPlan: appModel.savedPlan,
                    newPlan: draft,
                    calendar: appModel.scheduleService.calendar,
                    onCancel: { isShowingSavePreview = false },
                    onSave: saveDraft
                )
            }
        }
        .alert(
            "无法保存计划",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button("知道了", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var planSummarySection: some View {
        Section("整条计划") {
            DatePicker("开始日期", selection: draftDateBinding, displayedComponents: .date)

            HStack {
                Button {
                    shiftDraft(by: -1)
                } label: {
                    Label("前移一天", systemImage: "arrow.left")
                }
                .accessibilityIdentifier("schedule.shift.previous")
                Spacer()
                Button {
                    shiftDraft(by: 1)
                } label: {
                    Label("后移一天", systemImage: "arrow.right")
                }
                .accessibilityIdentifier("schedule.shift.next")
            }
            .buttonStyle(.borderless)

            if let draft {
                LabeledContent("视频组数", value: "\(draft.orderedPairIDs.count)")
                if let endDay = draft.startDay.adding(
                    days: max(draft.orderedPairIDs.count - 1, 0),
                    calendar: appModel.scheduleService.calendar
                ) {
                    LabeledContent("结束日期", value: format(endDay))
                }
            }
        }
    }

    private var orderSection: some View {
        Section {
            if let ids = draft?.orderedPairIDs {
                ForEach(ids, id: \.self) { id in
                    PairOrderRow(
                        pairID: id,
                        pair: appModel.scanResult.pair(id: id),
                        moveUp: { movePair(id: id, by: -1) },
                        moveDown: { movePair(id: id, by: 1) }
                    )
                }
                .onMove { source, destination in
                    guard var copy = draft else { return }
                    copy.orderedPairIDs.move(fromOffsets: source, toOffset: destination)
                    draft = copy
                }
            }
        } header: {
            Text("播放顺序")
        } footer: {
            Text("拖动右侧把手调整顺序；中英文始终作为一组移动。")
        }
    }

    private var calendarSection: some View {
        Section {
            if let draft {
                PlanCalendarShiftView(
                    plan: draft,
                    calendar: appModel.scheduleService.calendar,
                    focusDate: $calendarFocusDate,
                    onMovePair: { pairID, day in
                        guard let current = self.draft else { return false }
                        self.draft = appModel.scheduleService.shifting(
                            current,
                            movingPairID: pairID,
                            to: day
                        )
                        return true
                    }
                )
            }
        } header: {
            Text("调整某组播放日期")
        } footer: {
            Text("先点一个视频组，再点它要播放的日期。其他视频组保持原顺序，并一起前移或后移。")
        }
    }

    private var draftDateBinding: Binding<Date> {
        Binding {
            guard let draft,
                  let date = draft.startDay.date(in: appModel.scheduleService.calendar) else {
                return chosenStartDate
            }
            return date
        } set: { newDate in
            guard var copy = draft else { return }
            copy.startDay = appModel.scheduleService.day(containing: newDate)
            draft = copy
            chosenStartDate = newDate
            calendarFocusDate = newDate
        }
    }

    private var hasUnsavedChanges: Bool {
        switch (appModel.savedPlan, draft) {
        case (nil, nil): false
        case (nil, .some): true
        case (.some, nil): true
        case let (.some(saved), .some(draft)):
            saved.startDay != draft.startDay || saved.orderedPairIDs != draft.orderedPairIDs
        }
    }

    private func loadPersistedDraftIfNeeded() {
        guard draft == nil, let saved = appModel.savedPlan else { return }
        draft = saved
        chosenStartDate = saved.startDay.date(in: appModel.scheduleService.calendar) ?? Date()
        calendarFocusDate = chosenStartDate
    }

    private func focusCalendarOnDraftIfNeeded() {
        guard let draft,
              let startDate = draft.startDay.date(in: appModel.scheduleService.calendar) else {
            return
        }
        chosenStartDate = startDate
        calendarFocusDate = startDate
    }

    private func generateCandidate() {
        generationAttempted = true
        let date = draft?.startDay.date(in: appModel.scheduleService.calendar) ?? chosenStartDate
        guard let candidate = appModel.makeCandidate(startDate: date) else { return }
        draft = candidate
        calendarFocusDate = candidate.startDay.date(in: appModel.scheduleService.calendar) ?? date
    }

    private func shiftDraft(by days: Int) {
        guard let current = draft else { return }
        let shifted = appModel.scheduleService.shifting(current, byDays: days)
        draft = shifted
        if let startDate = shifted.startDay.date(in: appModel.scheduleService.calendar) {
            chosenStartDate = startDate
            calendarFocusDate = startDate
        }
    }

    private func movePair(id: Int, by offset: Int) {
        guard var copy = draft,
              let source = copy.orderedPairIDs.firstIndex(of: id) else { return }
        let target = source + offset
        guard copy.orderedPairIDs.indices.contains(target) else { return }
        copy.orderedPairIDs.swapAt(source, target)
        draft = copy
    }

    private func saveDraft() {
        guard let draft else { return }
        do {
            try appModel.savePlan(draft)
            self.draft = appModel.savedPlan
            shouldCloseAfterSave = true
            isShowingSavePreview = false
        } catch {
            saveError = "计划文件写入失败，旧计划仍然保留。"
        }
    }

    private func finishSavingIfNeeded() {
        guard shouldCloseAfterSave else { return }
        shouldCloseAfterSave = false
        onSaveCompleted()
    }

    private func format(_ day: LocalDay) -> String {
        guard let date = day.date(in: appModel.scheduleService.calendar) else {
            return "\(day.year)-\(day.month)-\(day.day)"
        }
        return date.formatted(.dateTime.year().month().day().weekday(.abbreviated))
    }
}

private struct PairOrderRow: View {
    let pairID: Int
    let pair: VideoPair?
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("编号 \(pairID)")
                .font(.headline)
            if let pair {
                Text("中文：\(pair.chineseFileName)　英文：\(pair.englishFileName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("当前资源缺失", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "上移") { moveUp() }
        .accessibilityAction(named: "下移") { moveDown() }
    }
}

private struct PlanCalendarShiftView: View {
    let plan: ViewingPlan
    let calendar: Calendar
    @Binding var focusDate: Date
    let onMovePair: (Int, LocalDay) -> Bool

    @State private var selectedPairID: Int?
    @State private var adjustmentMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("第一步：选择视频组")
                .font(.subheadline.bold())

            ScrollView(.horizontal, showsIndicators: true) {
                LazyHStack(spacing: 10) {
                    ForEach(plan.orderedPairIDs, id: \.self) { pairID in
                        let isSelected = selectedPairID == pairID
                        Button {
                            selectedPairID = pairID
                            adjustmentMessage = nil
                        } label: {
                            Label(
                                "编号 \(pairID)",
                                systemImage: isSelected ? "checkmark.circle.fill" : "circle"
                            )
                            .font(.headline)
                            .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(
                                isSelected ? Color.accentColor : Color.accentColor.opacity(0.15),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("schedule.shift.pair.\(pairID)")
                        .accessibilityValue(isSelected ? "已选择" : "未选择")
                        .accessibilityHint("选择后，再点下方目标日期")
                    }
                }
                .padding(.vertical, 2)
            }

            Text(selectionInstruction)
                .font(.footnote)
                .foregroundStyle(selectedPairID == nil ? Color.secondary : Color.accentColor)

            if let adjustmentMessage {
                Label(adjustmentMessage, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("schedule.shift.result")
            }

            Divider()

            Text("第二步：点目标日期")
                .font(.subheadline.bold())

            HStack {
                Button {
                    moveMonth(by: -1)
                } label: {
                    Label("上个月", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                Spacer()
                Text(monthTitle)
                    .font(.title3.bold())
                Spacer()
                Button {
                    moveMonth(by: 1)
                } label: {
                    Label("下个月", systemImage: "chevron.right")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
            }

            DatePicker("查看日期", selection: $focusDate, displayedComponents: .date)
                .datePickerStyle(.compact)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(rotatedWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        CalendarDaySelectionCell(
                            day: day,
                            pairID: pairID(on: day),
                            accessibilityDate: format(day),
                            hasSelectedPair: selectedPairID != nil,
                            onSelect: { select(day: day) }
                        )
                    } else {
                        Color.clear
                            .frame(minHeight: 68)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var selectionInstruction: String {
        if let selectedPairID {
            return "已选择编号 \(selectedPairID)。现在点日历里它要播放的日期。"
        }
        return "点一下编号即可选择，不需要长按或拖动。"
    }

    private var monthStart: Date {
        let components = calendar.dateComponents([.year, .month], from: focusDate)
        return calendar.date(from: components) ?? focusDate
    }

    private var monthTitle: String {
        monthStart.formatted(.dateTime.year().month(.wide))
    }

    private var monthCells: [LocalDay?] {
        guard let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        let weekday = calendar.component(.weekday, from: monthStart)
        let leadingEmptyCount = (weekday - calendar.firstWeekday + 7) % 7
        let components = calendar.dateComponents([.year, .month], from: monthStart)
        let days = dayRange.map { day -> LocalDay? in
            LocalDay(year: components.year!, month: components.month!, day: day)
        }
        return Array(repeating: nil, count: leadingEmptyCount) + days
    }

    private var rotatedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[start...] + symbols[..<start])
    }

    private func pairID(on day: LocalDay) -> Int? {
        guard let startDate = plan.startDay.date(in: calendar),
              let targetDate = day.date(in: calendar),
              let offset = calendar.dateComponents([.day], from: startDate, to: targetDate).day,
              plan.orderedPairIDs.indices.contains(offset) else {
            return nil
        }
        return plan.orderedPairIDs[offset]
    }

    private func select(day: LocalDay) {
        guard let selectedPairID else {
            adjustmentMessage = "请先选择一个视频组。"
            return
        }

        let movement = movementDescription(for: selectedPairID, to: day)
        guard onMovePair(selectedPairID, day) else { return }
        adjustmentMessage = "已将编号 \(selectedPairID) 安排到 \(shortFormat(day))；\(movement)"
        self.selectedPairID = nil
    }

    private func movementDescription(for pairID: Int, to targetDay: LocalDay) -> String {
        guard let index = plan.orderedPairIDs.firstIndex(of: pairID),
              let currentDay = plan.startDay.adding(days: index, calendar: calendar),
              let difference = calendar.dateComponents(
                [.day],
                from: currentDay.date(in: calendar) ?? focusDate,
                to: targetDay.date(in: calendar) ?? focusDate
              ).day else {
            return "其他视频组的日期已同步调整。"
        }

        if difference < 0 {
            return "其他视频组也前移 \(-difference) 天。"
        }
        if difference > 0 {
            return "其他视频组也后移 \(difference) 天。"
        }
        return "计划日期没有变化。"
    }

    private func moveMonth(by offset: Int) {
        focusDate = calendar.date(byAdding: .month, value: offset, to: monthStart) ?? focusDate
    }

    private func format(_ day: LocalDay) -> String {
        day.date(in: calendar)?.formatted(date: .complete, time: .omitted)
            ?? "\(day.year)-\(day.month)-\(day.day)"
    }

    private func shortFormat(_ day: LocalDay) -> String {
        day.date(in: calendar)?.formatted(.dateTime.month().day())
            ?? "\(day.month)月\(day.day)日"
    }
}

private struct CalendarDaySelectionCell: View {
    let day: LocalDay
    let pairID: Int?
    let accessibilityDate: String
    let hasSelectedPair: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                Text("\(day.day)")
                    .font(.subheadline.bold())
                if let pairID {
                    Text("#\(pairID)")
                        .font(.caption2.monospacedDigit().bold())
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text(" ")
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(hasSelectedPair ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(dayIdentifier)
        .accessibilityLabel("\(accessibilityDate)\(pairID.map { "，编号 \($0)" } ?? "，无计划")")
        .accessibilityHint(hasSelectedPair ? "把已选择的视频组安排到这一天" : "请先选择一个视频组")
    }

    private var dayIdentifier: String {
        String(format: "schedule.calendar.day.%04d-%02d-%02d", day.year, day.month, day.day)
    }
}

private struct SavePlanPreviewView: View {
    let oldPlan: ViewingPlan?
    let newPlan: ViewingPlan
    let calendar: Calendar
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("变更预览") {
                    LabeledContent("原开始日期", value: oldPlan.map { format($0.startDay) } ?? "尚无计划")
                    LabeledContent("新开始日期", value: format(newPlan.startDay))
                    LabeledContent("原视频组数", value: "\(oldPlan?.orderedPairIDs.count ?? 0)")
                    LabeledContent("新视频组数", value: "\(newPlan.orderedPairIDs.count)")
                }

                Section("新计划完整顺序") {
                    ForEach(Array(newPlan.orderedPairIDs.enumerated()), id: \.offset) { index, pairID in
                        if let day = newPlan.startDay.adding(days: index, calendar: calendar) {
                            LabeledContent(format(day), value: "编号 \(pairID)")
                        }
                    }
                }
            }
            .navigationTitle("保存计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("返回修改", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认保存", action: onSave)
                        .bold()
                }
            }
        }
    }

    private func format(_ day: LocalDay) -> String {
        guard let date = day.date(in: calendar) else {
            return "\(day.year)-\(day.month)-\(day.day)"
        }
        return date.formatted(.dateTime.year().month().day().weekday(.abbreviated))
    }
}
