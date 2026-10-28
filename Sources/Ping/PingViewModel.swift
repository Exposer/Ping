import Foundation

struct PingLine: Identifiable {
    enum Kind {
        case info, reply, failure
    }

    let id = UUID()
    let kind: Kind
    /// Rendered at display time, so switching language also updates existing lines.
    let text: (Language) -> String
}

struct PingOptions {
    static let payloadSizeRange = 0...ICMPPinger.maxPayloadSize
    static let ttlRange = 1...255
    static let timeoutRange: ClosedRange<Double> = 0.1...60
    static let intervalRange: ClosedRange<Double> = 0.1...60

    /// ICMP payload bytes, excluding the 8-byte ICMP header (same as `ping -s`).
    var payloadSize = 56
    var ttl = 64
    var timeout: TimeInterval = 2
    var interval: TimeInterval = 1

    var clamped: PingOptions {
        PingOptions(
            payloadSize: payloadSize.clamped(to: Self.payloadSizeRange),
            ttl: ttl.clamped(to: Self.ttlRange),
            timeout: timeout.clamped(to: Self.timeoutRange),
            interval: interval.clamped(to: Self.intervalRange)
        )
    }
}

/// Running round-trip statistics, so continuous mode doesn't keep every reply around.
struct PingStats {
    private(set) var sent = 0
    private(set) var received = 0
    private(set) var min = Double.infinity
    private(set) var max = 0.0
    private var sum = 0.0
    private var sumOfSquares = 0.0

    var lost: Int { sent - received }

    /// Packet loss as a percentage, nil before anything is sent.
    var lossPercent: Double? {
        sent > 0 ? Double(lost) / Double(sent) * 100 : nil
    }

    /// Round-trip times in milliseconds, nil until a reply arrives.
    var rtt: (min: Double, avg: Double, max: Double, stddev: Double)? {
        guard received > 0 else { return nil }
        let n = Double(received)
        let avg = sum / n
        let variance = Swift.max(0, sumOfSquares / n - avg * avg)
        return (min, avg, max, variance.squareRoot())
    }

    mutating func addReply(_ rtt: Double) {
        sent += 1
        received += 1
        min = Swift.min(min, rtt)
        max = Swift.max(max, rtt)
        sum += rtt
        sumOfSquares += rtt * rtt
    }

    mutating func addLoss() {
        sent += 1
    }
}

@MainActor
final class PingViewModel: ObservableObject {
    @Published var target = "1.1.1.1"
    @Published var count = 4
    @Published var isContinuous = false
    @Published var options = PingOptions()
    @Published private(set) var lines: [PingLine] = []
    @Published private(set) var isRunning = false
    /// Live statistics for the current (or last) run.
    @Published private(set) var stats = PingStats()

    /// Oldest lines are dropped beyond this, so continuous mode stays responsive.
    private let maxLines = 1000
    private var task: Task<Void, Never>?

    func start() {
        let host = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isRunning, !host.isEmpty else { return }

        options = options.clamped
        lines = []
        stats = PingStats()
        isRunning = true
        let limit = isContinuous ? nil : count
        let options = self.options
        task = Task {
            await run(host: host, limit: limit, options: options)
            isRunning = false
        }
    }

    func stop() {
        task?.cancel()
    }

    func clear() {
        guard !isRunning else { return }
        lines = []
        stats = PingStats()
    }

    // MARK: - Private

    /// Pings `limit` times, or until stopped when `limit` is nil.
    private func run(host: String, limit: Int?, options: PingOptions) async {
        let pinger: ICMPPinger
        do {
            pinger = try await Task.detached { try ICMPPinger(host: host, ttl: options.ttl) }.value
        } catch {
            append(.failure) { describe(error, in: $0) }
            return
        }

        append(.info, "PING \(host) (\(pinger.ipAddress)): \(options.payloadSize) data bytes, ttl \(options.ttl)")

        var seq = 0

        while limit.map({ seq < $0 }) ?? true {
            if Task.isCancelled { break }

            let sequence = UInt16(truncatingIfNeeded: seq)
            let result = await Task.detached {
                Result {
                    try pinger.ping(sequence: sequence, payloadSize: options.payloadSize, timeout: options.timeout)
                }
            }.value

            switch result {
            case .success(let reply):
                stats.addReply(reply.rtt)
                append(.reply, String(
                    format: "%d bytes from %@: icmp_seq=%d ttl=%d time=%.3f ms",
                    reply.bytes, pinger.ipAddress, seq, reply.ttl, reply.rtt
                ))
            case .failure(let error):
                stats.addLoss()
                append(.failure) { "icmp_seq=\(seq)\($0.pick("：", ": "))\(describe(error, in: $0))" }
            }

            seq += 1
            if limit.map({ seq < $0 }) ?? true {
                let wait = max(0, options.interval - (result.rtt ?? options.timeout))
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }

        appendSummary(host: host)
    }

    private func appendSummary(host: String) {
        guard let loss = stats.lossPercent else { return }
        append(.info, "--- \(host) ping statistics ---")
        append(.info, String(
            format: "%d packets transmitted, %d packets received, %.1f%% packet loss",
            stats.sent, stats.received, loss
        ))

        guard let rtt = stats.rtt else { return }
        append(.info, String(
            format: "round-trip min/avg/max/stddev = %.3f/%.3f/%.3f/%.3f ms",
            rtt.min, rtt.avg, rtt.max, rtt.stddev
        ))
    }

    /// Appends a line that reads the same in every language (ping-style output).
    private func append(_ kind: PingLine.Kind, _ text: String) {
        append(kind) { _ in text }
    }

    private func append(_ kind: PingLine.Kind, _ text: @escaping (Language) -> String) {
        lines.append(PingLine(kind: kind, text: text))
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }
}

private func describe(_ error: Error, in language: Language) -> String {
    (error as? PingError)?.message(in: language) ?? error.localizedDescription
}

private extension Result where Success == PingReply {
    var rtt: TimeInterval? {
        (try? get()).map { $0.rtt / 1000 }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
