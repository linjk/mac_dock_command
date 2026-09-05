import Foundation

enum ANSIStripper {
    static func strip(_ input: String) -> String {
        var s = input
        s = s.replacingOccurrences(of: "\u{001B}\\][^\u{0007}\u{001B}]*(\u{0007}|\u{001B}\\\\)", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        return s
    }
}
