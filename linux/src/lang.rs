//! The menu's texts in the user's language. The texts in the code are Danish (`text.rs`), and the Danish text is
//! the key: a language is a file `assets/sprog/xx.ini` with lines "Danish text = text in that language" (see the
//! README there). A file can also be a regional variant, `xx-YY.ini` (es-MX.ini: Spanish as in Mexico), holding
//! only the texts that differ from its language's.
//!
//! Every text falls back down a chain, as is usual for translations: the variant (es-mx), its language (es),
//! English, and last the Danish key itself.
//!
//! The setting `Language` is empty for automatic (the default: the first of the user's languages that has a file,
//! its regional variant before the language itself (es-MX, then es), else English) or a language's code when the user has chosen in the menu "Sprog".
//! The same on macOS (`Lang.swift`) and Windows (`src/Lang.cs`), from the same files.

use std::collections::HashMap;
use std::sync::{OnceLock, RwLock};

pub struct Language {
    pub code: String,
    pub name: String,
    texts: HashMap<String, String>,
}

/// The app's own files, compiled in. A new file in `assets/sprog` must be added here (`tools/sprog-check.py`
/// says so when one is missing).
const BUILT_IN: [(&str, &str); 11] = [
    ("da", include_str!("../../assets/sprog/da.ini")),
    ("en", include_str!("../../assets/sprog/en.ini")),
    ("de", include_str!("../../assets/sprog/de.ini")),
    ("es", include_str!("../../assets/sprog/es.ini")),
    ("es-mx", include_str!("../../assets/sprog/es-MX.ini")),
    ("fr", include_str!("../../assets/sprog/fr.ini")),
    ("it", include_str!("../../assets/sprog/it.ini")),
    ("nl", include_str!("../../assets/sprog/nl.ini")),
    ("pt", include_str!("../../assets/sprog/pt.ini")),
    ("pt-br", include_str!("../../assets/sprog/pt-BR.ini")),
    ("sv", include_str!("../../assets/sprog/sv.ini")),
];

/// Every language there is a file for, by code.
fn all() -> &'static HashMap<String, Language> {
    static ALL: OnceLock<HashMap<String, Language>> = OnceLock::new();
    ALL.get_or_init(|| {
        let mut found = HashMap::new();
        for (code, text) in BUILT_IN {
            found.insert(code.to_string(), parse(code, text));
        }
        // the user's own files, in a folder "sprog" beside the settings file: a user's file wins over the app's
        let dir = crate::settings::file_path().with_file_name("sprog");
        if let Ok(entries) = std::fs::read_dir(dir) {
            for path in entries.flatten().map(|e| e.path()) {
                if path.extension().and_then(|e| e.to_str()) != Some("ini") {
                    continue;
                }
                let Some(code) = path.file_stem().and_then(|s| s.to_str()).map(normal) else { continue };
                if let Ok(text) = std::fs::read_to_string(&path) {
                    let language = parse(&code, &text);
                    found.insert(code, language);
                }
            }
        }
        found
    })
}

/// A language's code as the files and the setting use it: lower case, a variant with "-" (es_MX, es-MX → es-mx).
pub fn normal(code: &str) -> String {
    code.to_lowercase().replace('_', "-")
}

/// The language a variant belongs to (es-mx → es); a language is its own.
pub fn base(code: &str) -> &str {
    code.split('-').next().unwrap_or(code)
}

/// Where a text is looked up, in order: the code, its language (for a variant), English. Danish ends every chain:
/// its texts are the keys themselves.
pub fn chain(code: &str) -> Vec<String> {
    let mut c = vec![code.to_string()];
    if base(code) != code {
        c.push(base(code).to_string());
    }
    if !c.iter().any(|x| x == "en") {
        c.push("en".to_string());
    }
    c
}

/// The codes a language could have a file under, the most particular first: (es, MX) → es-mx, es.
fn candidates(language: &str, region: Option<&str>) -> Vec<String> {
    let mut c: Vec<String> = region.map(|r| normal(&format!("{language}-{r}"))).into_iter().collect();
    c.push(normal(language));
    c
}

/// "Danish text = translation" per line; "#" starts a comment; "@name" is the language's own name.
pub fn parse(code: &str, text: &str) -> Language {
    let mut l = Language { code: code.to_string(), name: code.to_string(), texts: HashMap::new() };
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('#') {
            continue;
        }
        let Some((key, value)) = line.split_once(" = ") else { continue };
        let (key, value) = (key.trim(), value.trim());
        if key == "@name" {
            l.name = value.to_string();
        } else if !key.is_empty() && !value.is_empty() {
            l.texts.insert(key.to_string(), value.to_string());
        }
    }
    l
}

/// The languages for the menu as (code, name): Danish and English first, then by name.
pub fn listed() -> Vec<(String, String)> {
    let rank = |code: &str| match code {
        "da" => 0,
        "en" => 1,
        _ => 2,
    };
    let mut list: Vec<(String, String)> = all().values().map(|l| (l.code.clone(), l.name.clone())).collect();
    list.sort_by(|a, b| rank(&a.0).cmp(&rank(&b.0)).then_with(|| a.1.to_lowercase().cmp(&b.1.to_lowercase())));
    list
}

pub fn name_of(code: &str) -> String {
    all().get(code).map_or_else(|| code.to_string(), |l| l.name.clone())
}

/// The first of the user's languages that there is a file for, its regional variant first (es-MX, then es);
/// English when none of them has one.
pub fn automatic() -> &'static str {
    static AUTOMATIC: OnceLock<String> = OnceLock::new();
    AUTOMATIC.get_or_init(|| {
        crate::folk::languages()
            .iter()
            .flat_map(|(language, region)| candidates(language, region.as_deref()))
            .find(|c| all().contains_key(c))
            .unwrap_or_else(|| "en".to_string())
    })
}

/// The setting `Language` (set when the settings are read and when the user chooses in the menu). The tray runs on
/// its own thread, so it is shared.
static SETTING: RwLock<String> = RwLock::new(String::new());

pub fn select(setting: &str) {
    if let Ok(mut s) = SETTING.write() {
        if *s != setting {
            *s = setting.to_string();
        }
    }
}

/// The language in use.
pub fn code() -> String {
    let setting = SETTING.read().map(|s| s.clone()).unwrap_or_default();
    if !setting.is_empty() && all().contains_key(&setting) {
        setting
    } else {
        automatic().to_string()
    }
}

/// A menu text in the user's language. A text that is not a key (a name, a number) comes back as it is.
pub fn tr(da: &str) -> String {
    for c in chain(&code()) {
        if base(&c) == "da" {
            break;
        }
        if let Some(t) = all().get(&c).and_then(|l| l.texts.get(da)) {
            return t.clone();
        }
    }
    da.to_string()
}

/// As `tr`, with {0}, {1} … replaced by the arguments.
pub fn trf(da: &str, args: &[&str]) -> String {
    let mut s = tr(da);
    for (i, a) in args.iter().enumerate() {
        s = s.replace(&format!("{{{i}}}"), a);
    }
    s
}

/// Test aid (`--sprog-test`): the languages found, the automatic choice, and what each lacks against English.
pub fn test_report() -> String {
    let mut out = format!(
        "Automatic on this machine: {} ({}), looked up in: {} → da\n",
        automatic(),
        name_of(automatic()),
        chain(automatic()).join(" → ")
    );
    let english = all().get("en");
    for (code, name) in listed() {
        let Some(l) = all().get(&code) else { continue };
        // (a variant holds only what differs from its language: what it lacks comes from there)
        let mut missing: Vec<&String> = match english {
            Some(en) if code != "da" && base(&code) == code => en.texts.keys().filter(|k| !l.texts.contains_key(*k)).collect(),
            _ => Vec::new(),
        };
        missing.sort();
        out += &format!("  {code}  {name}: {} texts", l.texts.len());
        if !missing.is_empty() {
            out += &format!(", {} missing", missing.len());
        }
        out += "\n";
        for m in missing {
            out += &format!("      missing: {m}\n");
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_variant_falls_back_to_its_language_then_english() {
        assert_eq!(chain("es-mx"), ["es-mx", "es", "en"]);
        assert_eq!(chain("de"), ["de", "en"]);
        assert_eq!(chain("en-gb"), ["en-gb", "en"]);
        assert_eq!(candidates("es", Some("MX")), ["es-mx", "es"]);
        assert_eq!(candidates("es", None), ["es"]);
        // the Mexican file holds only what differs: the rest is Spanish
        let mx = parse("es-mx", BUILT_IN.iter().find(|b| b.0 == "es-mx").unwrap().1);
        let en = parse("en", BUILT_IN[1].1);
        assert!(mx.texts.len() < en.texts.len());
        for key in mx.texts.keys() {
            assert!(en.texts.contains_key(key), "es-MX.ini has a text en.ini does not: {key}");
        }
    }

    #[test]
    fn parse_reads_name_and_texts() {
        let l = parse("xx", "# comment\n@name = Xish\nSnevejr = Snow = fall\n\nno separator here\nTom = \n");
        assert_eq!(l.name, "Xish");
        assert_eq!(l.texts.get("Snevejr").map(String::as_str), Some("Snow = fall"));
        assert_eq!(l.texts.len(), 1);
    }

    #[test]
    fn every_built_in_language_has_every_english_text() {
        let en = parse("en", BUILT_IN[1].1);
        assert!(en.texts.len() > 100);
        for (code, text) in BUILT_IN {
            if code == "da" || code == "en" || base(code) != code {
                continue;
            }
            let l = parse(code, text);
            for key in en.texts.keys() {
                assert!(l.texts.contains_key(key), "{code} lacks: {key}");
            }
        }
    }

    #[test]
    fn the_menu_texts_are_in_the_english_file() {
        let en = parse("en", BUILT_IN[1].1);
        for key in crate::text::MENU_WALKERS.iter().chain(&crate::text::MENU_WALKER_COUNT).chain(&crate::text::FOLK) {
            assert!(en.texts.contains_key(*key), "en.ini lacks: {key}");
        }
        for key in [crate::text::MENU_LANGUAGE, crate::text::MENU_SNOW, crate::text::QUIT, crate::text::MENU_AUTOSTART] {
            assert!(en.texts.contains_key(key), "en.ini lacks: {key}");
        }
    }
}
