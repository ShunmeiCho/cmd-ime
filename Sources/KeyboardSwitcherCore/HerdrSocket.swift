import Foundation

/// The local Herdr server's socket: one request and its one-line reply, or a connection for the
/// stream of focus events. Blocking, so never used on the main thread.
public struct HerdrSocket: Sendable {
    public static let `default` = HerdrSocket(path: NSHomeDirectory() + "/.config/herdr/herdr.sock")

    /// A local reply takes under a millisecond (measured 2026-10-02); a server that has not sent
    /// its whole reply by then is treated as not answering.
    public static let replyBudget: TimeInterval = 0.2
    private static let maxReplyBytes = 1 << 20
    private static let chunkBytes = 65536
    private static let lineFeed = UInt8(ascii: "\n")

    public let path: String

    public init(path: String) {
        self.path = path
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// Sends one request line and returns the reply line, or nil when the server is not there,
    /// has not finished its reply within `budget`, or answers more than a reply can be. The
    /// budget covers the whole exchange: a server that sends a byte now and then cannot hold
    /// the caller longer.
    public func reply(to request: Data, budget: TimeInterval = HerdrSocket.replyBudget) -> Data? {
        #if canImport(Darwin)
        let deadline = ProcessInfo.processInfo.systemUptime + budget
        guard let descriptor = connect(sendTimeout: budget) else { return nil }
        defer { close(descriptor) }
        guard Self.send(request, on: descriptor) else { return nil }
        var reply = Data()
        var chunk = [UInt8](repeating: 0, count: Self.chunkBytes)
        while reply.last != Self.lineFeed {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return nil }
            Self.setTimeout(SO_RCVTIMEO, remaining, on: descriptor)
            let count = read(descriptor, &chunk, chunk.count)
            guard count > 0, reply.count + count <= Self.maxReplyBytes else { return nil }
            reply.append(contentsOf: chunk[..<count])
        }
        return reply
        #else
        return nil
        #endif
    }

    /// A connected socket with `request` sent, for the caller to read events from and to close.
    /// Sending times out; reading does not, since events come whenever focus moves.
    public func openSubscription(_ request: Data) -> Int32? {
        #if canImport(Darwin)
        guard let descriptor = connect(sendTimeout: Self.replyBudget) else { return nil }
        guard Self.send(request, on: descriptor) else {
            close(descriptor)
            return nil
        }
        return descriptor
        #else
        return nil
        #endif
    }

    #if canImport(Darwin)
    private func connect(sendTimeout: TimeInterval) -> Int32? {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(descriptor)
            return nil
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path.utf8)
        }
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        Self.setTimeout(SO_SNDTIMEO, sendTimeout, on: descriptor)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            close(descriptor)
            return nil
        }
        return descriptor
    }

    private static func setTimeout(_ option: Int32, _ seconds: TimeInterval, on descriptor: Int32) {
        let whole = seconds.rounded(.down)
        // Zero means "no timeout" to the socket, so a remainder below a microsecond becomes one.
        let micro = max(1, Int32((seconds - whole) * 1_000_000))
        var value = timeval(tv_sec: Int(whole), tv_usec: micro)
        setsockopt(descriptor, SOL_SOCKET, option, &value, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func send(_ data: Data, on descriptor: Int32) -> Bool {
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return false }
            var sent = 0
            while sent < buffer.count {
                let count = write(descriptor, base + sent, buffer.count - sent)
                guard count > 0 else { return false }
                sent += count
            }
            return true
        }
    }
    #endif
}
