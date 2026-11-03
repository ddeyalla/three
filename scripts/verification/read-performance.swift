import Foundation
import ThreeCore

struct Request: Decodable {
    let kind: String
    let from: String?
    let to: String?
    let days: Int
}

func nanoseconds() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

func measure<T: Encodable>(_ query: () throws -> T) throws {
    let start = nanoseconds()
    let result = try query()
    let queried = nanoseconds()
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    let compactStart = nanoseconds()
    let compact = try encoder.encode(result)
    let compactEnd = nanoseconds()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    let prettyStart = nanoseconds()
    let pretty = try encoder.encode(result)
    let prettyEnd = nanoseconds()
    print("{\"query_ns\":\(queried - start),\"compact_encode_ns\":\(compactEnd - compactStart),\"pretty_encode_ns\":\(prettyEnd - prettyStart),\"compact_bytes\":\(compact.count),\"pretty_bytes\":\(pretty.count),\"result\":\(String(decoding: compact, as: UTF8.self))}")
    fflush(stdout)
}

@main
struct ReadPerformance {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Expected a disposable database path") }
        let store = try Store(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("{\"ready\":true}")
        fflush(stdout)
        while let line = readLine() {
            let request = try JSONDecoder().decode(Request.self, from: Data(line.utf8))
            let from = request.from.flatMap(DayKey.init)
            let to = request.to.flatMap(DayKey.init)
            if request.kind == "history" {
                guard let from, let to else { fatalError("History requires valid bounds") }
                try measure {
                    let result = try store.historyReport(from: from, through: to)
                    precondition(result.days.count == request.days && result.totals.focusSeconds == Double(request.days * 9000))
                    precondition(result.totals.focusSessionCount == request.days * 10 && result.totals.breakSessionCount == request.days * 3)
                    return result
                }
            } else {
                precondition(request.kind == "stats")
                try measure {
                    let result = try store.stats(from: from, through: to)
                    precondition(result.days.count == request.days && result.metrics.focusSeconds == Double(request.days * 9000))
                    precondition(result.metrics.quality.focusSessionCount == request.days * 10 && result.tags.count == 6)
                    return result
                }
            }
        }
    }
}
