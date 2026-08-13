import Foundation

/// User-visible configuration: which lone modifier tap selects which input source.
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard
    private let mappingsKey = "mappings"
    private let enabledKey = "enabled"

    /// Called whenever mappings or the enabled flag change.
    var onChange: (() -> Void)?

    private(set) var mappings: [ModifierKey: String] = [:]

    var isEnabled: Bool {
        get { defaults.object(forKey: enabledKey) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: enabledKey)
            onChange?()
        }
    }

    private init() {
        let stored = defaults.dictionary(forKey: mappingsKey) as? [String: String] ?? [:]
        for (rawKey, sourceID) in stored {
            guard let code = Int64(rawKey), let key = ModifierKey(rawValue: code) else { continue }
            mappings[key] = sourceID
        }
        if stored.isEmpty && !defaults.bool(forKey: "didSeedDefaults") {
            seedDefaults()
        }
    }

    func inputSourceID(for key: ModifierKey) -> String? {
        mappings[key]
    }

    func setInputSource(_ sourceID: String?, for key: ModifierKey) {
        mappings[key] = sourceID
        persist()
        onChange?()
    }

    private func persist() {
        let stored = Dictionary(
            uniqueKeysWithValues: mappings.map { (String($0.key.rawValue), $0.value) })
        defaults.set(stored, forKey: mappingsKey)
    }

    /// First launch: map the right-hand ⌘/⌥ to the first two available input sources,
    /// so the app does something useful before the user opens the menu.
    private func seedDefaults() {
        defaults.set(true, forKey: "didSeedDefaults")
        let sources = InputSourceManager.available()
        guard sources.count >= 2 else { return }
        mappings[.rightCommand] = sources[0].id
        mappings[.rightOption] = sources[1].id
        persist()
    }
}
