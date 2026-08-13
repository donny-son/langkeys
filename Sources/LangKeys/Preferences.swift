import Foundation

/// User-visible configuration: which lone modifier tap selects which input source, and how
/// the notch flag behaves.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    /// Called whenever anything changes, for the AppKit side of the app.
    var onChange: (() -> Void)?

    @Published private(set) var mappings: [ModifierKey: String] = [:]
    @Published private(set) var sides: [ModifierKey: NotchSide] = [:]

    /// Key taps switch the input source.
    @Published var isEnabled: Bool {
        didSet { store(isEnabled, "enabled") }
    }

    /// A flag animates out of the notch on every switch.
    @Published var showsNotchHUD: Bool {
        didSet { store(showsNotchHUD, "showNotchHUD") }
    }

    /// The flag stays out so the current input mode is always visible. When false it tucks
    /// back in after `flagDwellSeconds`.
    @Published var flagStaysVisible: Bool {
        didSet { store(flagStaysVisible, "flagStaysVisible") }
    }

    @Published var flagDwellSeconds: Double {
        didSet { store(flagDwellSeconds, "flagDwellSeconds") }
    }

    /// The menu bar item. With it hidden, the settings window is reachable by launching the
    /// app again from Spotlight or Finder.
    @Published var showsMenuBarIcon: Bool {
        didSet { store(showsMenuBarIcon, "showMenuBarIcon") }
    }

    /// A daily check against the GitHub releases feed. Only prompts when there is something
    /// newer than the running version.
    @Published var checksForUpdates: Bool {
        didSet { store(checksForUpdates, "checkForUpdates") }
    }

    /// When the last check actually reached GitHub, so a relaunch does not mean another one.
    @Published var lastUpdateCheck: Date? {
        didSet { defaults.set(lastUpdateCheck, forKey: "lastUpdateCheck") }
    }

    /// A version the user chose to sit out. Manual checks ignore it.
    @Published var skippedUpdateVersion: String? {
        didSet { defaults.set(skippedUpdateVersion, forKey: "skippedUpdateVersion") }
    }

    private init() {
        isEnabled = defaults.object(forKey: "enabled") as? Bool ?? true
        showsNotchHUD = defaults.object(forKey: "showNotchHUD") as? Bool ?? true
        flagStaysVisible = defaults.object(forKey: "flagStaysVisible") as? Bool ?? true
        flagDwellSeconds = defaults.object(forKey: "flagDwellSeconds") as? Double ?? 1.3
        showsMenuBarIcon = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
        checksForUpdates = defaults.object(forKey: "checkForUpdates") as? Bool ?? true
        lastUpdateCheck = defaults.object(forKey: "lastUpdateCheck") as? Date
        skippedUpdateVersion = defaults.string(forKey: "skippedUpdateVersion")

        let storedMappings = defaults.dictionary(forKey: "mappings") as? [String: String] ?? [:]
        for (rawKey, sourceID) in storedMappings {
            guard let code = Int64(rawKey), let key = ModifierKey(rawValue: code) else { continue }
            mappings[key] = sourceID
        }
        let storedSides = defaults.dictionary(forKey: "notchSides") as? [String: String] ?? [:]
        for (rawKey, rawSide) in storedSides {
            guard let code = Int64(rawKey), let key = ModifierKey(rawValue: code),
                let side = NotchSide(rawValue: rawSide)
            else { continue }
            sides[key] = side
        }

        if storedMappings.isEmpty && !defaults.bool(forKey: "didSeedDefaults") {
            seedDefaults()
        }
    }

    // MARK: - Mappings

    func inputSourceID(for key: ModifierKey) -> String? {
        mappings[key]
    }

    func setInputSource(_ sourceID: String?, for key: ModifierKey) {
        mappings[key] = sourceID
        persistMappings()
        onChange?()
    }

    /// Which side of the notch this key's flag slides out from.
    func notchSide(for key: ModifierKey) -> NotchSide {
        sides[key] ?? key.defaultNotchSide
    }

    func setNotchSide(_ side: NotchSide, for key: ModifierKey) {
        sides[key] = side
        persistMappings()
        onChange?()
    }

    /// The side to use for a switch that did not come from a mapped key — the input menu,
    /// another app, or launch.
    func notchSide(forSourceID sourceID: String) -> NotchSide {
        guard let key = ModifierKey.allCases.first(where: { mappings[$0] == sourceID }) else {
            return .left
        }
        return notchSide(for: key)
    }

    // MARK: - Persistence

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        onChange?()
    }

    private func persistMappings() {
        defaults.set(
            Dictionary(uniqueKeysWithValues: mappings.map { (String($0.key.rawValue), $0.value) }),
            forKey: "mappings")
        defaults.set(
            Dictionary(
                uniqueKeysWithValues: sides.map { (String($0.key.rawValue), $0.value.rawValue) }),
            forKey: "notchSides")
    }

    /// First launch: map the right-hand ⌘/⌥ to the first two available input sources,
    /// so the app does something useful before the user opens the menu.
    private func seedDefaults() {
        defaults.set(true, forKey: "didSeedDefaults")
        let sources = InputSourceManager.available()
        guard sources.count >= 2 else { return }
        mappings[.rightCommand] = sources[0].id
        mappings[.rightOption] = sources[1].id
        persistMappings()
    }
}
