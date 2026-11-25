import Foundation

/// The menu's texts in the user's language. The texts in the code are Danish, and the Danish text is the key: a
/// language is a file `assets/sprog/xx.ini` with lines "Danish text = text in that language" (see the README
/// there). A file can also be a regional variant, `xx-YY.ini` (es-MX.ini: Spanish as in Mexico), holding only the
/// texts that differ from its language's.
///
/// Every text falls back down a chain, as is usual for translations: the variant (es-mx), its language (es),
/// English, and last the Danish key itself. So a Mexican Spanish user sees the Mexican words where es-MX.ini has
/// them, Spanish for the rest, and English only for what Spanish lacks too.
///
/// The setting `Language` is empty for automatic (the default: the first of the user's preferred languages that
/// has a file, its regional variant before the language itself (es-MX, then es), else English) or a language's code when the user has chosen in the menu "Sprog".
/// The same on Windows (src/Lang.cs) and Linux (linux/src/lang.rs), from the same files.
enum Lang {
    struct Language { let code: String, name: String, texts: [String: String] }

    /// Every language there is a file for, by code; Danish is always there.
    static let all: [String: Language] = {
        var found: [String: Language] = ["da": Language(code: "da", name: "Dansk", texts: [:])]
        // the app's own files, then the user's (beside the settings file): a user's file wins over the app's
        let dirs = [Bundle.main.resourceURL?.appendingPathComponent("sprog"),
                    Settings.fileURL.deletingLastPathComponent().appendingPathComponent("sprog")]
        for dir in dirs.compactMap({ $0 }) {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for file in files.sorted(by: { $0.path < $1.path }) where file.pathExtension == "ini" {
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                let code = normal(file.deletingPathExtension().lastPathComponent)
                found[code] = parse(code, text)
            }
        }
        return found
    }()

    /// A language's code as the files and the setting use it: lower case, a variant with "-" (es_MX, es-MX → es-mx).
    static func normal(_ code: String) -> String { code.lowercased().replacingOccurrences(of: "_", with: "-") }
    /// The language a variant belongs to (es-mx → es); a language is its own.
    static func base(_ code: String) -> String { code.split(separator: "-").first.map(String.init) ?? code }
    /// Where a text is looked up, in order: the code, its language (for a variant), English. Danish ends every chain:
    /// its texts are the keys themselves.
    static func chain(_ code: String) -> [String] {
        var c = [code]
        if base(code) != code { c.append(base(code)) }
        if !c.contains("en") { c.append("en") }
        return c
    }

    /// "Danish text = translation" per line; "#" starts a comment; "@name" is the language's own name.
    static func parse(_ code: String, _ text: String) -> Language {
        var texts: [String: String] = [:], name = code
        for line in text.split(whereSeparator: \.isNewline) {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard !l.hasPrefix("#"), let r = l.range(of: " = ") else { continue }
            let key = String(l[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            let value = String(l[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            if key == "@name" { name = value } else if !key.isEmpty, !value.isEmpty { texts[key] = value }
        }
        return Language(code: code, name: name, texts: texts)
    }

    /// The languages for the menu, Danish and English first, then by name.
    static var listed: [Language] {
        all.values.sorted { a, b in
            let ra = a.code == "da" ? 0 : a.code == "en" ? 1 : 2, rb = b.code == "da" ? 0 : b.code == "en" ? 1 : 2
            return ra != rb ? ra < rb : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// The first of the user's preferred languages that there is a file for, its regional variant first (es-MX,
    /// then es); English when none of them has one. JULE_LOCALE=es_MX pretends to be that locale (for tests).
    static let automatic: String = {
        var ids = Locale.preferredLanguages
        if let fake = ProcessInfo.processInfo.environment["JULE_LOCALE"], !fake.isEmpty { ids = [fake] }
        return ids.flatMap(candidates).first { all[$0] != nil } ?? "en"
    }()

    /// The codes a locale could have a file under, the most particular first: es_MX → es-mx, es.
    static func candidates(_ id: String) -> [String] {
        let l = Locale(identifier: id)
        guard let language = l.language.languageCode?.identifier else { return [] }
        let region = l.language.region?.identifier ?? l.region?.identifier
        return (region.map { [normal(language + "-" + $0)] } ?? []) + [normal(language)]
    }

    /// The setting `Language` (set when the settings are read and when the user chooses in the menu).
    nonisolated(unsafe) static var setting = ""
    /// The language in use.
    static var code: String { all[setting] != nil ? setting : automatic }

    static func text(_ da: String) -> String {
        for c in chain(code) {
            if base(c) == "da" { return da }
            if let t = all[c]?.texts[da] { return t }
        }
        return da
    }

    /// Test aid (--sprog-test): the languages found, the automatic choice, and what each lacks against English.
    static func test() {
        print("Automatisk på denne Mac: \(automatic) (\(all[automatic]?.name ?? "?")), opslag i: " + chain(automatic).joined(separator: " → ") + " → da")
        let english = all["en"]?.texts ?? [:]
        for l in listed {
            // (a variant holds only what differs from its language: what it lacks comes from there)
            let variant = base(l.code) != l.code
            let missing = l.code == "da" || variant ? [] : english.keys.filter { l.texts[$0] == nil }.sorted()
            let unknown = l.texts.keys.filter { english[$0] == nil }.sorted()
            print("  \(l.code)  \(l.name): \(l.texts.count) tekster" + (missing.isEmpty ? "" : ", mangler \(missing.count)") + (unknown.isEmpty ? "" : ", \(unknown.count) ukendte"))
            for m in missing { print("      mangler: \(m)") }
            for u in unknown { print("      ukendt (ikke i en.ini): \(u)") }
        }
    }
}

/// A menu text in the user's language (see Lang). {0}, {1} … are replaced by the arguments.
func L(_ da: String, _ args: Any...) -> String {
    var s = Lang.text(da)
    for (i, a) in args.enumerated() { s = s.replacingOccurrences(of: "{\(i)}", with: "\(a)") }
    return s
}
