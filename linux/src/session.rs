//! Whether anyone can see the overlay, and whether the computer runs on battery. Corresponds to the
//! `SessionSwitch`/screen saver part of `src/Controller.cs`.
//!
//! A thread asks D-Bus once a second (polling also finds services that start later, and costs nothing next to
//! drawing):
//! - logind: the session's `LockedHint` (system bus);
//! - the screen saver's `GetActive`: Cinnamon, GNOME, and the freedesktop name used by Xfce and KDE (session bus).
//!   Only services that already run are asked, so no screen saver is started by D-Bus activation.
//!
//! Suspend needs no signal: the process is frozen while the computer sleeps, and the controller's frame-stall
//! check ends anything on its way when it wakes up. DPMS (display off) is read over X11 in `x11.rs`.
//!
//! The same thread shows notifications (`org.freedesktop.Notifications`, the balloon tips of Windows) and listens
//! for clicks on them: a click on the daily door notice opens the calendar.
//!
//! The battery is read from `/sys/class/power_supply`, which is what UPower reads too.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{Receiver, Sender, TryRecvError};
use std::sync::Arc;
use std::time::{Duration, Instant};

use futures_util::StreamExt;
use zbus::names::InterfaceName;
use zbus::zvariant::Value;
use zbus::Connection;

const SCREEN_SAVERS: [(&str, &str); 3] = [
    ("org.cinnamon.ScreenSaver", "/org/cinnamon/ScreenSaver"),
    ("org.gnome.ScreenSaver", "/org/gnome/ScreenSaver"),
    ("org.freedesktop.ScreenSaver", "/org/freedesktop/ScreenSaver"),
];

/// A notification to show. `opens_calendar`: clicking it opens the calendar.
pub struct Notice {
    pub title: String,
    pub body: String,
    pub opens_calendar: bool,
}

pub struct SessionWatch {
    locked: Arc<AtomicBool>,
    saver: Arc<AtomicBool>,
    notices: Sender<Notice>,
    clicks: Receiver<()>,
}

impl SessionWatch {
    pub fn locked(&self) -> bool {
        self.locked.load(Ordering::Relaxed)
    }
    pub fn screen_saver(&self) -> bool {
        self.saver.load(Ordering::Relaxed)
    }
    pub fn notify(&self, title: &str, body: &str, opens_calendar: bool) {
        crate::log::debug(&format!("notice: {title}: {body}"));
        let _ = self.notices.send(Notice { title: title.into(), body: body.into(), opens_calendar });
    }
    /// True once for each click on a notice that opens the calendar.
    pub fn calendar_clicked(&self) -> bool {
        let mut any = false;
        while self.clicks.try_recv().is_ok() {
            any = true;
        }
        any
    }
}

/// Starts the D-Bus thread. Without D-Bus the flags stay false and notices are dropped; the overlay simply keeps
/// running.
pub fn spawn() -> SessionWatch {
    let (locked, saver) = (Arc::new(AtomicBool::new(false)), Arc::new(AtomicBool::new(false)));
    let (notices, notice_rx) = std::sync::mpsc::channel();
    let (click_tx, clicks) = std::sync::mpsc::channel();
    let flags = (locked.clone(), saver.clone());
    let started = std::thread::Builder::new().name("session".into()).spawn(move || {
        let rt = match tokio::runtime::Builder::new_current_thread().enable_all().build() {
            Ok(rt) => rt,
            Err(e) => {
                crate::log::error(&format!("session watch: {e}"));
                return;
            }
        };
        rt.block_on(run(flags, notice_rx, click_tx));
    });
    if let Err(e) = started {
        crate::log::error(&format!("session watch: {e}"));
    }
    SessionWatch { locked, saver, notices, clicks }
}

/// The thread's loop: the lock and screen saver once a second, notices as they come, and clicks on them.
async fn run(flags: (Arc<AtomicBool>, Arc<AtomicBool>), notices: Receiver<Notice>, clicks: Sender<()>) {
    let (mut system, mut session) = (None, None);
    let mut actions: Option<zbus::MessageStream> = None;
    let mut calendar_notices: Vec<u32> = Vec::new();
    let mut next_poll = Instant::now();
    let icon = crate::icon::rgba(48).ok();
    loop {
        if Instant::now() >= next_poll {
            next_poll = Instant::now() + Duration::from_secs(1);
            poll(&flags, &mut system, &mut session).await;
            if actions.is_none() {
                if let Some(c) = session.as_ref() {
                    actions = action_stream(c).await.ok();
                }
            }
        }
        loop {
            match notices.try_recv() {
                Ok(n) => {
                    let Some(c) = session.as_ref() else { continue };
                    match show(c, &n, icon.as_deref()).await {
                        Ok(id) if n.opens_calendar => calendar_notices.push(id),
                        Ok(_) => {}
                        Err(e) => crate::log::error(&format!("notice: {e}")),
                    }
                }
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) => return,
            }
        }
        match actions.as_mut() {
            Some(stream) => {
                if let Ok(Some(Ok(msg))) = tokio::time::timeout(Duration::from_millis(250), stream.next()).await {
                    if let Ok((id, _key)) = msg.body().deserialize::<(u32, String)>() {
                        if calendar_notices.contains(&id) {
                            let _ = clicks.send(());
                        }
                    }
                }
            }
            None => tokio::time::sleep(Duration::from_millis(250)).await,
        }
    }
}

/// Clicks on notifications (`ActionInvoked`), from every app; `run` keeps only its own.
async fn action_stream(c: &Connection) -> zbus::Result<zbus::MessageStream> {
    let rule = zbus::MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .interface("org.freedesktop.Notifications")?
        .member("ActionInvoked")?
        .build();
    zbus::MessageStream::for_match_rule(rule, c, None).await
}

/// Shows a notice with the snowflake icon; returns its id.
async fn show(c: &Connection, n: &Notice, icon: Option<&[u8]>) -> zbus::Result<u32> {
    let mut hints: HashMap<&str, Value> = HashMap::new();
    hints.insert("desktop-entry", Value::from("julehygge"));
    if let Some(px) = icon {
        // (width, height, rowstride, has alpha, bits per sample, channels, RGBA bytes)
        hints.insert("image-data", Value::from((48i32, 48i32, 48 * 4i32, true, 8i32, 4i32, px.to_vec())));
    }
    let actions: Vec<&str> = if n.opens_calendar { vec!["default", crate::text::NOTICE_OPEN_CALENDAR] } else { vec![] };
    let reply = c
        .call_method(
            Some("org.freedesktop.Notifications"),
            "/org/freedesktop/Notifications",
            Some("org.freedesktop.Notifications"),
            "Notify",
            &("JuleHygge", 0u32, "", n.title.as_str(), n.body.as_str(), actions, hints, 6000i32),
        )
        .await?;
    reply.body().deserialize::<u32>()
}

/// One round of questions. A bus that cannot be reached is tried again on the next round.
async fn poll(
    flags: &(Arc<AtomicBool>, Arc<AtomicBool>),
    system: &mut Option<Connection>,
    session: &mut Option<Connection>,
) {
    if system.is_none() {
        *system = Connection::system().await.ok();
    }
    if session.is_none() {
        *session = Connection::session().await.ok();
    }
    if let Some(c) = system.as_ref() {
        let locked = locked_hint(c).await.unwrap_or(false);
        if flags.0.swap(locked, Ordering::Relaxed) != locked {
            crate::log::debug(&format!("session locked: {locked}"));
        }
    }
    if let Some(c) = session.as_ref() {
        let mut active = false;
        for (name, path) in SCREEN_SAVERS {
            if screen_saver_active(c, name, path).await.unwrap_or(false) {
                active = true;
                break;
            }
        }
        if flags.1.swap(active, Ordering::Relaxed) != active {
            crate::log::debug(&format!("screen saver active: {active}"));
        }
    }
}

/// logind's `LockedHint` for the session this process belongs to (`session/auto`).
async fn locked_hint(c: &Connection) -> zbus::Result<bool> {
    let props = zbus::fdo::PropertiesProxy::builder(c)
        .destination("org.freedesktop.login1")?
        .path("/org/freedesktop/login1/session/auto")?
        .build()
        .await?;
    let v = props.get(InterfaceName::from_static_str_unchecked("org.freedesktop.login1.Session"), "LockedHint").await?;
    Ok(bool::try_from(v).unwrap_or(false))
}

async fn screen_saver_active(c: &Connection, name: &'static str, path: &'static str) -> zbus::Result<bool> {
    let dbus = zbus::fdo::DBusProxy::new(c).await?;
    if !dbus.name_has_owner(name.try_into()?).await? {
        return Ok(false);
    }
    let reply = c.call_method(Some(name), path, Some(name), "GetActive", &()).await?;
    reply.body().deserialize::<bool>()
}

/// True when the computer has a battery of its own and no charger is plugged in. Batteries of wireless mice and
/// keyboards (`scope` = Device) do not count, so a desktop PC is never "on battery".
pub fn on_battery() -> bool {
    on_battery_in(std::path::Path::new("/sys/class/power_supply"))
}

fn on_battery_in(dir: &std::path::Path) -> bool {
    let Ok(entries) = std::fs::read_dir(dir) else { return false };
    let (mut battery, mut charger) = (false, false);
    for e in entries.flatten() {
        let read =
            |f: &str| std::fs::read_to_string(e.path().join(f)).map(|s| s.trim().to_string()).unwrap_or_default();
        match read("type").as_str() {
            "Battery" if read("scope") != "Device" => battery = true,
            "Mains" | "USB" if read("online") == "1" => charger = true,
            _ => {}
        }
    }
    battery && !charger
}

#[cfg(test)]
mod tests {
    use super::*;

    fn supply(dir: &std::path::Path, name: &str, files: &[(&str, &str)]) {
        let d = dir.join(name);
        std::fs::create_dir_all(&d).unwrap();
        for (f, v) in files {
            std::fs::write(d.join(f), format!("{v}\n")).unwrap();
        }
    }

    #[test]
    fn battery_detection() {
        let base = std::env::temp_dir().join(format!("julehygge-power-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);

        // desktop PC with two wireless mice: never on battery
        let pc = base.join("pc");
        supply(&pc, "hidpp_battery_0", &[("type", "Battery"), ("scope", "Device")]);
        supply(&pc, "hidpp_battery_1", &[("type", "Battery"), ("scope", "Device")]);
        assert!(!on_battery_in(&pc));

        // laptop: on battery when the charger is unplugged
        let laptop = base.join("laptop");
        supply(&laptop, "BAT0", &[("type", "Battery"), ("status", "Discharging")]);
        supply(&laptop, "AC", &[("type", "Mains"), ("online", "0")]);
        assert!(on_battery_in(&laptop));
        supply(&laptop, "AC", &[("type", "Mains"), ("online", "1")]);
        assert!(!on_battery_in(&laptop));

        assert!(!on_battery_in(&base.join("missing")));
        let _ = std::fs::remove_dir_all(&base);
    }
}
