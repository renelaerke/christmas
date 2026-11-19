//! The restart supervisor, as `Supervise` in `src/Program.cs` and macOS `main.swift`.
//!
//! A normal start first runs as a small watchdog that starts the real app as a child process and restarts it if it
//! crashes (after 5 s; it gives up after 3 crashes within a minute of each start). A normal quit ("Afslut") exits
//! with code 0, and then the watchdog quits too. Exit code `updater::RESTART_EXIT_CODE` means the child installed
//! a new binary: the watchdog then becomes the new binary (`exec`), so both processes run the new version.
//!
//! Test flags and `JULE_NO_SUPERVISOR=1` run the app directly, without a watchdog.

use std::os::unix::process::CommandExt;
use std::process::Command;
use std::time::{Duration, Instant};

/// Set in the child's environment (to the watchdog's pid), so the child knows it is supervised.
pub const ENV: &str = "JULE_SUPERVISOR";

/// True in the app process started by a watchdog.
pub fn is_child() -> bool {
    std::env::var_os(ENV).is_some()
}

/// Runs the watchdog until the app quits; never returns.
pub fn supervise(args: &[String]) -> ! {
    // one watchdog per session (the app has its own lock as well)
    let lock_path = crate::log::runtime_dir().join("julehygge-supervisor.lock");
    let lock = std::fs::OpenOptions::new().create(true).truncate(false).write(true).open(&lock_path);
    let _lock = match lock {
        Ok(f) if f.try_lock().is_ok() => f,
        Ok(_) => {
            eprintln!("{}", crate::text::ALREADY_RUNNING);
            std::process::exit(0);
        }
        Err(e) => {
            crate::log::error(&format!("supervisor lock {}: {e}", lock_path.display()));
            run_once(args)
        }
    };
    let exe = crate::updater::exe_path();
    let mut quick_crashes = 0;
    loop {
        let started = Instant::now();
        let status = Command::new(&exe).args(args).env(ENV, std::process::id().to_string()).status();
        let code = match status {
            Ok(s) => s.code(),
            Err(e) => {
                crate::log::error(&format!("supervisor: cannot start {}: {e}", exe.display()));
                std::process::exit(1);
            }
        };
        match code {
            Some(0) => std::process::exit(0),
            Some(c) if c == crate::updater::RESTART_EXIT_CODE => {
                // the new binary is in place: become it (it starts a new watchdog and child)
                drop(_lock);
                crate::log::debug("supervisor: restarting into the updated binary");
                let err = Command::new(&exe).args(args).env_remove(ENV).exec();
                crate::log::error(&format!("supervisor: cannot start the updated binary: {err}"));
                std::process::exit(1);
            }
            other => {
                let what = other.map_or("et signal".to_string(), |c| format!("kode {c}"));
                crate::log::error(&format!("JuleHygge stoppede uventet ({what}); genstarter"));
            }
        }
        quick_crashes = if started.elapsed() < Duration::from_secs(60) { quick_crashes + 1 } else { 0 };
        if quick_crashes >= 3 {
            crate::log::error("supervisor: crasher igen og igen, giver op");
            std::process::exit(1);
        }
        std::thread::sleep(Duration::from_secs(5));
    }
}

/// Without a lock to guard the watchdog, run the app once in this process's place.
fn run_once(args: &[String]) -> ! {
    let err = Command::new(crate::updater::exe_path()).args(args).env("JULE_NO_SUPERVISOR", "1").exec();
    crate::log::error(&format!("cannot start the app: {err}"));
    std::process::exit(1);
}
