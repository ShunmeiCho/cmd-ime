import AppKit
import CryptoKit
import Foundation
import KeyboardSwitcherCore
import Security

enum SelfUpdateError: Error, LocalizedError {
    case notInstalledAsApp
    case locationNotWritable(String)
    case unknownVersion(String)
    case downloadFailed(String)
    case checksumUnavailable
    case checksumMismatch(expected: String, actual: String)
    case unpackFailed
    case signatureInvalid
    case signedByAnotherTeam
    case wrongVersion(found: String)
    case replaceFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalledAsApp: "This copy is not an app bundle, so it cannot replace itself."
        case let .locationNotWritable(path): "CmdIME cannot write to \(path). Update with the install command instead."
        case let .unknownVersion(version): "\"\(version)\" is not a release version."
        case let .downloadFailed(reason): "The download failed: \(reason)"
        case .checksumUnavailable: "The release has no published checksum, so the download was not installed."
        case let .checksumMismatch(expected, actual):
            "Checksum mismatch (expected \(expected.prefix(12))…, got \(actual.prefix(12))…). Nothing was installed."
        case .unpackFailed: "The downloaded archive could not be unpacked."
        case .signatureInvalid: "The downloaded app's code signature is not valid. Nothing was installed."
        case .signedByAnotherTeam: "The downloaded app is signed by a different developer. Nothing was installed."
        case let .wrongVersion(found): "The archive contains version \(found), not the one requested."
        case let .replaceFailed(reason): "The app could not be replaced: \(reason)"
        }
    }
}

/// Downloads a release, verifies it, and swaps it in for the running bundle. The same
/// steps as `script/install.sh`, plus a code-signature check the script cannot do: the new
/// app must be validly signed by the team that signed this one, which also keeps the
/// Accessibility and Input Monitoring approvals (they follow the signing identity).
enum SelfUpdater {
    enum Stage: String {
        case downloading = "Downloading…"
        case verifying = "Verifying…"
        case installing = "Installing…"
    }

    static var canUpdateInPlace: Bool {
        let bundle = Bundle.main.bundleURL
        return bundle.pathExtension == "app"
            && FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path)
    }

    /// Returns after the new bundle is in place. The caller relaunches.
    @MainActor
    static func install(version: String, onStage: (Stage) -> Void) async throws {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else { throw SelfUpdateError.notInstalledAsApp }
        let parent = bundle.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw SelfUpdateError.locationNotWritable(parent.path)
        }
        guard let urls = UpdatePackage.assetURLs(version: version) else {
            throw SelfUpdateError.unknownVersion(version)
        }

        // On the same volume as the target, so the final swap is a rename.
        let workDirectory = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: bundle, create: true
        )
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        onStage(.downloading)
        let zipURL = workDirectory.appendingPathComponent("CmdIME.zip")
        let checksumText: String
        do {
            let (checksumData, checksumResponse) = try await URLSession.shared.data(from: urls.checksum)
            guard (checksumResponse as? HTTPURLResponse)?.statusCode == 200 else { throw SelfUpdateError.checksumUnavailable }
            checksumText = String(decoding: checksumData, as: UTF8.self)
            let (downloaded, response) = try await URLSession.shared.download(from: urls.zip)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw SelfUpdateError.downloadFailed("the server answered \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            try FileManager.default.moveItem(at: downloaded, to: zipURL)
        } catch let error as SelfUpdateError {
            throw error
        } catch {
            throw SelfUpdateError.downloadFailed(error.localizedDescription)
        }

        onStage(.verifying)
        guard let expected = UpdatePackage.publishedChecksum(from: checksumText) else {
            throw SelfUpdateError.checksumUnavailable
        }
        let actual = try sha256(of: zipURL)
        guard actual == expected else { throw SelfUpdateError.checksumMismatch(expected: expected, actual: actual) }

        let unpacked = workDirectory.appendingPathComponent("unpacked", isDirectory: true)
        guard try run("/usr/bin/ditto", ["-x", "-k", zipURL.path, unpacked.path]) == 0 else {
            throw SelfUpdateError.unpackFailed
        }
        let newApp = unpacked.appendingPathComponent(bundle.lastPathComponent)
        guard FileManager.default.fileExists(atPath: newApp.path) else { throw SelfUpdateError.unpackFailed }

        guard let newSignature = validSignature(ofAppAt: newApp) else { throw SelfUpdateError.signatureInvalid }
        // An ad-hoc or unsigned development copy has no team to compare against.
        if let ownTeam = validSignature(ofAppAt: bundle)?.team, ownTeam != newSignature.team {
            throw SelfUpdateError.signedByAnotherTeam
        }
        let found = Bundle(url: newApp)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        guard found == version else { throw SelfUpdateError.wrongVersion(found: found) }

        onStage(.installing)
        do {
            _ = try FileManager.default.replaceItemAt(bundle, withItemAt: newApp)
        } catch {
            throw SelfUpdateError.replaceFailed(error.localizedDescription)
        }
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func run(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private struct Signature {
        /// nil for a valid ad-hoc signature.
        let team: String?
    }

    /// nil when the signature does not verify.
    private static func validSignature(ofAppAt url: URL) -> Signature? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess
        else { return nil }
        let team = (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
        return Signature(team: team)
    }
}
