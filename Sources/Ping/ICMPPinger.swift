import Darwin
import Foundation

struct PingReply {
    let sequence: Int
    let bytes: Int
    let ttl: Int
    /// Round-trip time in milliseconds.
    let rtt: Double
}

enum PingError: LocalizedError {
    case resolveFailed(String)
    case socketFailed(Int32)
    case sendFailed(Int32)
    case receiveFailed(Int32)
    case timeout
    case timeExceeded(from: String)
    case unreachable(from: String, code: UInt8)

    var errorDescription: String? {
        message(in: .current)
    }

    func message(in language: Language) -> String {
        let t = language.pick
        switch self {
        case .resolveFailed(let host):
            return t("无法解析主机：\(host)", "Cannot resolve host: \(host)")
        case .socketFailed(let code):
            return t("创建 ICMP socket 失败：", "Failed to create ICMP socket: ") + String(cString: strerror(code))
        case .sendFailed(let code):
            return t("发送失败：", "Send failed: ") + String(cString: strerror(code))
        case .receiveFailed(let code):
            return t("接收失败：", "Receive failed: ") + String(cString: strerror(code))
        case .timeout:
            return t("请求超时", "Request timeout")
        case .timeExceeded(let from):
            return t("TTL 耗尽（来自 \(from)）", "Time to live exceeded (from \(from))")
        case .unreachable(let from, let code):
            return t("目标不可达（来自 \(from)，code \(code)）", "Destination unreachable (from \(from), code \(code))")
        }
    }
}

/// Sends ICMP Echo Requests over an unprivileged SOCK_DGRAM socket (IPv4 only).
/// `ping` blocks, so call it off the main thread, one call at a time.
final class ICMPPinger: @unchecked Sendable {
    /// Largest payload an IPv4 datagram can carry after the 20-byte IP and 8-byte ICMP headers.
    static let maxPayloadSize = 65_507

    let host: String
    let ipAddress: String

    private let address: sockaddr_in
    private let fd: Int32
    private let identifier = UInt16.random(in: 1...UInt16.max)

    init(host: String, ttl: Int) throws {
        self.host = host
        address = try Self.resolve(host)
        ipAddress = Self.string(from: address.sin_addr)

        fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { throw PingError.socketFailed(errno) }

        var ttlValue = Int32(ttl)
        // Room for the largest echo request and reply (plus IP header).
        var bufferSize = Int32(Self.maxPayloadSize + 8 + 60)
        guard
            setsockopt(fd, IPPROTO_IP, IP_TTL, &ttlValue, socklen_t(MemoryLayout<Int32>.size)) == 0,
            setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &bufferSize, socklen_t(MemoryLayout<Int32>.size)) == 0,
            setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &bufferSize, socklen_t(MemoryLayout<Int32>.size)) == 0
        else {
            let code = errno
            close(fd)
            throw PingError.socketFailed(code)
        }
    }

    deinit {
        close(fd)
    }

    func ping(sequence: UInt16, payloadSize: Int, timeout: TimeInterval) throws -> PingReply {
        let packet = makeEchoRequest(sequence: sequence, payloadSize: payloadSize)
        let start = DispatchTime.now()

        var target = address
        let sent = withUnsafePointer(to: &target) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(fd, packet, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent == packet.count else { throw PingError.sendFailed(errno) }

        let deadline = start.uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
        var buffer = [UInt8](repeating: 0, count: packet.count + 60)

        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw PingError.timeout }

            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, Int32((deadline - now) / 1_000_000) + 1)
            if ready < 0 {
                if errno == EINTR { continue }
                throw PingError.receiveFailed(errno)
            }
            if ready == 0 { continue }

            var source = sockaddr_in()
            var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &source) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buffer, buffer.count, 0, $0, &sourceLength)
                }
            }
            if count < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                throw PingError.receiveFailed(errno)
            }

            // macOS delivers the IPv4 header in front of the ICMP message.
            var offset = 0
            var ttl = 0
            if count >= 20, buffer[0] >> 4 == 4 {
                offset = Int(buffer[0] & 0x0F) * 4
                ttl = Int(buffer[8])
            }
            guard count - offset >= 8 else { continue }

            let type = buffer[offset]
            switch type {
            case 0: // Echo Reply
                guard readID(buffer, at: offset), readSequence(buffer, at: offset) == sequence else { continue }
                let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                return PingReply(
                    sequence: Int(sequence),
                    bytes: count - offset,
                    ttl: ttl,
                    rtt: Double(elapsed) / 1_000_000
                )

            case 3, 11: // Destination Unreachable, Time Exceeded
                // These quote the original IP header plus the first 8 bytes of our request.
                let inner = offset + 8
                guard count >= inner + 20 else { continue }
                let quoted = inner + Int(buffer[inner] & 0x0F) * 4
                guard count >= quoted + 8, buffer[quoted] == 8,
                      readID(buffer, at: quoted), readSequence(buffer, at: quoted) == sequence
                else { continue }

                let from = Self.string(from: source.sin_addr)
                if type == 11 { throw PingError.timeExceeded(from: from) }
                throw PingError.unreachable(from: from, code: buffer[offset + 1])

            default:
                continue
            }
        }
    }

    // MARK: - Private

    private func readID(_ buffer: [UInt8], at offset: Int) -> Bool {
        (UInt16(buffer[offset + 4]) << 8 | UInt16(buffer[offset + 5])) == identifier
    }

    private func readSequence(_ buffer: [UInt8], at offset: Int) -> UInt16 {
        UInt16(buffer[offset + 6]) << 8 | UInt16(buffer[offset + 7])
    }

    private func makeEchoRequest(sequence: UInt16, payloadSize: Int) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: 8 + payloadSize)
        packet[0] = 8 // Echo Request
        packet[4] = UInt8(identifier >> 8)
        packet[5] = UInt8(identifier & 0xFF)
        packet[6] = UInt8(sequence >> 8)
        packet[7] = UInt8(sequence & 0xFF)
        for i in 0..<payloadSize {
            packet[8 + i] = UInt8(truncatingIfNeeded: i)
        }
        let sum = Self.checksum(packet)
        packet[2] = UInt8(sum >> 8)
        packet[3] = UInt8(sum & 0xFF)
        return packet
    }

    private static func checksum(_ data: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < data.count {
            sum += UInt32(data[i]) << 8 | UInt32(data[i + 1])
            i += 2
        }
        if i < data.count {
            sum += UInt32(data[i]) << 8
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return ~UInt16(sum)
    }

    private static func string(from address: in_addr) -> String {
        var addr = address
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &addr, &buffer, socklen_t(buffer.count))
        return String(cString: buffer)
    }

    private static func resolve(_ host: String) throws -> sockaddr_in {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM

        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let info = result, let addr = info.pointee.ai_addr else {
            throw PingError.resolveFailed(host)
        }
        defer { freeaddrinfo(result) }

        return addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
    }
}
