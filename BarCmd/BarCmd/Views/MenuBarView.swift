import AppKit
import SwiftUI

struct MenuBarView: View {
    let model: AppModel
    @State private var editing: CommandConfig?

    var body: some View {
        VStack(spacing: 0) {
            if model.configs.isEmpty {
                Text("还没有命令")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 96)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.configs) { config in
                            CommandRowView(model: model, config: config) { draft in
                                editing = draft
                            }
                        }
                    }
                    .padding(12)
                }
            }

            Divider()

            HStack(spacing: 12) {
                Button {
                    editing = CommandConfig(id: UUID(), name: "", command: "")
                } label: {
                    Label("添加命令", systemImage: "plus")
                }
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
        .sheet(item: $editing) { draft in
            CommandEditSheet(model: model, draft: draft)
        }
        .onAppear {
            Task { await model.presentLoadErrorIfNeeded() }
        }
    }
}
