import AppKit
import Foundation

final class AlertPrompter: UserPrompter {
    func confirmStopForEdit(name: String) async -> Bool {
        await confirm(
            message: "请先停止该命令再编辑",
            info: name,
            action: "停止并编辑"
        )
    }

    func confirmStopForDelete(name: String) async -> Bool {
        await confirm(
            message: "请先停止该命令再删除",
            info: name,
            action: "停止并删除"
        )
    }

    func confirmDelete(name: String) async -> Bool {
        await confirm(
            message: "确定删除？",
            info: name,
            action: "删除"
        )
    }

    func confirmQuit(runningCount: Int) async -> Bool {
        await confirm(
            message: "有 \(runningCount) 条命令正在运行，退出将停止它们。",
            action: "退出并停止"
        )
    }

    func confirmQuitSync(runningCount: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = "有 \(runningCount) 条命令正在运行，退出将停止它们。"
        alert.addButton(withTitle: "退出并停止")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func confirmReload() async -> Bool {
        await confirm(
            message: "配置已更新，是否重载？",
            action: "重载"
        )
    }

    func confirmLoginItem() async -> Bool {
        await confirm(
            message: "登录 Mac 时启动 BarCmd？",
            action: "启动"
        )
    }

    func alert(title: String, message: String) async {
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "好")
            _ = alert.runModal()
        }
    }

    private func confirm(message: String, info: String = "", action: String) async -> Bool {
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = message
            if !info.isEmpty {
                alert.informativeText = info
            }
            alert.addButton(withTitle: action)
            alert.addButton(withTitle: "取消")
            return alert.runModal() == .alertFirstButtonReturn
        }
    }
}
