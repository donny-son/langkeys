import Foundation

/// A dotted release version, compared component by component. String comparison would put
/// 1.10 before 1.9, which is exactly the case an updater must get right.
struct AppVersion: Comparable, CustomStringConvertible {
    private let components: [Int]
    let description: String

    init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Release tags are conventionally "v1.2.3" while the bundle stores "1.2.3".
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        // Any pre-release or build suffix is dropped for the comparison; pre-releases are
        // filtered out before they get this far, so this only tidies up stray "1.2.3+ci".
        let numeric = text.prefix { $0.isNumber || $0 == "." }
        let parts = numeric.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        components = parts.compactMap { $0 }
        description = text
    }

    /// The version of the running bundle.
    static var current: AppVersion {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return AppVersion(raw ?? "0") ?? AppVersion("0")!
    }

    private static func padded(_ lhs: AppVersion, _ rhs: AppVersion) -> [(Int, Int)] {
        (0..<max(lhs.components.count, rhs.components.count)).map { index in
            (
                index < lhs.components.count ? lhs.components[index] : 0,
                index < rhs.components.count ? rhs.components[index] : 0
            )
        }
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for (left, right) in padded(lhs, rhs) where left != right { return left < right }
        return false
    }

    /// 1.2 and 1.2.0 are the same release, so equality pads rather than comparing the text.
    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        padded(lhs, rhs).allSatisfy { $0 == $1 }
    }
}
