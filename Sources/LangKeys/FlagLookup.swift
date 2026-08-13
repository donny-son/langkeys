import Foundation

/// Turns an input source's language tag (`en`, `ko`, `zh-Hans`, `en-GB`) into a flag emoji.
enum FlagLookup {
    static func flag(forLanguage tag: String) -> String? {
        guard let region = region(forLanguage: tag) else { return nil }
        return emoji(forRegion: region)
    }

    private static func region(forLanguage tag: String) -> String? {
        // An explicit region wins: en-GB is 🇬🇧, not 🇺🇸.
        let locale = Locale(identifier: tag)
        if let region = locale.region?.identifier, region.count == 2 {
            return region
        }

        let language = Locale.Language(identifier: tag)
        guard let code = language.languageCode?.identifier else { return nil }
        if let override = regionOverrides[code] { return override }

        // ICU's likely-subtag data fills in the region for every language macOS ships a
        // keyboard for, including scripts (zh-Hant → TW) and languages no hand-written
        // table would cover (ckb → IQ, sat → IN).
        let maximal = Locale.Language(identifier: language.maximalIdentifier)
        // "und" and other unknown tags maximize to en-Latn-US. Only trust a maximization
        // that kept the language we asked about, so a stray tag never becomes 🇺🇸.
        guard maximal.languageCode?.identifier == code,
            let region = maximal.region?.identifier, region.count == 2
        else { return nil }
        return region
    }

    private static func emoji(forRegion region: String) -> String? {
        let base: UInt32 = 0x1F1E6  // 🇦
        var scalars = String.UnicodeScalarView()
        for character in region.uppercased().unicodeScalars {
            guard let scalar = UnicodeScalar(base + character.value - 65) else { return nil }
            scalars.append(scalar)
        }
        guard scalars.count == 2 else { return nil }
        return String(scalars)
    }

    /// Languages where the most-likely region is not the flag people expect on a keyboard.
    private static let regionOverrides: [String: String] = [
        "ar": "SA",  // ICU says EG
        "yi": "IL",  // ICU says UA
    ]
}
