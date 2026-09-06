import AppKit
import SwiftUI

struct LogWindowView: View {
    let commandID: UUID
    let model: AppModel

    @State private var lines: [String] = []
    @State private var isNearBottom = true
    @State private var bottomMinY: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    private static let backgroundColor = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private static let foregroundColor = Color(red: 0.80, green: 0.80, blue: 0.82)
    private static let bottomID = "log-bottom"
    private static let nearBottomSlop: CGFloat = 48

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(verbatim: line)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(Self.foregroundColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                        .background {
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: BottomMinYKey.self,
                                    value: geo.frame(in: .named("log-scroll")).minY
                                )
                            }
                        }
                }
                .padding(8)
            }
            .coordinateSpace(name: "log-scroll")
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ViewportHeightKey.self,
                        value: geo.size.height
                    )
                }
            }
            .onPreferenceChange(BottomMinYKey.self) { value in
                bottomMinY = value
                refreshNearBottom()
            }
            .onPreferenceChange(ViewportHeightKey.self) { value in
                viewportHeight = value
                refreshNearBottom()
            }
            .onChange(of: lines) { _, _ in
                if isNearBottom {
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
            }
            .task {
                for await snapshot in model.logs.updates(id: commandID) {
                    let stick = isNearBottom
                    lines = snapshot
                    if stick {
                        isNearBottom = true
                    }
                }
            }
        }
        .background(Self.backgroundColor)
        .preferredColorScheme(.dark)
        .navigationTitle(windowTitle)
        .toolbar {
            ToolbarItem {
                Button("复制全部") { copyAll() }
            }
            ToolbarItem {
                Button("清屏") { model.logs.clear(id: commandID) }
            }
            ToolbarItem {
                runtimeCaption
            }
        }
    }

    private var windowTitle: String {
        model.configs.first(where: { $0.id == commandID })?.name ?? "日志"
    }

    private var runtime: CommandRuntime {
        model.runtime(commandID)
    }

    @ViewBuilder
    private var runtimeCaption: some View {
        HStack(spacing: 8) {
            if let pid = runtime.pid {
                Text("PID \(pid)")
            }
            if let port = runtime.port {
                Text(":\(port)")
            }
            RuntimeDurationLabel(runtime: runtime)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func refreshNearBottom() {
        if viewportHeight == 0 {
            isNearBottom = true
            return
        }
        isNearBottom = bottomMinY <= viewportHeight + Self.nearBottomSlop
    }

    private func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}

private struct BottomMinYKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ViewportHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
