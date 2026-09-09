// 列出屏幕上指定 owner 的窗口元数据（用于冒烟验证）
import CoreGraphics
import Foundation

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    print("no window list")
    exit(1)
}
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    let name = w[kCGWindowName as String] as? String ?? ""
    if owner.lowercased().contains("wordpop") || name.lowercased().contains("wordpop") || owner.contains("词爆") {
        let num = w[kCGWindowNumber as String] as? Int ?? 0
        let layer = w[kCGWindowLayer as String] as? Int ?? -999
        let bounds = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let b = "\(bounds["X"] ?? "?")x\(bounds["Y"] ?? "?") \(bounds["Width"] ?? "?")x\(bounds["Height"] ?? "?")"
        print("win#\(num) layer=\(layer) \(b) owner=\(owner) name=\(name)")
    }
}
