import Foundation

// Chrome native messaging between the Three extension and `three native-host`: each message is UTF-8 JSON
// preceded by its byte length as a 32-bit integer in native byte order. stdout carries only these frames.

public enum NativeMessaging {
    public static let hostName = "com.deyalla.three"
    public static let protocolVersion = 1
    /// Chrome allows 64 MiB toward the host; the extension's messages are tiny, so anything near this is an attack or a bug.
    public static let maxInboundBytes = 64 * 1024
    /// Chrome's limit for one message from the host.
    public static let maxOutboundBytes = 1024 * 1024
    /// How long the extension may apply a state without hearing again. Past it, the extension drops its rules,
    /// so a dead host can't leave sites blocked. Chrome runs the host independently of the GUI.
    public static let lease: TimeInterval = 120
    /// How often the host renews the lease while nothing changes.
    public static let heartbeat: TimeInterval = 45

    public static func frame(_ payload: Data) throws -> Data {
        guard payload.count <= maxOutboundBytes else { throw NativeMessagingError.oversize(payload.count) }
        var length = UInt32(payload.count)
        return Data(bytes: &length, count: 4) + payload
    }
}

public enum NativeMessagingError: Error, Equatable {
    case oversize(Int)
    case malformed
}

/// Splits a byte stream into frames, however the bytes arrive.
public struct NativeMessageDecoder: Sendable {
    private let limit: Int
    private var buffer = Data()

    public init(limit: Int = NativeMessaging.maxInboundBytes) { self.limit = limit }

    public mutating func append(_ bytes: Data) { buffer.append(bytes) }

    /// The next complete payload, or nil until more bytes arrive. An oversize length throws as soon as its
    /// header is read, so the body is never buffered.
    public mutating func next() throws -> Data? {
        guard buffer.count >= 4 else { return nil }
        let length = Int(buffer.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        guard length <= limit else { throw NativeMessagingError.oversize(length) }
        guard buffer.count >= 4 + length else { return nil }
        let payload = Data(buffer.dropFirst(4).prefix(length))
        buffer = Data(buffer.dropFirst(4 + length))
        return payload
    }

    /// True when bytes of an unfinished frame are waiting, as at an EOF mid-message.
    public var hasPartialFrame: Bool { !buffer.isEmpty }
}

/// What the extension may say. Nothing here can change a rule, read a file or run anything.
public enum BrowserMessage: Equatable, Sendable {
    /// `clientId` is a random id the extension keeps per profile, used only to count connected profiles.
    case hello(clientId: String, extensionVersion: String, hostAccess: Bool)
    /// A block page loaded for this rule.
    case hit(ruleId: String)

    public init(json: Data) throws {
        struct Kind: Decodable { let type: String }
        struct Hello: Decodable {
            let `protocol`: Int, clientId: String, version: String, hostAccess: Bool
        }
        struct Hit: Decodable { let ruleId: String }
        let decoder = JSONDecoder()
        do {
            switch try decoder.decode(Kind.self, from: json).type {
            case "hello":
                let h = try decoder.decode(Hello.self, from: json)
                guard h.protocol == NativeMessaging.protocolVersion, UUID(uuidString: h.clientId) != nil,
                      h.version.count <= 24, h.version.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) else {
                    throw NativeMessagingError.malformed
                }
                self = .hello(clientId: h.clientId.lowercased(), extensionVersion: h.version, hostAccess: h.hostAccess)
            case "hit":
                let h = try decoder.decode(Hit.self, from: json)
                guard UUID(uuidString: h.ruleId) != nil else { throw NativeMessagingError.malformed }
                self = .hit(ruleId: h.ruleId)
            default:
                throw NativeMessagingError.malformed
            }
        } catch is DecodingError {
            throw NativeMessagingError.malformed
        }
    }
}

/// What the host tells the extension: the policy reduced to what a browser can enforce and a block page shows.
/// Compare two states to decide whether a push is needed; the lease is added only when framing.
public struct BrowserState: Equatable, Sendable {
    public struct Rule: Equatable, Sendable {
        public let id: String
        public let domain: String
        public let label: String
    }

    public enum Reason: String, Sendable {
        case focus, overrun, paused, focusHours
    }

    public let active: Bool
    public let reason: Reason?
    public let taskTitle: String?
    public let taskColor: String?
    public let until: Date?
    public let strict: Bool
    /// Domain rules only; app rules mean nothing to a browser.
    public let rules: [Rule]

    public init(_ policy: BlockPolicy) {
        active = policy.isActive
        reason = policy.focus.map {
            switch $0.phase {
            case .running: .focus
            case .overrun: .overrun
            case .paused: .paused
            }
        } ?? (policy.focusHours != nil ? .focusHours : nil)
        taskTitle = policy.focus?.taskTitle.map { String(String.UnicodeScalarView($0.unicodeScalars.prefix(200))) }
        taskColor = policy.focus?.categoryColor
        until = policy.until
        strict = policy.strict
        rules = policy.blocked.compactMap {
            guard case .domain(let d) = $0.target else { return nil }
            return Rule(id: $0.id, domain: d.rawValue, label: d.label)
        }
    }

    public func frame(validUntil: Date) throws -> Data {
        func ms(_ d: Date) -> Int64 { Int64((d.timeIntervalSince1970 * 1000).rounded()) }
        let object: [String: Any] = [
            "type": "state",
            "protocol": NativeMessaging.protocolVersion,
            "validUntil": ms(validUntil),
            "active": active,
            "reason": reason?.rawValue ?? NSNull(),
            "task": taskTitle.map { ["title": $0, "color": taskColor ?? NSNull()] as [String: Any] } ?? NSNull(),
            "until": until.map(ms) ?? NSNull(),
            "strict": strict,
            "rules": rules.map { ["id": $0.id, "domain": $0.domain, "label": $0.label] },
        ]
        return try NativeMessaging.frame(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
    }
}
