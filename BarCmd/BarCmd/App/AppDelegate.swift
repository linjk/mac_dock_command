import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel!

    func applicationWillFinishLaunching(_ notification: Notification) {
        if let bundleID = Bundle.main.bundleIdentifier {
            SingleInstanceGuard.terminateSiblings(bundleIdentifier: bundleID)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.beginWatching()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.runningCount == 0 { return .terminateNow }
        let ok = AlertPrompter().confirmQuitSync(runningCount: model.runningCount)
        if !ok { return .terminateCancel }
        model.isQuitting = true
        Task { @MainActor in
            await model.stopAll()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
