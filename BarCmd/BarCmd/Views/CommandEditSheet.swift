import SwiftUI

struct CommandEditSheet: View {
    let model: AppModel
    let draft: CommandConfig
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var command: String
    @State private var cwd: String
    @State private var envText: String

    private var isNew: Bool {
        !model.configs.contains { $0.id == draft.id }
    }

    init(model: AppModel, draft: CommandConfig) {
        self.model = model
        self.draft = draft
        _name = State(initialValue: draft.name)
        _command = State(initialValue: draft.command)
        _cwd = State(initialValue: draft.cwd ?? "")
        _envText = State(initialValue: Self.encodeEnv(draft.env))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                TextField("Name", text: $name)
                TextField("Command", text: $command)
                TextField("Working Directory", text: $cwd)
                LabeledContent("Environment") {
                    TextEditor(text: $envText)
                        .font(.body.monospaced())
                        .frame(minHeight: 88)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding()
        }
        .frame(minWidth: 420, minHeight: 280)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCWD = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = CommandConfig(
            id: draft.id,
            name: trimmedName,
            command: trimmedCommand,
            cwd: trimmedCWD.isEmpty ? nil : trimmedCWD,
            env: Self.parseEnv(envText)
        )
        if isNew {
            await model.add(config)
        } else {
            await model.update(config)
        }
        dismiss()
    }

    static func parseEnv(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            result[key] = String(line[line.index(after: eq)...])
        }
        return result
    }

    static func encodeEnv(_ env: [String: String]) -> String {
        env.keys.sorted().map { "\($0)=\(env[$0] ?? "")" }.joined(separator: "\n")
    }
}
