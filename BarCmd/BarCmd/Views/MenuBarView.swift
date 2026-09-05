import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var listHeight: CGFloat {
        min(CGFloat(model.configs.count) * 76 + 24, 360)
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.configs.isEmpty {
                Text("还没有命令")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 96)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.configs) { config in
                            CommandRowView(model: model, config: config)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: listHeight)
            }

            Divider()

            HStack(spacing: 12) {
                Button {
                    model.presentEditor(CommandConfig(id: UUID(), name: "", command: ""))
                } label: {
                    Label("添加命令", systemImage: "plus")
                }
                Toggle("登录时启动", isOn: loginItemBinding)
                    .toggleStyle(.checkbox)
                Button {
                    model.revealConfig()
                } label: {
                    Label("打开配置", systemImage: "folder")
                }
                Spacer()
                Button("退出 BarCmd") {
                    NSApp.terminate(nil)
                }
            }
            .padding(10)
        }
        .frame(width: 420)
        .disabled(model.isQuitting)
        .onAppear {
            model.openLogWindow = { openWindow(id: "command-log", value: $0) }
            model.openEditWindow = { openWindow(id: "command-edit", value: $0) }
            try? model.applyExternalReload()
            Task {
                await model.presentLoadErrorIfNeeded()
                await model.presentLoginItemPromptIfNeeded()
            }
        }
    }

    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { model.loginItemEnabled },
            set: { value in
                Task { await model.setLoginItemEnabled(value) }
            }
        )
    }
}
