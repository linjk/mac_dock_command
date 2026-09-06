import AppKit

enum SingleInstanceGuard {
    static func terminateSiblings(
        bundleIdentifier: String,
        currentPID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
            guard app.processIdentifier != currentPID else { continue }
            app.forceTerminate()
        }
    }
}
