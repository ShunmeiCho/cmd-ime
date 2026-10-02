import Darwin
import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct HerdrSocketTests {
    /// A server on a scratch socket that answers the first connection with `reply`, one byte
    /// every `interval`. Returns the socket path; the listener closes with the test process.
    private func serve(_ reply: String, every interval: TimeInterval) throws -> String {
        let path = NSTemporaryDirectory() + "cmdime-\(UUID().uuidString.prefix(8)).sock"
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        try #require(listener >= 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        try #require(path.utf8.count < MemoryLayout.size(ofValue: address.sun_path))
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8) }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        try #require(bound == 0)
        try #require(listen(listener, 1) == 0)
        DispatchQueue.global().async {
            let connection = accept(listener, nil, nil)
            defer { close(listener); unlink(path) }
            guard connection >= 0 else { return }
            defer { close(connection) }
            var noSignal: Int32 = 1
            setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            var request = [UInt8](repeating: 0, count: 128)
            _ = Darwin.read(connection, &request, request.count)
            for byte in Array(reply.utf8) {
                if interval > 0 { Thread.sleep(forTimeInterval: interval) }
                var value = byte
                if Darwin.write(connection, &value, 1) != 1 { break }
            }
        }
        return path
    }

    @Test("a reply line comes back whole")
    func replies() throws {
        let socket = HerdrSocket(path: try serve("{\"ok\":1}\n", every: 0))

        #expect(socket.reply(to: Data("{}\n".utf8)) == Data("{\"ok\":1}\n".utf8))
    }

    @Test("the budget bounds the whole reply, even while the server drips bytes")
    func replyHasADeadline() throws {
        let socket = HerdrSocket(path: try serve("1234567\n", every: 0.08))
        let began = ProcessInfo.processInfo.systemUptime

        let reply = socket.reply(to: Data("{}\n".utf8), budget: 0.2)

        #expect(reply == nil)
        #expect(ProcessInfo.processInfo.systemUptime - began < 0.35)
    }

    @Test("no server means no reply and no subscription")
    func noServer() {
        let socket = HerdrSocket(path: NSTemporaryDirectory() + "cmdime-absent.sock")

        #expect(!socket.exists)
        #expect(socket.reply(to: Data("{}\n".utf8)) == nil)
        #expect(socket.openSubscription(Data("{}\n".utf8)) == nil)
    }
}
