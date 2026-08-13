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
        let language = tag.split(separator: "-").first.map(String.init)?.lowercased() ?? tag
        // Scripts pick out a region where the bare language cannot.
        if language == "zh" {
            return tag.contains("Hant") ? "TW" : "CN"
        }
        return regionByLanguage[language]
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

    /// Default country for a language that carries no region of its own.
    private static let regionByLanguage: [String: String] = [
        "af": "ZA", "am": "ET", "ar": "SA", "az": "AZ", "be": "BY", "bg": "BG", "bn": "BD",
        "bo": "CN", "bs": "BA", "ca": "ES", "chr": "US", "cs": "CZ", "cy": "GB", "da": "DK",
        "de": "DE", "dv": "MV", "el": "GR", "en": "US", "es": "ES", "et": "EE", "eu": "ES",
        "fa": "IR", "fi": "FI", "fo": "FO", "fr": "FR", "ga": "IE", "gd": "GB", "gl": "ES",
        "gu": "IN", "ha": "NG", "haw": "US", "he": "IL", "hi": "IN", "hr": "HR", "hu": "HU",
        "hy": "AM", "id": "ID", "ig": "NG", "is": "IS", "it": "IT", "iu": "CA", "ja": "JP",
        "ka": "GE", "kk": "KZ", "kl": "GL", "km": "KH", "kn": "IN", "ko": "KR", "ku": "IQ",
        "ky": "KG", "lo": "LA", "lt": "LT", "lv": "LV", "mi": "NZ", "mk": "MK", "ml": "IN",
        "mn": "MN", "mr": "IN", "ms": "MY", "mt": "MT", "my": "MM", "nb": "NO", "ne": "NP",
        "nl": "NL", "nn": "NO", "no": "NO", "or": "IN", "pa": "IN", "pl": "PL", "ps": "AF",
        "pt": "BR", "ro": "RO", "ru": "RU", "sa": "IN", "si": "LK", "sk": "SK", "sl": "SI",
        "sq": "AL", "sr": "RS", "sv": "SE", "sw": "KE", "ta": "IN", "te": "IN", "tg": "TJ",
        "th": "TH", "ti": "ER", "tk": "TM", "tr": "TR", "tt": "RU", "ug": "CN", "uk": "UA",
        "ur": "PK", "uz": "UZ", "vi": "VN", "yi": "IL", "yo": "NG", "zu": "ZA",
    ]
}
