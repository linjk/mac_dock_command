import Foundation

protocol UserPrompter: AnyObject {
    func confirmStopForEdit(name: String) async -> Bool
    func confirmStopForDelete(name: String) async -> Bool
    func confirmDelete(name: String) async -> Bool
    func confirmQuit(runningCount: Int) async -> Bool
    func confirmReload() async -> Bool
    func alert(title: String, message: String) async
}
