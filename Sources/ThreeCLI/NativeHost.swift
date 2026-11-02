import ArgumentParser
import Foundation
import ThreeCore

/// Chrome starts this through `Contents/Helpers/three-native-host`, passing the extension's origin. It reads
/// the same database as the app, so Chrome blocking works with Three closed. stdout carries protocol frames
/// only; diagnostics go to stderr.
struct NativeHost: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "native-host",
        abstract: "Chrome's native messaging host. Chrome starts it; you don't need to.",
        shouldDisplay: false
    )
    @Argument(help: "The calling extension's origin, which Chrome passes first.") var origin: String
    @Argument(parsing: .allUnrecognized, help: .hidden) var ignored: [String] = []

    func run() throws {
        guard origin == ChromeExtension.origin else {
            hostLog("refusing caller \(origin)")
            throw ExitCode(2)
        }
        signal(SIGPIPE, SIG_IGN)
        let store = try Store()
        let loop = MainActor.assumeIsolated { HostLoop(store: store) }
        MainActor.assumeIsolated { loop.start() }
        withExtendedLifetime(loop) { dispatchMain() }
    }
}

func hostLog(_ message: String) {
    FileHandle.standardError.write(Data("three native-host: \(message)\n".utf8))
}

/// Everything runs on the main queue, so there is one writer to stdout and one owner of the last state sent.
@MainActor
final class HostLoop {
    private let store: Store
    private var sent: BrowserState?
    private var sentAt = Date.distantPast
    private var clientId: String?
    private var signalToken: Int32 = 0
    private let timer = DispatchSource.makeTimerSource(queue: .main)

    init(store: Store) { self.store = store }

    func start() {
        signalToken = ChangeSignal.observe { [weak self] in MainActor.assumeIsolated { self?.refresh() } }
        timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.refresh() } }
        timer.resume()
        readStdin()
        refresh()
    }

    /// Re-derives the state and sends it when it differs from the last one or the lease needs renewing. Our own
    /// writes (hits, hellos) post ChangeSignal too; comparing first keeps them from echoing back as pushes.
    private func refresh() {
        NSTimeZone.resetSystemTimeZone()
        let now = Date()
        do {
            let policy = try store.blockPolicy(now: now, calendar: .current)
            let state = BrowserState(policy)
            if state != sent || now >= sentAt.addingTimeInterval(NativeMessaging.heartbeat) {
                write(try state.frame(validUntil: now.addingTimeInterval(NativeMessaging.lease)))
                sent = state
                sentAt = now
                if let clientId { try store.recordBrowserHeartbeat(clientId: clientId, now: now) }
            }
            schedule(at: min(policy.nextChange ?? .distantFuture, sentAt.addingTimeInterval(NativeMessaging.heartbeat)), now: now)
        } catch {
            hostLog("couldn't read the blocking state: \(error)")
            schedule(at: now.addingTimeInterval(5), now: now)
        }
    }

    /// Wall-clock deadline, so a Mac waking from sleep fires late timers at once. At least a second out, so a
    /// boundary that rounds to now can't spin.
    private func schedule(at date: Date, now: Date) {
        timer.schedule(wallDeadline: .now() + max(1, date.timeIntervalSince(now)), leeway: .milliseconds(250))
    }

    private func handle(_ payload: Data) {
        do {
            switch try BrowserMessage(json: payload) {
            case .hello(let id, let version, let hostAccess):
                clientId = id
                try store.recordBrowserHello(clientId: id, extensionVersion: version, hostAccess: hostAccess)
                sent = nil
                refresh()
            case .hit(let ruleId):
                try store.recordBlockHit(ruleId: ruleId)
            }
        } catch NativeMessagingError.malformed {
            hostLog("ignored a message outside the protocol")
        } catch {
            hostLog("couldn't record a message: \(error)")
        }
    }

    private func write(_ frame: Data) {
        frame.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = Darwin.write(STDOUT_FILENO, raw.baseAddress! + offset, raw.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    exit(0)
                }
                offset += n
            }
        }
    }

    /// Blocking reads on their own thread; each complete frame is handled on main, in order. EOF means Chrome
    /// closed the port, so the host exits cleanly after handling what came before it.
    private func readStdin() {
        Thread.detachNewThread { [weak self] in
            var decoder = NativeMessageDecoder()
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            while true {
                let n = read(STDIN_FILENO, &buffer, buffer.count)
                if n < 0, errno == EINTR { continue }
                if n <= 0 {
                    let partial = decoder.hasPartialFrame
                    DispatchQueue.main.async {
                        if partial { hostLog("stdin closed in the middle of a message") }
                        exit(n < 0 ? 1 : 0)
                    }
                    return
                }
                decoder.append(Data(buffer[0..<n]))
                do {
                    while let payload = try decoder.next() {
                        DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(payload) } }
                    }
                } catch {
                    DispatchQueue.main.async {
                        hostLog("closing: \(error). Messages over \(NativeMessaging.maxInboundBytes) bytes aren't part of the protocol.")
                        exit(1)
                    }
                    return
                }
            }
        }
    }
}
