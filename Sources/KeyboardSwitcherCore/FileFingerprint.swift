import CryptoKit
import Foundation

/// The size and SHA-256 of a file, read in fixed-size chunks, so telling whether files changed
/// never holds a whole file in memory (imported fonts can be large and there is no limit on count).
public struct FileFingerprint: Equatable, Sendable {
    public let size: UInt64
    public let sha256: String

    static let chunkSize = 1 << 20

    /// Nil when the file does not exist or cannot be read to the end.
    public static func of(_ url: URL) -> FileFingerprint? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var size: UInt64 = 0
        while true {
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: chunkSize)
            } catch {
                return nil
            }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            size += UInt64(chunk.count)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return FileFingerprint(size: size, sha256: digest)
    }
}
