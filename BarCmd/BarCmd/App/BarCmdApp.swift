import SwiftUI

@main
struct BarCmdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var model: AppModel

    init() {
        let store = ConfigStore()
        let logs = LogBufferStore()
        let model = AppModel(
            store: store,
            processes: ProcessManager(),
            logs: logs,
            prompter: AlertPrompter()
        )
        _model = State(initialValue: model)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
                .frame(width: 420)
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.window)
    }
}
