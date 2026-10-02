import Foundation
import KeyboardSwitcherCore

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
