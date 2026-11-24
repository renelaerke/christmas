import Foundation

/// The menu's texts in the user's language. The texts in the code are Danish, and the Danish text is the key: a
/// language is a file `assets/sprog/xx.ini` with lines "Danish text = text in that language" (see the README
/// there). A text a language lacks is shown in English, and one English lacks in Danish.
///
/// The setting `Language` is empty for automatic (the default: the first of the user's preferred languages that
/// has a file, else English) or a language's code when the user has chosen in the menu "Sprog".
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
                let code = file.deletingPathExtension().lastPathComponent.lowercased()
                found[code] = parse(code, text)
            }
        }
        return found
    }()

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

    /// The first of the user's preferred languages that there is a file for; English when none of them has one.
    /// JULE_LOCALE=de_DE pretends to be that locale (for tests).
    static let automatic: String = {
        var wanted = Locale.preferredLanguages.compactMap { Locale(identifier: $0).language.languageCode?.identifier }
        if let fake = ProcessInfo.processInfo.environment["JULE_LOCALE"], !fake.isEmpty {
            wanted = [Locale(identifier: fake).language.languageCode?.identifier].compactMap { $0 }
        }
        return wanted.map { $0.lowercased() }.first { all[$0] != nil } ?? "en"
    }()

    /// The setting `Language` (set when the settings are read and when the user chooses in the menu).
    nonisolated(unsafe) static var setting = ""
    /// The language in use.
    static var code: String { all[setting] != nil ? setting : automatic }

    static func text(_ da: String) -> String {
        let c = code
        if c == "da" { return da }
        return all[c]?.texts[da] ?? all["en"]?.texts[da] ?? da
    }

    /// Test aid (--sprog-test): the languages found, the automatic choice, and what each lacks against English.
    static func test() {
        print("Automatisk på denne Mac: \(automatic) (\(all[automatic]?.name ?? "?"))")
        let english = all["en"]?.texts ?? [:]
        for l in listed {
            let missing = l.code == "da" ? [] : english.keys.filter { l.texts[$0] == nil }.sorted()
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
