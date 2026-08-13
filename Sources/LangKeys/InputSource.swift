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
        let iconURL = property(source, kTISPropertyIconImageURL) as? URL
        let language = language(of: source, id: id)
        let badge = (language.map { String($0.prefix(2)) } ?? String(name.prefix(2)))
            .uppercased()
        return InputSource(
            id: id, name: name, badge: badge,
            flag: language.flatMap(FlagLookup.flag(forLanguage:)), iconURL: iconURL)
    }

    /// The language this source types in, or nil when it belongs to no single language.
    ///
    /// `kTISPropertyInputSourceLanguages` is not as tidy as it looks: several Korean and
    /// Chinese layouts report `[""]`, and language-neutral ones like Unicode Hex Input report
    /// every language macOS knows.
    private static func language(of source: TISInputSource, id: String) -> String? {
        let languages = property(source, kTISPropertyInputSourceLanguages) as? [String] ?? []
        // The first entry is the source's own language, and every later entry is just
        // something the layout happens to be able to type — ABC lists twenty of them.
        if let first = languages.first, !first.isEmpty { return first }
        // An empty first entry followed by the whole world means the layout belongs to no
        // language at all (Unicode Hex Input). A short list means macOS simply left the
        // language off a layout that has one, so recover it from the ID.
        if languages.count > languageClaimLimit { return nil }
        return languageByIDKeyword.first { id.localizedCaseInsensitiveContains($0.keyword) }?
            .language
    }

    /// An unlabelled source listing more languages than this belongs to none of them.
    private static let languageClaimLimit = 5

    /// Recovers the language of the layouts that declare none, by the script named in their
    /// source ID. Ordered: "TraditionalPinyin" has to lose to "Traditional".
    private static let languageByIDKeyword: [(keyword: String, language: String)] = [
        ("Hangul", "ko"), ("Korean", "ko"), ("Romaja", "ko"),
        ("Traditional", "zh-Hant"), ("Zhuyin", "zh-Hant"), ("Cangjie", "zh-Hant"),
        ("Pinyin", "zh-Hans"), ("Wubi", "zh-Hans"),
    ]

    private static func property(_ source: TISInputSource, _ key: CFString?) -> Any? {
        guard let key, let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
    }
}
