import Foundation

public struct AppVersion: Comparable, Sendable {
    public let rawValue: String
    private let components: [Int]

    public init(_ rawValue: String) {
        self.rawValue = rawValue
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed
        let numeric = withoutPrefix.split(separator: "-", maxSplits: 1).first ?? ""
        let parsed = numeric.split(separator: ".").map { Int($0) ?? 0 }
        self.components = parsed.isEmpty ? [0] : parsed
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) == .orderedSame
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) == .orderedAscending
    }

    private static func compare(_ lhs: AppVersion, _ rhs: AppVersion) -> ComparisonResult {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left < right {
                return .orderedAscending
            }
            if left > right {
                return .orderedDescending
            }
        }
        return .orderedSame
    }
}
