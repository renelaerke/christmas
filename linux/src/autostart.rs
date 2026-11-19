//! "Start ved login": an XDG autostart entry, `~/.config/autostart/julehygge.desktop`, that starts this binary
//! when the user logs in (the "Start med Windows" registry value on Windows). `install.sh` (phase 6) writes the same
//! file.

use std::path::{Path, PathBuf};

/// `$XDG_CONFIG_HOME`, default `~/.config`.
fn config_dir() -> Option<PathBuf> {
    std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
}

fn entry_path(config: &Path) -> PathBuf {
    config.join("autostart").join("julehygge.desktop")
}

/// True when the entry exists and is not disabled (`Hidden=true` is how desktops switch an entry off).
pub fn enabled() -> bool {
    config_dir().is_some_and(|c| enabled_in(&c))
}

fn enabled_in(config: &Path) -> bool {
    std::fs::read_to_string(entry_path(config))
        .is_ok_and(|s| !s.lines().any(|l| l.trim().eq_ignore_ascii_case("hidden=true")))
}

/// Writes or removes the entry. A failure is logged; the menu then shows the real state again.
pub fn set(on: bool) {
    if let Some(c) = config_dir() {
        set_in(&c, on);
    }
}

fn set_in(config: &Path, on: bool) {
    let path = entry_path(config);
    let result = if on {
        std::env::current_exe().and_then(|exe| {
            if let Some(dir) = path.parent() {
                std::fs::create_dir_all(dir)?;
            }
            let entry = format!(
                "[Desktop Entry]\nType=Application\nName=JuleHygge\nComment=Sne, nisser og julekalender på skrivebordet\nExec=\"{}\"\nIcon=julehygge\nX-GNOME-Autostart-enabled=true\nTerminal=false\n",
                exe.display()
            );
            std::fs::write(&path, entry)
        })
    } else {
        match std::fs::remove_file(&path) {
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            r => r,
        }
    };
    if let Err(e) = result {
        crate::log::error(&format!("autostart {}: {e}", path.display()));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn switch_on_and_off() {
        let dir = std::env::temp_dir().join(format!("julehygge-autostart-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        assert!(!enabled_in(&dir));
        set_in(&dir, true);
        assert!(enabled_in(&dir));
        let entry = std::fs::read_to_string(entry_path(&dir)).unwrap();
        assert!(entry.starts_with("[Desktop Entry]") && entry.contains("Exec=\""));
        set_in(&dir, false);
        assert!(!enabled_in(&dir));
        // switching off twice is fine, and a desktop that hid the entry counts as off
        set_in(&dir, false);
        std::fs::create_dir_all(dir.join("autostart")).unwrap();
        std::fs::write(entry_path(&dir), "[Desktop Entry]\nHidden=true\n").unwrap();
        assert!(!enabled_in(&dir));
        let _ = std::fs::remove_dir_all(&dir);
    }
}
