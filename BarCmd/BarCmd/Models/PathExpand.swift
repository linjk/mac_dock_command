import Foundation

enum PathExpand {
    static func expand(_ path: String?, home: String = NSHomeDirectory()) -> URL {
        let raw: String
        if let path, !path.isEmpty {
            if path == "~" {
                raw = home
            } else if path.hasPrefix("~/") {
                raw = home + "/" + path.dropFirst(2)
            } else {
                raw = path
            }
        } else {
            raw = home
        }
        return URL(fileURLWithPath: raw)
    }
}
