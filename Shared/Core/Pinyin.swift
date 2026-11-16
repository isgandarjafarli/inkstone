import Foundation

enum Pinyin {
    private static let marks: [Character: Int] = {
        var m: [Character: Int] = [:]
        for (tone, set) in ["āēīōūǖĀĒĪŌŪǕ", "áéíóúǘÁÉÍÓÚǗ", "ǎěǐǒǔǚǍĚǏǑǓǙ", "àèìòùǜÀÈÌÒÙǛ"].enumerated() {
            for ch in set { m[ch] = tone + 1 }
        }
        return m
    }()

    /// Tone of one syllable: 1–4, or 5 for neutral.
    static func tone(of syllable: String) -> Int {
        for ch in syllable.precomposedStringWithCanonicalMapping {
            if let t = marks[ch] { return t }
        }
        return 5
    }

    static func syllables(_ pinyin: String) -> [String] {
        pinyin.split(whereSeparator: { $0 == " " }).map(String.init)
    }

    /// Strips tone marks and spaces: "péng you" -> "pengyou". Used for search.
    static func plain(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "'", with: "")
    }

    /// Joined display form for multi-syllable words: "péng you" -> "péngyou", "Xī ān" -> "Xī'ān".
    static func joined(_ s: String) -> String {
        let parts = syllables(s)
        guard parts.count > 1 else { return s }
        var out = parts[0]
        for p in parts.dropFirst() {
            if needsApostrophe(p) { out += "'" }
            out += p
        }
        return out
    }

    /// A syllable starting with a, e or o takes an apostrophe when it follows another one.
    static func needsApostrophe(_ syllable: String) -> Bool {
        guard let f = syllable.precomposedStringWithCanonicalMapping.lowercased().first else { return false }
        return "aeoāáǎàēéěèōóǒò".contains(f)
    }

    /// The pinyin string with tone marks removed but numbers added: "péng you" -> "peng2 you5".
    static func numbered(_ s: String) -> String {
        syllables(s).map { syl in
            let t = tone(of: syl)
            let base = syl.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
            return base + String(t)
        }.joined(separator: " ")
    }
}
