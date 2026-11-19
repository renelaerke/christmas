//! Settings, saved in `$XDG_CONFIG_HOME/JuleHygge/settings.ini` (default `~/.config/JuleHygge/settings.ini`).
//!
//! Same keys, defaults and limits as `src/Settings.cs`, so a settings file can be copied between Windows and Linux.
//! The keys in the file are a shared format and keep their names (e.g. `Nisser`, `NisseCount` for the elves).
//! New fields must have a default, so old files keep working. `JULE_SETTINGS=<path>` uses another file, so tests
//! never touch the real settings.

use std::collections::{BTreeSet, HashMap};
use std::path::PathBuf;

use chrono::NaiveDate;

#[derive(Clone, Debug, PartialEq)]
pub struct Settings {
    pub snow: bool,
    pub snow_ground: bool,
    pub santa: bool,
    /// Elves (Danish "nisser") walking on the ground. Key `Nisser`.
    pub elves: bool,
    pub lights: bool,
    pub pause_fullscreen: bool,
    pub snowman: bool,
    pub all_screens: bool,
    pub plow: bool,
    pub window_snow: bool,
    /// Sound is always off by default.
    pub sound: bool,
    pub plow_sound: bool,
    /// 0 light, 1 normal, 2 snowstorm, 3 changing weather (the default).
    pub snow_level: i32,
    /// Elves per screen. Key `NisseCount`.
    pub elf_count: i32,
    /// 0 off, 1 always on, 2 only on battery.
    pub power_save: i32,
    /// 0 low, 1 medium, 2 high.
    pub sound_level: i32,
    /// Frames per second while the scene is calm: 12, 20, 30 or 60.
    pub frame_rate: i32,
    pub auto_update: bool,
    /// The version that ran last time, to announce an update.
    pub last_version: String,
    pub snowman_seen_stage: i32,
    pub calendar_year: i32,
    pub first_run: Option<NaiveDate>,
    pub last_door_notice: Option<NaiveDate>,
    pub opened_doors: BTreeSet<i32>,
    /// The file existed but could not be read: run on defaults and never save over the user's file.
    load_failed: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            snow: true,
            snow_ground: true,
            santa: true,
            elves: true,
            lights: true,
            pause_fullscreen: true,
            snowman: true,
            all_screens: true,
            plow: true,
            window_snow: true,
            sound: false,
            plow_sound: false,
            snow_level: 3,
            elf_count: 3,
            power_save: 2,
            sound_level: 1,
            frame_rate: 20,
            auto_update: true,
            last_version: String::new(),
            snowman_seen_stage: 0,
            calendar_year: 0,
            first_run: None,
            last_door_notice: None,
            opened_doors: BTreeSet::new(),
            load_failed: false,
        }
    }
}

pub fn file_path() -> PathBuf {
    if let Some(p) = std::env::var_os("JULE_SETTINGS").filter(|p| !p.is_empty()) {
        let p = PathBuf::from(p);
        return if p.is_absolute() { p } else { std::env::current_dir().unwrap_or_default().join(p) };
    }
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
        .unwrap_or_else(std::env::temp_dir);
    base.join("JuleHygge").join("settings.ini")
}

impl Settings {
    pub fn load() -> Self {
        let path = file_path();
        match std::fs::read_to_string(&path) {
            Ok(text) => Self::parse(&text),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Settings::default(),
            Err(e) => {
                crate::log::error(&format!("cannot read {}: {e}; using defaults and not saving", path.display()));
                Settings { load_failed: true, ..Settings::default() }
            }
        }
    }

    pub fn parse(text: &str) -> Self {
        let mut d = HashMap::new();
        for line in text.lines() {
            if let Some(i) = line.find('=') {
                if i > 0 {
                    d.insert(line[..i].trim().to_string(), line[i + 1..].trim().to_string());
                }
            }
        }
        let def = Settings::default();
        let b = |k: &str, v: bool| d.get(k).map(|s| s == "1").unwrap_or(v);
        let i = |k: &str, v: i32| d.get(k).and_then(|s| s.parse::<i32>().ok()).unwrap_or(v);
        let date = |k: &str| d.get(k).and_then(|s| NaiveDate::parse_from_str(s, "%Y-%m-%d").ok());
        let mut frame_rate = i("FrameRate", def.frame_rate);
        if ![12, 20, 30, 60].contains(&frame_rate) {
            frame_rate = 20;
        }
        Settings {
            snow: b("Snow", def.snow),
            snow_ground: b("SnowGround", def.snow_ground),
            santa: b("Santa", def.santa),
            elves: b("Nisser", def.elves),
            lights: b("Lights", def.lights),
            pause_fullscreen: b("PauseFullscreen", def.pause_fullscreen),
            snowman: b("Snowman", def.snowman),
            all_screens: b("AllScreens", def.all_screens),
            plow: b("Plow", def.plow),
            window_snow: b("WindowSnow", def.window_snow),
            sound: b("Sound", def.sound),
            plow_sound: b("PlowSound", def.plow_sound),
            sound_level: i("SoundLevel", def.sound_level).clamp(0, 2),
            frame_rate,
            snow_level: i("SnowLevel", def.snow_level).clamp(0, 3),
            elf_count: i("NisseCount", def.elf_count).clamp(1, 12),
            power_save: i("PowerSave", def.power_save).clamp(0, 2),
            auto_update: b("AutoUpdate", def.auto_update),
            last_version: d.get("LastVersion").cloned().unwrap_or_default(),
            snowman_seen_stage: i("SnowmanSeenStage", 0),
            calendar_year: i("CalendarYear", 0),
            first_run: date("FirstRun"),
            last_door_notice: date("LastDoorNotice"),
            opened_doors: d
                .get("OpenedDoors")
                .map(|s| {
                    s.split(',').filter_map(|p| p.trim().parse::<i32>().ok()).filter(|n| (1..=24).contains(n)).collect()
                })
                .unwrap_or_default(),
            load_failed: false,
        }
    }

    pub fn to_ini(&self) -> String {
        let b = |v: bool| if v { "1" } else { "0" };
        let ds = |d: &Option<NaiveDate>| d.map(|d| d.format("%Y-%m-%d").to_string()).unwrap_or_default();
        let doors: Vec<String> = self.opened_doors.iter().map(|n| n.to_string()).collect();
        let lines = [
            format!("Snow={}", b(self.snow)),
            format!("SnowGround={}", b(self.snow_ground)),
            format!("Santa={}", b(self.santa)),
            format!("Nisser={}", b(self.elves)),
            format!("Lights={}", b(self.lights)),
            format!("PauseFullscreen={}", b(self.pause_fullscreen)),
            format!("Snowman={}", b(self.snowman)),
            format!("AllScreens={}", b(self.all_screens)),
            format!("Plow={}", b(self.plow)),
            format!("WindowSnow={}", b(self.window_snow)),
            format!("Sound={}", b(self.sound)),
            format!("PlowSound={}", b(self.plow_sound)),
            format!("SoundLevel={}", self.sound_level),
            format!("SnowLevel={}", self.snow_level),
            format!("NisseCount={}", self.elf_count),
            format!("PowerSave={}", self.power_save),
            format!("FrameRate={}", self.frame_rate),
            format!("AutoUpdate={}", b(self.auto_update)),
            format!("LastVersion={}", self.last_version),
            format!("SnowmanSeenStage={}", self.snowman_seen_stage),
            format!("CalendarYear={}", self.calendar_year),
            format!("FirstRun={}", ds(&self.first_run)),
            format!("LastDoorNotice={}", ds(&self.last_door_notice)),
            format!("OpenedDoors={}", doors.join(",")),
        ];
        let mut s = lines.join("\n");
        s.push('\n');
        s
    }

    /// Takes over the fields the tray menu changes, leaving what the app itself keeps (opened doors, the
    /// snowman's progress, dates) as it is. Returns the old values, so the caller can see what changed. The caller
    /// saves.
    pub fn take_menu_fields(&mut self, m: &Settings) -> Settings {
        let old = self.clone();
        self.snow = m.snow;
        self.snow_level = m.snow_level;
        self.snow_ground = m.snow_ground;
        self.snowman = m.snowman;
        self.santa = m.santa;
        self.plow = m.plow;
        self.sound = m.sound;
        self.plow_sound = m.plow_sound;
        self.sound_level = m.sound_level;
        self.elves = m.elves;
        self.elf_count = m.elf_count;
        self.power_save = m.power_save;
        self.frame_rate = m.frame_rate;
        self.lights = m.lights;
        self.all_screens = m.all_screens;
        self.pause_fullscreen = m.pause_fullscreen;
        self.window_snow = m.window_snow;
        self.auto_update = m.auto_update;
        old
    }

    /// Writes a temp file and renames it over the old one, so a crash mid-write never leaves half a file.
    pub fn save(&self) {
        if self.load_failed {
            return;
        }
        let path = file_path();
        let result = (|| -> std::io::Result<()> {
            if let Some(dir) = path.parent() {
                std::fs::create_dir_all(dir)?;
            }
            let mut tmp = path.clone().into_os_string();
            tmp.push(".tmp");
            std::fs::write(&tmp, self.to_ini())?;
            std::fs::rename(&tmp, &path)
        })();
        if let Err(e) = result {
            crate::log::error(&format!("cannot save {}: {e}", path.display()));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_file_gives_defaults() {
        assert_eq!(Settings::parse(""), Settings::default());
    }

    #[test]
    fn round_trip() {
        let s = Settings {
            snow_level: 2,
            frame_rate: 30,
            sound: true,
            last_version: "1.5.0".into(),
            first_run: NaiveDate::from_ymd_opt(2026, 11, 20),
            opened_doors: [1, 2, 24].into_iter().collect(),
            ..Default::default()
        };
        assert_eq!(Settings::parse(&s.to_ini()), s);
    }

    #[test]
    fn menu_changes_keep_the_doors() {
        let mut app = Settings { opened_doors: [1, 2].into_iter().collect(), ..Default::default() };
        // the menu's copy is older: it has not seen door 2 being opened
        let menu = Settings { opened_doors: [1].into_iter().collect(), sound: true, ..Default::default() };
        let old = app.take_menu_fields(&menu);
        assert!(!old.sound && app.sound);
        assert_eq!(app.opened_doors.len(), 2);
    }

    #[test]
    fn windows_file_with_crlf_and_bad_values() {
        let text = "Snow=0\r\nFrameRate=25\r\nSnowLevel=9\r\nNisseCount=0\r\nOpenedDoors=3,x,25,1\r\nFirstRun=2026-11-01\r\nUnknown=1\r\n";
        let s = Settings::parse(text);
        assert!(!s.snow);
        assert_eq!(s.frame_rate, 20);
        assert_eq!(s.snow_level, 3);
        assert_eq!(s.elf_count, 1);
        assert_eq!(s.opened_doors.iter().copied().collect::<Vec<_>>(), vec![1, 3]);
        assert_eq!(s.first_run, NaiveDate::from_ymd_opt(2026, 11, 1));
    }
}
