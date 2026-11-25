//! Who walks on the panel in the Christmas theme: the Nordic nisse (red hat, grey clothes, white beard), or the
//! Christmas elf most of the rest of the world expects (green and red, pointed ears and cap, striped stockings, no
//! beard). They are the same walkers in everything but looks (`layer/elves.rs`: `draw_elf` and `alf`). As
//! `Folk.swift` on macOS and `src/Folk.cs` on Windows, with the same rule and the same setting.
//!
//! The setting `Folk` is 0 = automatic (the default: decided by the user's language and region, below), 1 = nisser
//! or 2 = alfer, when the user has chosen in the menu because the automatic choice was wrong for them.
//!
//! The rest of the Linux code calls every walker an "elf" (the nisse included), so the two folks keep their Danish
//! names here.

use std::sync::OnceLock;

/// The Nordic nisse; the Christmas elf; and three nisse-like figures with their own looks: the German Wichtel (a
/// tall felt cap pulled down over the eyes, a long beard, hardly any legs), the Dutch kabouter (a stiff cone hat, a
/// short beard, clogs) and the Estonian päkapikk (all in red with white trim, no beard).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Folk {
    Nisser,
    Alfer,
    Wichtel,
    Kabouter,
    Paekapikk,
}

/// In the order of the setting's values 1 to 5 (and of `text::FOLK`).
pub const ALL: [Folk; 5] = [Folk::Nisser, Folk::Alfer, Folk::Wichtel, Folk::Kabouter, Folk::Paekapikk];

impl Folk {
    /// Index into `ALL` and `text::FOLK`; the setting's value is one more.
    pub fn index(self) -> usize {
        ALL.iter().position(|f| *f == self).unwrap_or(0)
    }
}

/// Who gets which figure: by language first, then by region; everyone else gets elves. These two tables are the
/// whole rule (the same as in `Folk.swift` and `src/Folk.cs`).
/// The Nordic ones: the nisse and its close relatives (tomte, tonttu, jólasveinar).
const BY_LANGUAGE: [(&str, Folk); 13] = [
    ("da", Folk::Nisser),
    ("nb", Folk::Nisser),
    ("nn", Folk::Nisser),
    ("no", Folk::Nisser),
    ("sv", Folk::Nisser),
    ("fi", Folk::Nisser),
    ("fo", Folk::Nisser),
    ("is", Folk::Nisser),
    ("kl", Folk::Nisser),
    ("se", Folk::Nisser),
    ("de", Folk::Wichtel),
    ("nl", Folk::Kabouter),
    ("et", Folk::Paekapikk),
];
const BY_REGION: [(&str, Folk); 15] = [
    ("DK", Folk::Nisser),
    ("NO", Folk::Nisser),
    ("SE", Folk::Nisser),
    ("FI", Folk::Nisser),
    ("FO", Folk::Nisser),
    ("GL", Folk::Nisser),
    ("IS", Folk::Nisser),
    ("AX", Folk::Nisser),
    ("SJ", Folk::Nisser),
    ("DE", Folk::Wichtel),
    ("AT", Folk::Wichtel),
    ("CH", Folk::Wichtel),
    ("LI", Folk::Wichtel),
    ("NL", Folk::Kabouter),
    ("EE", Folk::Paekapikk),
];

fn lookup(table: &[(&str, Folk)], key: &str) -> Option<Folk> {
    table.iter().find(|(k, _)| *k == key).map(|(_, f)| *f)
}

/// The language decides when it has a figure of its own: a Dane abroad keeps the nisser. Otherwise the region
/// does: someone living in Denmark with the desktop set to English gets nisser too.
pub fn automatic(language: Option<&str>, region: Option<&str>) -> Folk {
    language
        .and_then(|l| lookup(&BY_LANGUAGE, &l.to_lowercase()))
        .or_else(|| region.and_then(|r| lookup(&BY_REGION, &r.to_uppercase())))
        .unwrap_or(Folk::Alfer)
}

/// The language and region of a locale name: "da_DK.UTF-8", "en_US", "sv_SE@euro", "zh-Hans_CN". The language is
/// the first part, the region the last one of two letters. "C" and "POSIX" have neither.
pub fn split(id: &str) -> (Option<String>, Option<String>) {
    let id = id.split(['.', '@']).next().unwrap_or("");
    if id.is_empty() || id == "C" || id == "POSIX" {
        return (None, None);
    }
    let parts: Vec<&str> = id.split(['_', '-']).collect();
    let region = match parts.last() {
        Some(last) if parts.len() > 1 && last.len() == 2 => Some(last.to_string()),
        _ => None,
    };
    (Some(parts[0].to_string()), region)
}

fn env(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.is_empty())
}

/// The desktop's language (`LANGUAGE`'s first choice, else `LC_ALL`, `LC_MESSAGES`, `LANG`) and the country of the
/// regional formats (`LC_ALL`, else `LC_TIME`, `LC_MONETARY`, `LANG`: the desktop's "Formats" setting sets the
/// `LC_` ones). `JULE_LOCALE=en_US` pretends to be that locale (for tests).
fn system_locale() -> (Option<String>, Option<String>) {
    if let Some(fake) = env("JULE_LOCALE") {
        return split(&fake);
    }
    let language = env("LANGUAGE")
        .and_then(|l| l.split(':').next().map(str::to_string))
        .into_iter()
        .chain(["LC_ALL", "LC_MESSAGES", "LANG"].into_iter().filter_map(env))
        .find_map(|id| split(&id).0);
    let region = ["LC_ALL", "LC_TIME", "LC_MONETARY", "LANG"].into_iter().filter_map(env).find_map(|id| split(&id).1);
    (language, region)
}

/// The user's languages in order of preference (`LANGUAGE`'s list, then `LC_ALL`, `LC_MESSAGES`, `LANG`), each with
/// its region when it has one (es_MX), for the menu's language (`lang.rs`). `JULE_LOCALE=es_MX` pretends to be that
/// locale.
pub fn languages() -> Vec<(String, Option<String>)> {
    if let Some(fake) = env("JULE_LOCALE") {
        let (language, region) = split(&fake);
        return language.map(|l| (l, region)).into_iter().collect();
    }
    let mut ids: Vec<String> = env("LANGUAGE").map(|l| l.split(':').map(str::to_string).collect()).unwrap_or_default();
    ids.extend(["LC_ALL", "LC_MESSAGES", "LANG"].into_iter().filter_map(env));
    ids.iter()
        .filter_map(|id| {
            let (language, region) = split(id);
            language.map(|l| (l, region))
        })
        .collect()
}

/// The automatic choice on this machine. Read once: a change of language or region takes effect at the next start.
pub fn system() -> Folk {
    static SYSTEM: OnceLock<Folk> = OnceLock::new();
    *SYSTEM.get_or_init(|| {
        let (language, region) = system_locale();
        automatic(language.as_deref(), region.as_deref())
    })
}

/// Which carnival the Karneval theme shows (setting `Carnival`): Rio's samba parade is the first and the default;
/// the Rhineland's street carnival (Cologne, Düsseldorf, Mainz) is its German form.
pub const CARNIVAL_RIO: i32 = 1;
pub const CARNIVAL_RHEIN: i32 = 2;

/// The automatic carnival on this machine: the Rhineland's where German is the language or the country, by the
/// rule that gives the Wichtel, so the two always agree; Rio's everywhere else.
pub fn carnival_system() -> i32 {
    if system() == Folk::Wichtel {
        CARNIVAL_RHEIN
    } else {
        CARNIVAL_RIO
    }
}

/// The setting's value as the carnival to show (0 or anything unknown = automatic).
pub fn carnival_chosen(setting: i32) -> i32 {
    match setting {
        CARNIVAL_RIO | CARNIVAL_RHEIN => setting,
        _ => carnival_system(),
    }
}

/// The setting's value as the folk to draw (0 or anything unknown = automatic).
pub fn chosen(setting: i32) -> Folk {
    match setting {
        1..=5 => ALL[setting as usize - 1],
        _ => system(),
    }
}

fn name(folk: Folk) -> &'static str {
    ["nisser", "alfer", "wichtel", "kabouter", "paekapikk"][folk.index()]
}

/// Test aid (`--folk-test`): what this machine's language and region give, and the rule for a list of locales.
pub fn test_report() -> String {
    let (language, region) = system_locale();
    let mut out = format!(
        "This machine: language {}, region {} -> {}\n",
        language.as_deref().unwrap_or("?"),
        region.as_deref().unwrap_or("?"),
        name(system())
    );
    for id in [
        "da_DK", "da_US", "en_DK", "nb_NO", "sv_SE", "fi_FI", "is_IS", "fo_FO", "kl_GL", "en_US", "en_GB", "de_DE",
        "de_AT", "en_DE", "da_DE", "fr_CH", "nl_NL", "nl_BE", "et_EE", "fr_FR", "es_MX", "pt_BR", "ja_JP",
        "zh-Hans_CN", "pl_PL", "en_AU",
    ] {
        let (language, region) = split(id);
        out += &format!("  {id:<11} {}\n", name(automatic(language.as_deref(), region.as_deref())));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn of(id: &str) -> Folk {
        let (language, region) = split(id);
        automatic(language.as_deref(), region.as_deref())
    }

    #[test]
    fn nordic_language_or_region_gives_nisser() {
        for id in ["da_DK.UTF-8", "da_US", "en_DK.UTF-8", "nb_NO", "sv_SE@euro", "fi_FI", "is_IS", "fo_FO", "kl_GL"] {
            assert_eq!(of(id), Folk::Nisser, "{id}");
        }
    }

    #[test]
    fn everywhere_else_gives_alfer() {
        for id in ["en_US.UTF-8", "en_GB", "fr_FR", "ja_JP", "zh-Hans_CN", "C", "POSIX", "", "en"] {
            assert_eq!(of(id), Folk::Alfer, "{id}");
        }
    }

    #[test]
    fn the_nisse_like_figures_have_their_countries() {
        for (id, folk) in [
            ("de_DE.UTF-8", Folk::Wichtel),
            ("de_AT", Folk::Wichtel),
            ("en_DE", Folk::Wichtel),
            ("fr_CH", Folk::Wichtel),
            ("nl_NL", Folk::Kabouter),
            ("nl_BE", Folk::Kabouter),
            ("et_EE", Folk::Paekapikk),
            ("da_DE", Folk::Nisser), // the language comes first
            ("de_DK", Folk::Wichtel),
        ] {
            assert_eq!(of(id), folk, "{id}");
        }
    }

    #[test]
    fn split_reads_language_and_region() {
        assert_eq!(split("da_DK.UTF-8"), (Some("da".into()), Some("DK".into())));
        assert_eq!(split("zh-Hans_CN"), (Some("zh".into()), Some("CN".into())));
        assert_eq!(split("en"), (Some("en".into()), None));
        assert_eq!(split("C.UTF-8"), (None, None));
    }

    #[test]
    fn the_setting_overrides_the_automatic_choice() {
        assert_eq!(chosen(1), Folk::Nisser);
        assert_eq!(chosen(2), Folk::Alfer);
        assert_eq!(chosen(5), Folk::Paekapikk);
        assert_eq!(Folk::Kabouter.index(), 3);
    }
}
