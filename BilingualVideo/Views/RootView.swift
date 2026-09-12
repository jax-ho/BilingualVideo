import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingParentPortal = false
    @State private var isUITestScheduleEditorClosed = false

    @ViewBuilder
    var body: some View {
        #if DEBUG
        if UITestFixture.isStrictPlayback {
            if isShowingParentPortal {
                ParentHomeView(onClose: { isShowingParentPortal = false })
            } else {
                NavigationStack {
                    TodayView()
                        .toolbar {
                            Button("家长设置") { isShowingParentPortal = true }
                                .accessibilityIdentifier("ui-test.parent")
                        }
                }
            }
        } else if UITestFixture.isShowingScheduleEditor {
            if isUITestScheduleEditorClosed {
                if ProcessInfo.processInfo.arguments.contains("--ui-test-viewing-settings") {
                    NavigationStack { TodayView() }
                } else {
                    ContentUnavailableView(
                        "计划编辑已关闭",
                        systemImage: "checkmark.circle"
                    )
                    .accessibilityIdentifier("schedule.editor.closed")
                }
            } else {
                ParentHomeView(
                    onClose: { isUITestScheduleEditorClosed = true },
                    startsInScheduleEditor: true
                )
            }
        } else {
            standardContent
        }
        #else
        standardContent
        #endif
    }

    private var standardContent: some View {
        NavigationStack {
            TodayView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isShowingParentPortal = true
                        } label: {
                            Label("家长入口", systemImage: "lock.shield")
                        }
                        .accessibilityHint("需要家长 PIN")
                    }
                }
        }
        .sheet(isPresented: $isShowingParentPortal, onDismiss: { appModel.refreshToday() }) {
            ParentPortalView()
                .environmentObject(appModel)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                isShowingParentPortal = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            appModel.activate()
        }
        .alert(
            "提示",
            isPresented: Binding(
                get: { appModel.errorMessage != nil },
                set: { if !$0 { appModel.errorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {
                appModel.errorMessage = nil
            }
        } message: {
            Text(appModel.errorMessage ?? "")
        }
    }
}
