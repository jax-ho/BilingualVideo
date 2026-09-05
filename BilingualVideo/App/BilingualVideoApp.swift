import SwiftUI
import UIKit

@main
struct BilingualVideoApp: App {
    @StateObject private var appModel: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        if UITestFixture.isShowingScheduleEditor {
            _appModel = StateObject(wrappedValue: UITestFixture.makeScheduleEditorModel())
            return
        }
        #endif
        _appModel = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                appModel.activate()
            default:
                appModel.deactivate()
            }
        }
    }
}
