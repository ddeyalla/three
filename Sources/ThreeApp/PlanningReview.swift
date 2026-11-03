import Foundation
import ThreeCore

extension DaySnapshot {
    var draftSummary: String? {
        guard let plan, plan.status == .draft else { return nil }
        let source = switch plan.source {
        case .app: "Three"
        case .cli: "CLI"
        case .mcp: "MCP"
        case .routine: "Routine"
        }
        return "Draft from \(source) · \(activeTaskCount) \(activeTaskCount == 1 ? "task" : "tasks") · \(Format.duration(TimeInterval(plannedMinutes * 60)))"
    }
}

struct LinearIssueLink: Equatable {
    let title: String
    let url: URL

    init?(_ reference: String) {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(reference.startIndex..., in: reference)
        guard let url = detector.matches(in: reference, range: range).compactMap(\.url).first,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", parts.host?.lowercased() == "linear.app",
              parts.user == nil, parts.password == nil, parts.port == nil else { return nil }
        let path = parts.path.split(separator: "/")
        guard path.count >= 3, path[1] == "issue",
              path[2].range(of: #"^[A-Za-z][A-Za-z0-9]*-[0-9]+$"#, options: .regularExpression) != nil else { return nil }
        title = String(path[2])
        self.url = url
    }
}
