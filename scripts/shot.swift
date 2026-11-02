// Prints the CGWindowID of Three's largest on-screen window, for `screencapture -l`.
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let target = CommandLine.arguments.dropFirst().first ?? "Three"
let windows = list.filter { ($0[kCGWindowOwnerName as String] as? String) == target }
func area(_ w: [String: Any]) -> Double {
    let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    return (b["Width"] ?? 0) * (b["Height"] ?? 0)
}
if let w = windows.filter({ ($0[kCGWindowBounds as String] as? [String: Double])?["Y"] ?? -1 >= 0 }).max(by: { area($0) < area($1) }) {
    print(w[kCGWindowNumber as String] as! Int)
}
