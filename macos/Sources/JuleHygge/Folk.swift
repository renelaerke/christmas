import Foundation

/// Who walks along the bottom of the screen in the Christmas theme: the Nordic nisse (red hat, grey clothes, white
/// beard), or the Christmas elf most of the rest of the world expects (green and red, pointed ears and cap, striped
/// stockings, no beard). They are the same walkers in everything but looks (see ScreenOverlay.drawNisse/drawElf).
///
/// The setting `Folk` is 0 = automatic (the default: decided by the user's language and region, below), or one of
/// the raw values here when the user has chosen in the menu because the automatic choice was wrong for them.
enum Folk: Int, CaseIterable {
    /// The Nordic nisse; the Christmas elf; and three nisse-like figures with their own looks: the German Wichtel
    /// (a tall felt cap pulled down over the eyes, a long beard, hardly any legs), the Dutch kabouter (a stiff
    /// cone hat, a short beard, clogs) and the Estonian päkapikk (all in red with white trim, no beard).
    case nisser = 1, alfer = 2, wichtel = 3, kabouter = 4, paekapikk = 5

    static let names = ["Nisser", "Alfer", "Wichtel (tyske nisser)", "Kabouters (hollandske nisser)", "Päkapikud (estiske nisser)"]
    var name: String { Self.names[rawValue - 1] }
    /// For test output.
    var shortName: String { String(describing: self) }

    /// Who gets which figure: by language first, then by region; everyone else gets elves. These two tables are
    /// the whole rule; change it here (and the same in src/Folk.cs and linux/src/folk.rs).
    /// The Nordic ones: the nisse and its close relatives (tomte, tonttu, jólasveinar).
    static let byLanguage: [String: Folk] = [
        "da": .nisser, "nb": .nisser, "nn": .nisser, "no": .nisser, "sv": .nisser, "fi": .nisser, "fo": .nisser,
        "is": .nisser, "kl": .nisser, "se": .nisser,
        "de": .wichtel, "nl": .kabouter, "et": .paekapikk,
    ]
    static let byRegion: [String: Folk] = [
        "DK": .nisser, "NO": .nisser, "SE": .nisser, "FI": .nisser, "FO": .nisser, "GL": .nisser, "IS": .nisser,
        "AX": .nisser, "SJ": .nisser,
        "DE": .wichtel, "AT": .wichtel, "CH": .wichtel, "LI": .wichtel, "NL": .kabouter, "EE": .paekapikk,
    ]

    /// The language decides when it has a figure of its own: a Dane abroad keeps the nisser. Otherwise the region
    /// does: someone living in Denmark with the Mac set to English gets nisser too.
    static func automatic(language: String?, region: String?) -> Folk {
        if let l = language?.lowercased(), let f = byLanguage[l] { return f }
        if let r = region?.uppercased(), let f = byRegion[r] { return f }
        return .alfer
    }

    /// The user's first preferred language and the region from System Settings. (Locale.current's own language is
    /// limited to the languages the app is translated into, so the language is read from the preferred list.)
    /// JULE_LOCALE=en_US pretends to be that locale (for tests).
    static var systemLocale: (language: String?, region: String?) {
        if let fake = ProcessInfo.processInfo.environment["JULE_LOCALE"], !fake.isEmpty {
            let l = Locale(identifier: fake)
            return (l.language.languageCode?.identifier, l.region?.identifier)
        }
        let first = Locale.preferredLanguages.first.map { Locale(identifier: $0) }
        return (first?.language.languageCode?.identifier, Locale.current.region?.identifier ?? first?.region?.identifier)
    }

    /// The automatic choice on this Mac. Read once: a change of language or region takes effect at the next start.
    static let system: Folk = { let l = systemLocale; return automatic(language: l.language, region: l.region) }()

    /// The setting's value as the folk to draw (0 or anything unknown = automatic).
    static func chosen(_ setting: Int) -> Folk { Folk(rawValue: setting) ?? system }

    /// Test aid (--folk-test): prints what this Mac's language and region give, and the rule for a list of locales.
    static func test() {
        let l = systemLocale
        print("Denne Mac: sprog \(l.language ?? "?"), region \(l.region ?? "?") -> \(system.shortName)")
        for id in ["da_DK", "da_US", "en_DK", "nb_NO", "sv_SE", "fi_FI", "is_IS", "fo_FO", "kl_GL", "en_US", "en_GB",
                   "de_DE", "de_AT", "en_DE", "da_DE", "fr_CH", "nl_NL", "nl_BE", "et_EE", "fr_FR", "es_MX", "pt_BR", "ja_JP",
                   "zh-Hans_CN", "pl_PL", "en_AU"] {
            let loc = Locale(identifier: id)
            let f = automatic(language: loc.language.languageCode?.identifier, region: loc.region?.identifier)
            print("  \(id.padding(toLength: 11, withPad: " ", startingAt: 0)) \(f.shortName)")
        }
    }
}
