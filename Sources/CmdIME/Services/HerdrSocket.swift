import Foundation
import KeyboardSwitcherCore

/// The local Herdr server's socket: one request and its one-line reply, or the stream of focus
/// events. Never used on the main thread.
enum HerdrSocket {
    static let path = NSHomeDirectory() + "/.config/herdr/herdr.sock"
    /// A local reply takes under a millisecond (measured 2026-10-02); a server that takes this
    /// long is treated as not answering.
    private static let timeout: TimeInterval = 0.2
    private static let maxReplyBytes = 1 << 20
    private static let chunkBytes = 65536

    static var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// Sends one request line and returns the reply line, or nil when the server is not there,
    /// does not answer in time or answers more than a reply can be.
    static func reply(to request: Data) -> Data? {
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard let descriptor = connect(timeout: timeout) else { return nil }
        defer { close(descriptor) }
        guard send(request, on: descriptor) else { return nil }
        var reply = Data()
        var chunk = [UInt8](repeating: 0, count: chunkBytes)
        while reply.last != UInt8(ascii: "\n") {
            let count = read(descriptor, &chunk, chunk.count)
            guard count > 0, reply.count + count <= maxReplyBytes else { return nil }
            reply.append(contentsOf: chunk[..<count])
        }
        return reply
    }

    /// A connected socket with the focus subscription sent, to be read by the caller. Sends time
    /// out; reads do not, since events come whenever focus moves.
    static func openFocusSubscription() -> Int32? {
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard let descriptor = connect(timeout: nil) else { return nil }
        guard send(HerdrSurface.focusSubscriptionRequest, on: descriptor) else {
            close(descriptor)
            return nil
        }
        return descriptor
    }

    private static func connect(timeout: TimeInterval?) -> Int32? {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else {
            close(descriptor)
            return nil
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path.utf8)
        }
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        setTimeout(SO_SNDTIMEO, Self.timeout, on: descriptor)
        if let timeout {
            setTimeout(SO_RCVTIMEO, timeout, on: descriptor)
        }
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
        var value = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - seconds.rounded(.down)) * 1_000_000))
        setsockopt(descriptor, SOL_SOCKET, option, &value, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func send(_ data: Data, on descriptor: Int32) -> Bool {
        data.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                let count = write(descriptor, buffer.baseAddress! + sent, buffer.count - sent)
                guard count > 0 else { return false }
                sent += count
            }
            return true
        }
    }
}

/// Reads focus events from one subscription socket on its own queue and reports each one, and the
/// end of the stream, to the caller. The caller hops to its own thread.
final class HerdrFocusStream: @unchecked Sendable {
    /// A line longer than this is not an event CmdIME reads; the buffer is dropped.
    private static let maxLineBytes = 65536
    private static let chunkBytes = 4096

    private let source: DispatchSourceRead
    private let queue = DispatchQueue(label: "com.shunmei.cmd-ime.herdr-focus")
    // Touched only on `queue`.
    private var buffer = Data()

    init(descriptor: Int32, onFocus: @escaping @Sendable () -> Void, onClose: @escaping @Sendable () -> Void) {
        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var chunk = [UInt8](repeating: 0, count: Self.chunkBytes)
            let count = read(descriptor, &chunk, chunk.count)
            guard count > 0 else {
                self.source.cancel()
                onClose()
                return
            }
            self.buffer.append(contentsOf: chunk[..<count])
            if self.takeLines().contains(where: Self.isFocusEvent) {
                onFocus()
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    func cancel() {
        source.cancel()
    }

    private func takeLines() -> [String] {
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        if buffer.count > Self.maxLineBytes {
            buffer.removeAll()
        }
        return lines
    }

    private static func isFocusEvent(_ line: String) -> Bool {
        switch HerdrReplyParser.event(from: line) {
        case .paneFocused, .tabFocused, .workspaceFocused:
            return true
        case .subscriptionStarted, .unknown:
            return false
        }
    }
}
