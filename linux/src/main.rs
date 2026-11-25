//! JuleHygge for Linux (Ubuntu and Linux Mint): snow over the desktop, with a snowflake in the panel.
//! See linux/README.md and docs/linux-plan.md. All user-facing text is Danish.

mod autostart;
mod calendar;
mod clock;
mod controller;
mod figures;
mod folk;
mod icon;
mod lang;
mod layer;
mod new_year;
mod log;
mod rng;
mod session;
mod settings;
mod snowman_build;
mod sound;
mod supervisor;
mod text;
mod tray;
mod updater;
mod weather;
mod window_snow;
mod x11;

use std::path::PathBuf;

pub const VERSION: &str = env!("APP_VERSION");

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    updater::exe_path(); // captured now: an update renames another file over it later
    let mut opts = controller::Options::default();
    // Test flags run the app directly, without the restart supervisor (as on Windows).
    let mut test_run = false;
    for a in &args {
        if a == "--version" {
            println!("JuleHygge {VERSION}");
            return;
        } else if let Some(file) = a.strip_prefix("--write-icon=") {
            // the app icon as a 256 px PNG, for install.sh (the repo has no image files)
            if let Err(e) = icon::write_png(256, std::path::Path::new(file)) {
                eprintln!("JuleHygge: {file}: {e}");
                std::process::exit(1);
            }
            return;
        } else if a == "--update-test=github" {
            // asks GitHub what an update would install now, and checks it, without installing
            let current = updater::display(updater::current());
            match updater::test_against_github() {
                updater::Outcome::UpToDate => {
                    println!("{current}: up to date (or the release has no Linux tarball yet)")
                }
                updater::Outcome::Ready { version, .. } => {
                    println!("{current}: would update to {} (downloaded and checked)", updater::display(version))
                }
                updater::Outcome::Failed(e) => {
                    println!("{current}: update check failed: {e}");
                    std::process::exit(1);
                }
            }
            return;
        } else if a == "--sprog-test" {
            // prints the languages found for the menu, the automatic choice, and what each lacks
            // (JULE_LOCALE=de_DE pretends to be that locale)
            print!("{}", lang::test_report());
            return;
        } else if a == "--folk-test" {
            // prints whether this machine's language and region give nisser or elves, and the rule for other
            // locales (JULE_LOCALE=en_US pretends to be that locale)
            print!("{}", folk::test_report());
            return;
        } else if a == "--list-windows" {
            // prints the windows as the snow on windows sees them (only reads from the X server, shows nothing)
            match x11::Display::open() {
                Ok(d) => {
                    let screens: Vec<x11::Rect> = d.monitors().iter().map(|m| m.rect).collect();
                    let wins = d.client_windows();
                    let snowy = window_snow::scan(&wins, &screens, d.dpi_scale);
                    for w in &wins {
                        let edge = snowy.iter().find(|s| s.id == w.id);
                        let vis: Vec<String> = edge
                            .map_or(Vec::new(), |e| e.visible.iter().map(|(a, b)| format!("{a:.0}-{b:.0}")).collect());
                        println!(
                            "{:#010x} {:>5},{:<5} {:>5}x{:<5} shown {:5} maximized {:5} snow {:5} {}",
                            w.id,
                            w.rect.x,
                            w.rect.y,
                            w.rect.w,
                            w.rect.h,
                            w.shown,
                            w.maximized,
                            edge.is_some(),
                            vis.join(" ")
                        );
                    }
                }
                Err(e) => eprintln!("JuleHygge: {e}"),
            }
            return;
        } else if let Some(file) = a.strip_prefix("--calendar-snapshot=") {
            // draws the calendar into a PNG file without opening a window (at JULE_SCALE, default 2)
            let k = std::env::var("JULE_SCALE").ok().and_then(|v| v.parse::<f64>().ok()).unwrap_or(2.0);
            if let Err(e) = calendar::render_to_png(&settings::Settings::load(), k, std::path::Path::new(file)) {
                eprintln!("JuleHygge: {file}: {e}");
                std::process::exit(1);
            }
            return;
        } else if let Some(dir) = a.strip_prefix("--sound-test=").or_else(|| a.strip_prefix("--lyd-test=")) {
            // writes the synthesized sounds as WAV files and a summary, without starting the app
            match sound::write_test_files(std::path::Path::new(dir)) {
                Ok(()) => println!("sounds written to {dir}"),
                Err(e) => {
                    eprintln!("JuleHygge: {dir}: {e}");
                    std::process::exit(1);
                }
            }
            return;
        } else if let Some(v) = a.strip_prefix("--snapshot=") {
            // --snapshot=DIR[,SECONDS]: writes each screen's overlay as screenN.png after SECONDS (default 5)
            let (dir, secs) = match v.rsplit_once(',') {
                Some((d, s)) if s.parse::<f32>().is_ok() => (d, s.parse::<f32>().unwrap_or(5.0)),
                _ => (v, 5.0),
            };
            opts.snapshot = Some((PathBuf::from(dir), secs));
            test_run = true;
        } else if a == "--calendar" || a == "--kalender" {
            opts.calendar = true;
            test_run = true;
        } else if let Some(v) = a.strip_prefix("--effect=").or_else(|| a.strip_prefix("--effekt=")) {
            test_run = true;
            match v.parse::<i32>() {
                Ok(n) => opts.effect = Some(n),
                Err(_) => eprintln!("JuleHygge: {a}: not an effect number (1-5)"),
            }
        } else if a == "--santa" || a == "--julemand" {
            opts.santa = true;
            test_run = true;
        } else if a == "--plow" || a == "--sneplov" {
            // --plow sends the snow plow after 3 s, --plow=N after N seconds (the Danish names work too)
            opts.plow_after = Some(3.0);
            test_run = true;
        } else if let Some(v) = a.strip_prefix("--plow=").or_else(|| a.strip_prefix("--sneplov=")) {
            test_run = true;
            match v.parse::<f32>() {
                Ok(secs) => opts.plow_after = Some(secs),
                Err(_) => eprintln!("JuleHygge: {a}: not a number of seconds"),
            }
        } else {
            eprintln!("JuleHygge: unknown argument {a}");
        }
    }

    if !supervisor::is_child() && !test_run && std::env::var_os("JULE_NO_SUPERVISOR").is_none() {
        supervisor::supervise(&args);
    }

    // Only one JuleHygge per user session. The lock is released when the process ends, also after a crash.
    // Right after an update without a supervisor, the old process may still be shutting down: wait for it.
    let lock_path = log::runtime_dir().join("julehygge.lock");
    let wait = if std::env::var_os("JULE_AFTER_UPDATE").is_some() { 15 } else { 0 };
    let _lock = match std::fs::OpenOptions::new().create(true).truncate(false).write(true).open(&lock_path) {
        Ok(f) => {
            let mut tries = 0;
            loop {
                match f.try_lock() {
                    Ok(()) => break Some(f),
                    Err(std::fs::TryLockError::WouldBlock) if tries < wait * 4 => {
                        tries += 1;
                        std::thread::sleep(std::time::Duration::from_millis(250));
                    }
                    Err(std::fs::TryLockError::WouldBlock) => {
                        eprintln!("{}", text::ALREADY_RUNNING);
                        return;
                    }
                    Err(std::fs::TryLockError::Error(e)) => {
                        log::error(&format!("lock {}: {e}", lock_path.display()));
                        break None;
                    }
                }
            }
        }
        Err(e) => {
            log::error(&format!("lock {}: {e}", lock_path.display()));
            None
        }
    };

    log::debug(&format!("JuleHygge {VERSION} starting, args {args:?}"));
    match controller::Controller::new(opts).and_then(|mut c| c.run()) {
        Ok(code) if code == updater::RESTART_EXIT_CODE && !supervisor::is_child() => {
            // updated without a supervisor: start the new binary, which waits for this process's lock
            drop(_lock);
            let started =
                std::process::Command::new(updater::exe_path()).args(&args).env("JULE_AFTER_UPDATE", "1").spawn();
            if let Err(e) = started {
                log::error(&format!("cannot start the updated binary: {e}"));
            }
        }
        Ok(code) => std::process::exit(code),
        Err(e) => {
            log::error(&format!("{e}"));
            std::process::exit(1);
        }
    }
}
