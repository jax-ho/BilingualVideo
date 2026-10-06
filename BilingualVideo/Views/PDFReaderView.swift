import SwiftUI

struct PDFReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: PDFReaderModel
    private let appModel: AppModel
    @State private var isFinishing = false
    @State private var finishError: String?
    let onFinished: () -> Void

    init(request: PDFReadingRequest, appModel: AppModel, onFinished: @escaping () -> Void) {
        _model = StateObject(wrappedValue: PDFReaderModel(request: request, appModel: appModel))
        self.appModel = appModel
        self.onFinished = onFinished
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: geometry.size.height < 600 ? 10 : 20) {
                HStack(spacing: 16) {
                    Button { model.close(); dismiss() } label: {
                        Label("返回", systemImage: "chevron.backward")
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("pdf.close")
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("RAZ · 编号 \(model.request.book.id)")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                        Text("今天第 \(model.request.index + 1) / \(model.request.bookCount) 份")
                            .font(.subheadline).foregroundStyle(AppTheme.muted)
                    }
                }
                .frame(maxWidth: 980)

                if let error = model.error {
                    ContentUnavailableView {
                        Label("PDF 暂时无法阅读", systemImage: "book.closed")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("重新打开") { Task { await model.load() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else if model.isLoading || model.pages.isEmpty {
                    Spacer()
                    ProgressView("正在打开与识别 PDF…").tint(AppTheme.accent)
                    Spacer()
                } else {
                    pageCanvas
                        .frame(maxWidth: 980, maxHeight: .infinity)
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            if model.isPreparing { ProgressView().tint(AppTheme.accent) }
                            else { Image(systemName: model.isSpeaking ? "speaker.wave.3.fill" : "hand.draw") }
                            Text(model.isPreparing ? "准备声音…" : model.isSpeaking ? "正在朗读，再点一下可以重听" : "左右滑动翻页 · 点页面听朗读")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityIdentifier("pdf.speechStatus")
                        Text("第 \(model.pageIndex + 1) / \(model.pages.count) 页")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(AppTheme.muted)
                            .accessibilityIdentifier("pdf.pageNumber")
                        if let message = model.speechError {
                            Text(message).font(.footnote).foregroundStyle(AppTheme.warning)
                        } else if model.current?.text.isEmpty == true {
                            Text("这一页没有要朗读的文字").font(.footnote).foregroundStyle(AppTheme.muted)
                        }
                        if model.pageIndex == model.pages.count - 1 {
                            Button {
                                guard !isFinishing else { return }
                                isFinishing = true
                                Task {
                                    defer { isFinishing = false }
                                    do { if try await model.finish() { onFinished() } }
                                    catch { model.stop(); finishError = error.localizedDescription }
                                }
                            } label: {
                                Label("结束观看", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SpringPrimaryButtonStyle())
                            .disabled(isFinishing)
                            .accessibilityIdentifier("pdf.finish")
                        }
                    }
                    .frame(maxWidth: 980)
                }
            }
            .padding(.horizontal, geometry.size.width < 700 ? 20 : 40)
            .padding(.vertical, geometry.size.height < 600 ? 12 : 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(AppTheme.ink)
            .background(AppTheme.canvas.ignoresSafeArea())
        }
        .tint(AppTheme.accent)
        .interactiveDismissDisabled()
        .task { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.close(); dismiss() }
        }
        .onReceive(appModel.$savedPDFPlan.map { plan -> UUID? in
            guard let progress = plan?.pdfReading,
                  progress.day == appModel.scheduleService.day(containing: appModel.currentDate) else { return nil }
            return progress.sessionID
        }.removeDuplicates()) { _ in
            if !appModel.isCurrentPDFRequest(model.request) { model.close(); dismiss() }
        }
        .onDisappear { model.close() }
        .alert("阅读进度未能保存", isPresented: Binding(
            get: { finishError != nil }, set: { if !$0 { finishError = nil } }
        )) {
            Button("知道了", role: .cancel) { finishError = nil }
        } message: { Text(finishError ?? "") }
    }

    private var pageCanvas: some View {
        TabView(selection: Binding(
            get: { model.pageIndex }, set: { model.turn($0 - model.pageIndex) }
        )) {
            ForEach(model.pages.indices, id: \.self) { index in
                GeometryReader { geometry in
                    if let image = model.pageImages[index] {
                        Image(decorative: image, scale: 1)
                            .resizable().interpolation(.high).scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: AppTheme.accent.opacity(0.12), radius: 14, y: 6)
                            .padding(12)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .contentShape(Rectangle())
                            .onTapGesture { if index == model.pageIndex { model.speak() } }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(model.pages[index].text.isEmpty ? "PDF 页面" : model.pages[index].text)
                            .accessibilityHint("轻点朗读，向左滑动下一页，向右滑动上一页")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("pdf.page.\(index)")
                            .accessibilityAction { if index == model.pageIndex { model.speak() } }
                            .accessibilityAction(named: "下一页") { model.turn(1) }
                            .accessibilityAction(named: "上一页") { model.turn(-1) }
                    }
                }
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .id(model.request.id)
    }
}
