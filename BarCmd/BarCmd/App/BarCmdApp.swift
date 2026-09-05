import SwiftUI

@main
struct BarCmdApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text("BarCmd")
                .padding()
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.window)
    }
}
