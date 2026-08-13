import AppKit
import Carbon

/// A selectable keyboard input source (a "language" in the input menu).
struct InputSource: Hashable {
    let id: String
    let name: String
    /// Two-letter language badge, e.g. "EN" / "KO". Used when there is no flag for the language.
    let badge: String
    /// Flag emoji for the source's primary language, e.g. 🇺🇸 / 🇰🇷.
    let flag: String?
    let iconURL: URL?

    /// Name prefixed with the flag, for menu rows.
    var displayName: String {
        flag.map { "\($0) \(name)" } ?? name
    }

    var icon: NSImage? {
        guard let iconURL else { return nil }
        return NSImage(contentsOf: iconURL)
    }
}

enum InputSourceManager {
    /// Every enabled, selectable keyboard input source, in input-menu order.
    static func available() -> [InputSource] {
        let filter =
            [
                kTISPropertyInputSourceCategory! as String: kTISCategoryKeyboardInputSource!,
                kTISPropertyInputSourceIsEnabled! as String: kCFBooleanTrue!,
                kTISPropertyInputSourceIsSelectCapable! as String: kCFBooleanTrue!,
            ] as CFDictionary

        guard let list = TISCreateInputSourceList(filter, false),
            let sources = list.takeRetainedValue() as? [TISInputSource]
        else { return [] }

        return sources.compactMap(describe)
    }

    static func current() -> InputSource? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return describe(source)
    }

    static func select(id: String) {
        let filter = [kTISPropertyInputSourceID! as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false),
            let sources = list.takeRetainedValue() as? [TISInputSource],
            let target = sources.first
        else { return }
        TISSelectInputSource(target)
    }

    /// Fires whenever the selected keyboard input source changes, from anywhere in the system.
    static func observeSelectionChange(_ handler: @escaping () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in handler() }
    }

    private static func describe(_ source: TISInputSource) -> InputSource? {
        guard let id = property(source, kTISPropertyInputSourceID) as? String else { return nil }
        let name = property(source, kTISPropertyLocalizedName) as? String ?? id
        let languages = property(source, kTISPropertyInputSourceLanguages) as? [String] ?? []
        let badge = (languages.first.map { String($0.prefix(2)) } ?? String(name.prefix(2)))
            .uppercased()
        let iconURL = property(source, kTISPropertyIconImageURL) as? URL
        return InputSource(
            id: id, name: name, badge: badge,
            flag: languages.first.flatMap(FlagLookup.flag(forLanguage:)), iconURL: iconURL)
    }

    private static func property(_ source: TISInputSource, _ key: CFString?) -> Any? {
        guard let key, let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
    }
}
