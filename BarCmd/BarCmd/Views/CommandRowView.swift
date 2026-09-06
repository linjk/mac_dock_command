import AppKit
import SwiftUI

struct CommandRowView: View {
    let model: AppModel
    let config: CommandConfig

    private var runtime: CommandRuntime {
        model.runtime(config.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                statusIndicator
                Text(config.name)
                    .lineLimit(1)
                if runtime.removedFromConfig {
                    Text("已从配置移除")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                actionButtons
            }

            Text(config.command)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(config.command)

            HStack(spacing: 8) {
                if let pid = runtime.pid {
                    Text("PID \(pid)")
                }
                if let port = runtime.port {
                    Button(":\(port)") {
                        NSWorkspace.shared.open(URL(string: "http://127.0.0.1:\(port)")!)
                    }
                    .buttonStyle(.plain)
                }
                RuntimeDurationLabel(runtime: runtime, fallbackStatus: statusText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            if runtime.status == .starting {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 2) {
            Button {
                Task { await model.start(config.id) }
            } label: {
                Image(systemName: "play.fill")
            }
            .disabled(runtime.status != .stopped && runtime.status != .exited)
            .help("启动")

            Button {
                Task { await model.stop(config.id) }
            } label: {
                Image(systemName: "stop.fill")
            }
            .disabled(runtime.status != .starting && runtime.status != .running)
            .help("停止")

            Button {
                model.openLog(config.id)
            } label: {
                Image(systemName: "doc.text")
            }
            .help("日志")

            Button {
                Task { _ = await model.requestEdit(config.id) }
            } label: {
                Image(systemName: "pencil")
            }
            .help("编辑")

            Button {
                Task { _ = await model.requestDelete(config.id) }
            } label: {
                Image(systemName: "trash")
            }
            .help("删除")
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
    }

    private var dotColor: Color {
        switch runtime.status {
        case .running: return .green
        case .stopped, .starting: return .gray
        case .exited: return .red
        }
    }

    private var statusText: String {
        switch runtime.status {
        case .stopped: return "已停止"
        case .starting: return "启动中"
        case .running: return "运行中"
        case .exited: return "已退出"
        }
    }
}
