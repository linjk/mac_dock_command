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
        appDelegate.model = model
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
                .frame(width: 420)
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: "command-log", for: UUID.self) { $id in
            if let id {
                LogWindowView(commandID: id, model: model)
            }
        }
        .defaultSize(width: 720, height: 480)
    }
}
