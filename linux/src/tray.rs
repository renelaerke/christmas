//! The snowflake icon in the panel (StatusNotifierItem): Ubuntu shows it through its AppIndicator extension,
//! Cinnamon (Mint) natively. Corresponds to the `NotifyIcon` and its menu in `src/Controller.cs`.
//!
//! Same items and Danish texts as the Windows menu (texts live in `text.rs`). Tray hosts deliver no double-clicks,
//! so "Send julemanden afsted nu!" is the way to call Santa; a left click opens the calendar where the host
//! supports it.
//!
//! The tray runs on its own thread. It keeps a copy of the settings for the checkmarks; a change sends the whole
//! copy to the main loop, which takes over the menu's fields (`Settings::take_menu_fields`) and saves.

use std::sync::mpsc::Sender;

use ksni::blocking::TrayMethods;
use ksni::menu::{CheckmarkItem, MenuItem, RadioGroup, RadioItem, StandardItem, SubMenu};

use crate::folk;
use crate::lang;
use crate::settings::Settings;
use crate::text;

pub enum TrayMsg {
    Quit,
    Calendar,
    Santa,
    Plow,
    Settings(Box<Settings>),
    Autostart(bool),
    CheckUpdate,
}

pub struct AppTray {
    tx: Sender<TrayMsg>,
    icons: Vec<ksni::Icon>,
    /// Shown greyed out at the top of the menu and in the tooltip (e.g. `text::NEEDS_COMPOSITOR`), or empty.
    pub status: String,
    pub cfg: Settings,
    pub snowman_stage: i32,
    /// "★ 12 dage til juleaften ★"
    pub countdown: String,
    pub autostart: bool,
}

pub type TrayHandle = ksni::blocking::Handle<AppTray>;

const ELF_COUNTS: [i32; 6] = [1, 2, 3, 5, 8, 12];
const FRAME_RATES: [i32; 4] = [12, 20, 30, 60];
/// Menu order of the power-save choices: off, on, only on battery (as on Windows).
const POWER_ORDER: [i32; 3] = [1, 2, 0];

impl AppTray {
    fn changed(&self) {
        let _ = self.tx.send(TrayMsg::Settings(Box::new(self.cfg.clone())));
    }
}

fn item(label: &str, msg: fn() -> TrayMsg) -> MenuItem<AppTray> {
    StandardItem {
        label: lang::tr(label),
        activate: Box::new(move |t: &mut AppTray| {
            let _ = t.tx.send(msg());
        }),
        ..Default::default()
    }
    .into()
}

fn disabled(label: String) -> MenuItem<AppTray> {
    StandardItem { label, enabled: false, ..Default::default() }.into()
}

/// The menu "Sprog": automatic (the desktop's own language, or English when there is no file for it), and every
/// language there is a file for, each under its own name. It also says "Language", so it can be found by someone
/// who cannot read the language chosen.
fn language_choice(current: &str) -> MenuItem<AppTray> {
    let languages = lang::listed();
    let mut codes = vec![String::new()];
    codes.extend(languages.iter().map(|l| l.0.clone()));
    let mut names = vec![text::menu_language_automatic(lang::name_of(lang::automatic()).as_str())];
    names.extend(languages.iter().map(|l| l.1.clone()));
    let mut label = lang::tr(text::MENU_LANGUAGE);
    if label != "Language" {
        label += " / Language";
    }
    SubMenu {
        label,
        submenu: vec![RadioGroup {
            selected: codes.iter().position(|c| c == current).unwrap_or(0),
            select: Box::new(move |t: &mut AppTray, i| {
                t.cfg.language = codes[i].clone();
                lang::select(&t.cfg.language);
                t.changed();
            }),
            options: names.into_iter().map(|label| RadioItem { label, ..Default::default() }).collect(),
        }
        .into()],
        ..Default::default()
    }
    .into()
}

/// A checkmark for one boolean setting.
fn toggle(label: String, checked: bool, field: fn(&mut Settings) -> &mut bool) -> MenuItem<AppTray> {
    CheckmarkItem {
        label: lang::tr(&label),
        checked,
        activate: Box::new(move |t: &mut AppTray| {
            let v = field(&mut t.cfg);
            *v = !*v;
            t.changed();
        }),
        ..Default::default()
    }
    .into()
}

/// A submenu where exactly one option is checked.
fn choice(
    label: &str,
    names: &[&str],
    values: &'static [i32],
    current: i32,
    field: fn(&mut Settings) -> &mut i32,
) -> MenuItem<AppTray> {
    SubMenu {
        label: lang::tr(label),
        submenu: vec![RadioGroup {
            selected: values.iter().position(|v| *v == current).unwrap_or(0),
            select: Box::new(move |t: &mut AppTray, i| {
                *field(&mut t.cfg) = values[i];
                t.changed();
            }),
            options: names.iter().map(|n| RadioItem { label: lang::tr(n), ..Default::default() }).collect(),
        }
        .into()],
        ..Default::default()
    }
    .into()
}

impl ksni::Tray for AppTray {
    fn id(&self) -> String {
        "julehygge".into()
    }

    fn title(&self) -> String {
        "JuleHygge".into()
    }

    fn icon_pixmap(&self) -> Vec<ksni::Icon> {
        self.icons.clone()
    }

    fn tool_tip(&self) -> ksni::ToolTip {
        let description = if self.status.is_empty() { self.countdown.clone() } else { lang::tr(&self.status) };
        ksni::ToolTip { title: "JuleHygge".into(), description, ..Default::default() }
    }

    /// Left click: the calendar.
    fn activate(&mut self, _x: i32, _y: i32) {
        let _ = self.tx.send(TrayMsg::Calendar);
    }

    fn menu(&self) -> Vec<MenuItem<Self>> {
        let c = &self.cfg;
        // (the menu's own copy of the settings says which language: the helpers below look every text up in it)
        lang::select(&c.language);
        let mut items: Vec<MenuItem<Self>> = Vec::new();
        if !self.status.is_empty() {
            items.push(disabled(lang::tr(&self.status)));
            items.push(MenuItem::Separator);
        }
        // The autumn theme: the calendar and the countdown belong to Christmas and are left out of the menu in
        // autumn; everything else has its autumn form and its autumn name.
        let autumn = c.theme == 1;
        if !autumn {
            items.push(item(text::MENU_CALENDAR, || TrayMsg::Calendar));
            items.push(disabled(self.countdown.clone()));
            items.push(MenuItem::Separator);
        }

        items.push(choice(text::MENU_THEME, &text::THEMES, &[0, 1], c.theme, |s| &mut s.theme));
        let snow = if autumn { text::MENU_LEAVES } else { text::MENU_SNOW };
        items.push(toggle(snow.into(), c.snow, |s| &mut s.snow));
        let (level, levels) = if autumn {
            (text::MENU_LEAF_LEVEL, &text::LEAF_LEVELS)
        } else {
            (text::MENU_SNOW_LEVEL, &text::SNOW_LEVELS)
        };
        items.push(choice(level, levels, &[0, 1, 2, 3], c.snow_level, |s| &mut s.snow_level));
        let ground = if autumn { text::MENU_LEAF_GROUND } else { text::MENU_SNOW_GROUND };
        items.push(toggle(ground.into(), c.snow_ground, |s| &mut s.snow_ground));
        let on_windows = if autumn { text::MENU_WINDOW_LEAVES } else { text::MENU_WINDOW_SNOW };
        items.push(toggle(on_windows.into(), c.window_snow, |s| &mut s.window_snow));
        let snowman = if autumn {
            text::menu_scarecrow(self.snowman_stage, crate::layer::SNOWMAN_MAX_STAGE)
        } else {
            text::menu_snowman(self.snowman_stage, crate::layer::SNOWMAN_MAX_STAGE)
        };
        items.push(toggle(snowman, c.snowman, |s| &mut s.snowman));
        // (the kite only exists in autumn)
        if autumn {
            items.push(toggle(text::MENU_KITE.into(), c.kite, |s| &mut s.kite));
        }
        items.push(MenuItem::Separator);

        let (santa, send) = if autumn {
            (text::MENU_GEESE, text::MENU_SEND_GEESE)
        } else {
            (text::MENU_SANTA, text::MENU_SEND_SANTA)
        };
        items.push(toggle(santa.into(), c.santa, |s| &mut s.santa));
        items.push(item(send, || TrayMsg::Santa));
        items.push(MenuItem::Separator);

        let (plow, send) = if autumn {
            (text::MENU_LEAF_COLLECTOR, text::MENU_SEND_LEAF_COLLECTOR)
        } else {
            (text::MENU_PLOW, text::MENU_SEND_PLOW)
        };
        items.push(toggle(plow.into(), c.plow, |s| &mut s.plow));
        items.push(item(send, || TrayMsg::Plow));
        items.push(MenuItem::Separator);

        // sound is off by default; each source is switched on separately
        let (sound, plow_sound) = if autumn {
            (text::MENU_GOOSE_SOUND, text::MENU_LEAF_COLLECTOR_SOUND)
        } else {
            (text::MENU_SOUND, text::MENU_PLOW_SOUND)
        };
        items.push(toggle(sound.into(), c.sound, |s| &mut s.sound));
        items.push(toggle(plow_sound.into(), c.plow_sound, |s| &mut s.plow_sound));
        items.push(choice(text::MENU_VOLUME, &text::VOLUMES, &[0, 1, 2], c.sound_level, |s| &mut s.sound_level));
        items.push(MenuItem::Separator);

        let (elves, elf_count) = if autumn {
            (text::MENU_ANIMALS, text::MENU_ANIMAL_COUNT)
        } else {
            let folk = folk::chosen(c.folk).index();
            (text::MENU_WALKERS[folk], text::MENU_WALKER_COUNT[folk])
        };
        items.push(toggle(elves.into(), c.elves, |s| &mut s.elves));
        let counts: Vec<String> = ELF_COUNTS.iter().map(|n| n.to_string()).collect();
        let counts: Vec<&str> = counts.iter().map(|s| s.as_str()).collect();
        items.push(choice(elf_count, &counts, &ELF_COUNTS, c.elf_count, |s| &mut s.elf_count));
        // Nisser or elves: automatic follows the language and region; the other two are for when that is wrong.
        // (in autumn animals walk here, so there is nothing to choose)
        if !autumn {
            let automatic = text::menu_folk_automatic(text::FOLK[folk::system().index()]);
            let mut names = vec![automatic.as_str()];
            names.extend(text::FOLK);
            items.push(choice(text::MENU_FOLK, &names, &[0, 1, 2, 3, 4, 5], c.folk, |s| &mut s.folk));
        }
        items.push(MenuItem::Separator);

        let power: Vec<&str> = POWER_ORDER.iter().map(|&v| text::POWER_SAVE[v as usize]).collect();
        items.push(choice(text::MENU_POWER_SAVE, &power, &POWER_ORDER, c.power_save, |s| &mut s.power_save));
        let rates = if autumn { &text::FRAME_RATES_AUTUMN } else { &text::FRAME_RATES };
        items.push(choice(text::MENU_FRAME_RATE, rates, &FRAME_RATES, c.frame_rate, |s| &mut s.frame_rate));
        let lights = if autumn { text::MENU_GARLAND } else { text::MENU_LIGHTS };
        items.push(toggle(lights.into(), c.lights, |s| &mut s.lights));
        items.push(toggle(text::MENU_ALL_SCREENS.into(), c.all_screens, |s| &mut s.all_screens));
        items.push(toggle(text::MENU_PAUSE_FULLSCREEN.into(), c.pause_fullscreen, |s| &mut s.pause_fullscreen));
        items.push(
            CheckmarkItem {
                label: lang::tr(text::MENU_AUTOSTART),
                checked: self.autostart,
                activate: Box::new(|t: &mut AppTray| {
                    let _ = t.tx.send(TrayMsg::Autostart(!t.autostart));
                }),
                ..Default::default()
            }
            .into(),
        );
        items.push(MenuItem::Separator);
        items.push(language_choice(&c.language));
        items.push(MenuItem::Separator);

        if crate::updater::is_release_build() {
            items.push(disabled(text::menu_version(&crate::updater::display(crate::updater::current()))));
            items.push(toggle(text::MENU_AUTO_UPDATE.into(), c.auto_update, |s| &mut s.auto_update));
            items.push(item(text::MENU_CHECK_UPDATE, || TrayMsg::CheckUpdate));
        } else {
            items.push(disabled(lang::tr(text::MENU_DEV_VERSION)));
        }
        items.push(MenuItem::Separator);
        items.push(
            StandardItem {
                label: lang::tr(text::QUIT),
                icon_name: "application-exit".into(),
                activate: Box::new(|t: &mut Self| {
                    let _ = t.tx.send(TrayMsg::Quit);
                }),
                ..Default::default()
            }
            .into(),
        );
        items
    }
}

/// Starts the tray icon. Without a tray host (or D-Bus) the app keeps running without it; it can then only be
/// stopped from a terminal (`pkill -x JuleHygge`).
pub fn spawn(
    tx: Sender<TrayMsg>,
    status: String,
    cfg: Settings,
    snowman_stage: i32,
    countdown: String,
    autostart: bool,
) -> Option<TrayHandle> {
    let mut icons = Vec::new();
    for size in [16, 22, 24, 32, 48, 64] {
        match crate::icon::argb_be(size) {
            Ok(data) => icons.push(ksni::Icon { width: size, height: size, data }),
            Err(e) => crate::log::error(&format!("icon {size}: {e}")),
        }
    }
    match (AppTray { tx, icons, status, cfg, snowman_stage, countdown, autostart }).spawn() {
        Ok(h) => Some(h),
        Err(e) => {
            crate::log::error(&format!("no tray icon: {e}"));
            None
        }
    }
}
