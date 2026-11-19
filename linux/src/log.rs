//! Debug and error logs, like `ErrorLog` in `src/Program.cs`.
//!
//! - `JULE_DEBUG=1`: debug lines go to `$XDG_RUNTIME_DIR/julehygge-debug.log` (for measurements and tests).
//! - Errors always go to `~/.local/state/JuleHygge/error.log` (capped, so a repeating error cannot grow it forever)
//!   and to stderr.

use std::io::Write;
use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::OnceLock;

/// `$XDG_RUNTIME_DIR`, or the temp directory when it is not set.
pub fn runtime_dir() -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).filter(|p| p.is_dir()).unwrap_or_else(std::env::temp_dir)
}

/// `$XDG_STATE_HOME/JuleHygge` (default `~/.local/state/JuleHygge`).
fn state_dir() -> PathBuf {
    let base = std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/state")))
        .unwrap_or_else(std::env::temp_dir);
    base.join("JuleHygge")
}

pub fn debug_enabled() -> bool {
    static ON: OnceLock<bool> = OnceLock::new();
    *ON.get_or_init(|| std::env::var("JULE_DEBUG").as_deref() == Ok("1"))
}

fn append(path: PathBuf, line: &str) {
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(f, "{line}");
    }
}

/// A debug line (only with `JULE_DEBUG=1`).
pub fn debug(msg: &str) {
    if !debug_enabled() {
        return;
    }
    let t = chrono::Local::now().format("%H:%M:%S%.3f");
    append(runtime_dir().join("julehygge-debug.log"), &format!("{t} {msg}"));
}

/// An error line. At most 200 per run.
pub fn error(msg: &str) {
    static WRITTEN: AtomicUsize = AtomicUsize::new(0);
    eprintln!("JuleHygge: {msg}");
    if WRITTEN.fetch_add(1, Ordering::Relaxed) >= 200 {
        return;
    }
    let t = chrono::Local::now().format("%Y-%m-%d %H:%M:%S");
    append(state_dir().join("error.log"), &format!("{t} {msg}"));
    debug(&format!("error: {msg}"));
}
