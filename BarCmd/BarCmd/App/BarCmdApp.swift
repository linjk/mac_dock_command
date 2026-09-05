import SwiftUI

@main
struct BarCmdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        let store = ConfigStore()
        let logs = LogBufferStore()
        appDelegate.model = AppModel(
            store: store,
            processes: ProcessManager(),
            logs: logs,
            prompter: AlertPrompter()
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: appDelegate.model)
                .frame(width: 420)
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: "command-edit", for: UUID.self) { $id in
            if let id {
                CommandEditWindow(commandID: id, model: appDelegate.model)
            }
        }
        .defaultSize(width: 460, height: 360)

        WindowGroup(id: "command-log", for: UUID.self) { $id in
            if let id {
                LogWindowView(commandID: id, model: appDelegate.model)
            }
        }
        .defaultSize(width: 720, height: 480)
    }
}
