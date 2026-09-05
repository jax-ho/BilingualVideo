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
        if UITestFixture.isShowingScheduleEditor {
            if isUITestScheduleEditorClosed {
                ContentUnavailableView(
                    "计划编辑已关闭",
                    systemImage: "checkmark.circle"
                )
                .accessibilityIdentifier("schedule.editor.closed")
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
