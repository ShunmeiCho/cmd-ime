import CryptoKit
import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct FileFingerprintTests {
    private func scratchFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fingerprint-\(UUID().uuidString).bin")
        try data.write(to: url)
        return url
    }

    @Test("same bytes give the same fingerprint; one changed byte of the same size does not")
    func detectsChanges() throws {
        let original = Data("activation recipes".utf8)
        var changed = original
        changed[0] = UInt8(ascii: "A")
        let a = try scratchFile(original), b = try scratchFile(original), c = try scratchFile(changed)
        defer { [a, b, c].forEach { try? FileManager.default.removeItem(at: $0) } }

        #expect(FileFingerprint.of(a) == FileFingerprint.of(b))
        #expect(FileFingerprint.of(a) != FileFingerprint.of(c))
        #expect(FileFingerprint.of(c)?.size == UInt64(original.count))
    }

    @Test("a file read across several chunks hashes the same as all of it at once")
    func chunkedDigestMatchesOneShot() throws {
        let data = Data((0..<(FileFingerprint.chunkSize * 2 + 12345)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let url = try scratchFile(data)
        defer { try? FileManager.default.removeItem(at: url) }

        let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(FileFingerprint.of(url) == FileFingerprint(size: UInt64(data.count), sha256: expected))
    }

    @Test("a missing file has no fingerprint")
    func missingFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("absent-\(UUID().uuidString)")
        #expect(FileFingerprint.of(url) == nil)
    }
}
