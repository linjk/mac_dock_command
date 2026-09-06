import SwiftUI

struct RuntimeDurationLabel: View {
    let runtime: CommandRuntime
    var endedText: String = "已结束"
    var fallbackStatus: String?

    var body: some View {
        switch runtime.status {
        case .stopped, .exited:
            Text(fallbackStatus ?? endedText)
        case .starting, .running:
            if let startedAt = runtime.startedAt {
                Text(startedAt, style: .timer)
            } else if let fallbackStatus {
                Text(fallbackStatus)
            }
        }
    }
}
