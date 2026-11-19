# JuleHygge on Linux — analysis and plan

> **Status (2026-11-18):** All six phases are built in `linux/` and tested on Linux Mint 22.3 (Cinnamon, X11, two monitors at 2x). Ubuntu on Wayland (XWayland) is the next test round. Target: Ubuntu 22.04+ and Linux Mint 21+ (x86_64). The updater checks `rkl1976/christmas` (upstream). Differences from this plan found while building are in `AGENTS.md` (Linux section).

## Starting point
The Windows version (`src/`, C# 5, WinForms + GDI+) and the macOS version (`macos/`, Swift + AppKit) are both native, and the drawing code in `Overlay.swift` follows `src/Layer.cs` line by line. Linux gets a third native version in the same way, in `linux/`, written in **Rust**. Windows and macOS are not touched.

Nothing from `src/` can be recompiled for Linux: about 40 Win32 calls (`UpdateLayeredWindow`, DIB sections, `EnumWindows`, `waveOut`, power notifications) carry the app, and WinForms/`System.Drawing` are not usable on Linux. What ports directly is the logic: `CalendarContent` (texts), `JULE_DATE`, the snowman's 12 stages, the effect state machine, Santa's route across neighbouring screens, `Weather` (same random sequence), the settings format.

## Display servers — the main risk
| | Linux Mint (Cinnamon) | Ubuntu 24.04 | Ubuntu 25.10+ |
|---|---|---|---|
| Default session | X11 | Wayland ("Ubuntu on Xorg" still available) | Wayland only |
| Click-through overlay on top of everything | yes | via XWayland, **must be proven in phase 1** | via XWayland, **must be proven in phase 1** |
| Snow on windows, fullscreen pause | yes | only for X11 apps | only for X11 apps |
| Tray icon | yes (XApp/SNI) | yes (Ubuntu's AppIndicator extension) | yes |

Wayland deliberately lets no client put a global always-on-top overlay over everything, read other windows' positions, or know which app is fullscreen. GNOME (Mutter) does not implement `wlr-layer-shell`. The app therefore always talks **X11** — natively on Mint, through XWayland on Ubuntu. Full support on GNOME Wayland would need a GNOME Shell extension (JavaScript, one per GNOME version); that is out of scope for this plan.

## Options considered
1. **Rust, no GUI toolkit (chosen).** `x11rb` for windows, Cairo/Pango for drawing. Memory-safe, as fast as C, Cargo for dependencies and builds, small binary that only links system libraries every desktop already has.
2. **C + GTK 3 + Cairo.** Works, but more hand-written D-Bus/HTTPS/JSON code and no memory safety (macOS already had one dangling-reference crash on screen unplug).
3. **Rust + GTK.** The GTK 3 bindings (`gtk3-rs`) are archived; GTK 4 removed global window positioning and input shapes on X11, which the overlay needs.
4. **Python + GTK + Cairo.** Least code, but per-pixel snow at 4K/20 fps is too slow, and CPU/fan noise is already a stated concern.
5. **.NET 8 + Avalonia, Electron, Tauri.** Same problems as listed in `docs/macos-plan.md`: native interop is needed anyway, and they are heavy for an animation that runs all of December.

No toolkit is needed because the calendar is already custom-drawn on Windows (`Calendar.cs` has one `OnPaint` and one `OnMouseClick`, no controls), and every setting lives in the tray menu.

## Building blocks
| Job | Crate / system library | Windows counterpart |
|---|---|---|
| Windows, monitors, shapes, stacking | `x11rb` (pure Rust X11 protocol; features `randr`, `shape`, `xfixes`, `shm`, `dpms`) | `Form`, `Screen.AllScreens`, `SetWindowPos` |
| Drawing | `cairo-rs` + `pangocairo` (gtk-rs-core, maintained); system `libcairo2`, `libpango-1.0-0` | GDI+ |
| Presenting frames | Cairo `ImageSurface` (ARGB32, premultiplied) per screen; only dirty rectangles sent with MIT-SHM `PutImage` (plain `PutImage` as fallback) | DIB section + `UpdateLayeredWindowIndirect` with dirty rects |
| Tray icon + menu | `ksni` (StatusNotifierItem over D-Bus; icon as ARGB pixmap drawn in code) | `NotifyIcon` + `ContextMenuStrip` |
| Lock, suspend, screen saver, battery | `zbus` (logind, `org.gnome.ScreenSaver`, `org.cinnamon.ScreenSaver`, UPower) | `SystemEvents`, `RegisterPowerSettingNotification`, `SPI_GETSCREENSAVERRUNNING` |
| Notifications | `notify-rust` | balloon tip |
| Sound | `cpal` (ALSA; reaches PipeWire/PulseAudio through their ALSA plugins) | `waveOut` |
| Updater | `ureq` (rustls, no OpenSSL), `serde_json`, `sha2`, `flate2` + `tar` | `WebClient`, `JavaScriptSerializer`, SHA-256 |
| Settings | hand-written ini (same keys and defaults as `Settings.cs`) | `Settings.cs` |

Build dependencies on Ubuntu/Mint: `build-essential pkg-config libcairo2-dev libpango1.0-dev libasound2-dev`. Pin crate versions in a committed `Cargo.lock`.

## Structure
```
linux/
  Cargo.toml, Cargo.lock
  build.rs            // stamps JULE_VERSION (0.0.0 without VERSION=x.y.z)
  build.sh            // cargo build --release, packs JuleHygge-linux-x86_64.tar.gz
  install.sh          // per-user install, autostart, menu entry (no root)
  README.md           // build, run, test aids
  src/
    main.rs           // args, test aids, supervisor            ← Program.cs / main.swift
    clock.rs          // JULE_DATE
    controller.rs     // main loop, effects, Santa, daily notices ← Controller.cs
    x11.rs            // atoms, monitors, overlay windows, shapes, SHM present, struts, window list
    layer.rs          // one scene per screen: snow, ground, nisser, lights, snowman, plow ← Layer.cs / Overlay.swift
    window_snow.rs    // snow on other windows' top edges ← WindowSnow.cs
    weather.rs        // changing weather               ← Weather.cs (identical sequence)
    calendar.rs       // calendar window + CalendarContent ← Calendar.cs
    tray.rs           // ksni tray, menu, icon
    session.rs        // D-Bus: lock, sleep, screen saver, battery
    sound.rs          // synthesis + cpal playback thread ← Sound.cs
    settings.rs       // ~/.config/JuleHygge/settings.ini ← Settings.cs
    updater.rs        // GitHub releases                ← Updater.cs
    icon.rs           // snowflake icon drawn with Cairo (tray, window, .desktop)
    text.rs           // all user-facing text (Danish); code and comments are English
```

## Design per area

### Overlay windows
- One window per RandR monitor, sized to the monitor, re-created when monitors change (RandR `ScreenChangeNotify`).
- 32-bit ARGB visual. That needs a compositor: check the `_NET_WM_CM_S<n>` selection owner. Without one, show a notification ("Kræver en compositor") instead of drawing black rectangles.
- `override_redirect` window (no decoration, not in taskbar/alt-tab), raised periodically like `KeepOnTop()`. If the window manager stacks it wrongly, fall back to a managed window with `_NET_WM_WINDOW_TYPE_NOTIFICATION`, `_NET_WM_STATE_ABOVE`, `_SKIP_TASKBAR`, `_SKIP_PAGER`. Decided in phase 1, on both Mint and Ubuntu.
- Click-through: empty input region via XFixes `SetWindowShapeRegion(ShapeInput)`.
- HiDPI: X11 has no per-monitor scale. Use `Xft.dpi / 96` from the resource database as `dpiScale`, overridable with `JULE_SCALE`.

### Rendering (keep the Windows optimizations)
- Port `Layer.cs` / `Overlay.swift` function by function; origin top-left, same as both.
- Snowflakes are blended straight into the surface's pixel data (`BlendDot`); figures use Cairo paths.
- Everything drawn registers its bounds with `mark()`. Each frame only clears and presents last frame's plus this frame's rectangles (`ClearRects` / `PresentRegions`). Missing a `mark()` leaves trails, as on Windows.
- Christmas lights cached as a surface. Flake count scaled by logical screen size.
- Frame rate from settings (12/20/30/60, default 20); Santa and the plow boosted to 30 fps, as on Windows. Power-save caps at 12 fps.

### Ground (where the snow settles)
- Per monitor: the top of any dock/panel at the bottom of that monitor, from `_NET_WM_STRUT_PARTIAL` of windows with `_NET_WM_WINDOW_TYPE_DOCK` (`_NET_WORKAREA` is one rectangle for all monitors, so it is not enough).
- No bottom panel (Ubuntu's dock is on the left; GNOME's shell panels are invisible to XWayland): the screen bottom, as decided for macOS.
- While a fullscreen app is active: the screen bottom, as on Windows.

### Fullscreen pause and snow on windows
- Fullscreen: `_NET_ACTIVE_WINDOW` → `_NET_WM_STATE_FULLSCREEN`, or its geometry covers the monitor.
- Window list: `_NET_CLIENT_LIST_STACKING` (gives occlusion order). Subtract `_GTK_FRAME_EXTENTS` (invisible CSD shadows) and add `_NET_FRAME_EXTENTS` (WM decorations) to find the visible top edge. Minimized = `_NET_WM_STATE_HIDDEN`; maximized = `_MAXIMIZED_VERT` + `_HORZ` (no snow, as on Windows).
- Port the rest of `WindowSnow.cs` unchanged: piles in global coordinates, `settled` position, clumps falling on minimize/close.
- On XWayland, native Wayland windows are invisible; the feature then simply finds fewer windows.

### Stopping completely (`FinishRuns()`)
Stop drawing and end Santa, the plow and their sound at once on: logind `Lock` or `LockedHint`, `PrepareForSleep(true)`, screen saver `ActiveChanged(true)` (GNOME and Cinnamon), DPMS not `On` (polled every 2 s), or a frame stall over 2 s. Resume on the opposite signals.

### Tray menu
Same items and Danish texts as the Windows menu, using `ksni` checkmark, radio and submenu items. AppIndicator hosts do not deliver double-clicks, so "Kald julemanden" is a menu item. Left click (`activate`) opens the menu or, where the host supports it, the calendar.

### Calendar window
A normal managed X11 window (title "Julekalender", `WM_CLASS` `julehygge`, `_NET_WM_ICON` drawn in code), drawn with Cairo + Pango, handling `Expose`, `ButtonPress`, `ConfigureNotify`, `WM_DELETE_WINDOW` and Escape. Port the layout and `CalendarContent` from `Calendar.cs`.

### Sound
Port the synthesis from `Sound.cs` unchanged; play on its own thread through `cpal`, panned with the figure across screens. Always off by default. `--lyd-test=DIR` writes the same WAV files and `summary.txt` as on Windows, so both versions can be compared.

### Settings
`$XDG_CONFIG_HOME/JuleHygge/settings.ini` (default `~/.config/JuleHygge/settings.ini`), same keys, defaults and clamping as `Settings.cs`; atomic save via `.tmp` + rename. `JULE_SETTINGS=path` overrides.

### Supervisor
Same scheme as Windows and macOS: the first process runs the app as a child and restarts it 5 s after a crash, giving up after 3 quick crashes. Exit code 3 means "restart into the updated binary". Quitting from the menu ends both. Test flags and `JULE_NO_SUPERVISOR=1` skip it.

### Updater
As `Updater.cs`: check 1 minute after start and every 6 hours, download `JuleHygge-linux-x86_64.tar.gz`, verify GitHub's SHA-256 digest and that the binary's version equals the release tag, swap the binary next to the running one, exit with code 3. Local builds are 0.0.0 and never update. Menu: *Opdatér automatisk*, *Søg efter opdatering nu*. The repository it checks is one constant (see open questions).

### Install and packaging
- Release asset: `JuleHygge-linux-x86_64.tar.gz` containing `JuleHygge`, `install.sh`, `README.md`.
- `install.sh` (no root): copies to `~/.local/share/JuleHygge/` (user-writable, so self-update works; a `.deb` in `/usr` could not update itself), links `~/.local/bin/julehygge`, writes `~/.local/share/applications/julehygge.desktop` and `~/.config/autostart/julehygge.desktop`, and has the app write its icon (`--write-icon=PATH`), so the repo still has no image files. No `GDK_BACKEND=x11` is needed on Ubuntu Wayland: `x11rb` only speaks X11 and uses the `DISPLAY` that XWayland provides.
- Built on `ubuntu-22.04` so the binary runs on Ubuntu 22.04+ and Mint 21+ (glibc).

### CI
`.github/workflows/linux-build.yml`: on push and pull request run `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test`, `build.sh`, keep the tarball as an artifact; on a published release build with `VERSION=<tag>` and attach the tarball, like the Windows and macOS workflows.

## Test aids
The Linux code is English throughout, so the test aids get English names; the Danish names used on Windows and macOS are accepted as aliases, so the same test scripts work everywhere:
`--calendar` (`--kalender`), `--santa` (`--julemand`), `--plow[=N]` (`--sneplov[=N]`), `--effect=N` (`--effekt=N`), `--sound-test=DIR` (`--lyd-test=DIR`), `--snapshot=DIR[,SEC]` (saves each overlay surface and the calendar as PNG; no screen capture needed), `JULE_SETTINGS`, `JULE_DATE`, `JULE_DEBUG=1` (log in `$XDG_RUNTIME_DIR/julehygge-debug.log`), `JULE_FPS`, `JULE_DEEPSNOW=1`, `JULE_ELF_SECONDS` (`JULE_NISSE_SECONDS`), `JULE_NO_SUPERVISOR=1`, `JULE_UPDATE_VERSION`, `JULE_WEATHER_TIME=HH:MM` (`JULE_VEJR_TID`), plus `JULE_SCALE`. The `JULE_` prefix is part of the product name and stays. User-facing text stays Danish and lives in `linux/src/text.rs`.

Unlike the other versions, the pure logic gets `cargo test` unit tests: settings round-trip with old files, calendar door rules per date, snowman stage per day, and `Weather` against a fixture of day schedules produced by the Windows or macOS build (the sequence must be identical on all three).

## Phases (each ends with a CPU measurement on a real desktop)
1. **Skeleton and proof.** Cargo project, supervisor off, tray icon with *Afslut*, one overlay per monitor with falling snow, dirty-rect presenting, `--snapshot`. **Done when:** click-through and on-top work on Mint (X11) and on Ubuntu 24.04/26.04 Wayland via XWayland, and CPU at 20 fps is measured. Stacking strategy decided here.
2. **Ground and stopping.** Snow piles at the panel/screen bottom, storm drifts, fullscreen pause, lock/sleep/screen saver/DPMS stop, power-save on battery, settings file.
3. **Figures.** Christmas lights, nisser (walking across screens, gift exchange), snowman (12 stages), snow plow, Santa with reindeer across neighbouring screens.
4. **Calendar, effects, weather, sound.** Calendar window, door rules, notifications, the four effects, changing weather, synthesized sound.
5. **Snow on windows** (X11 windows only).
6. **Distribution.** Updater, supervisor, `install.sh`, autostart, CI workflow; update `README.md` and add a Linux section to `AGENTS.md` (feature parity now covers three versions).

## Testing environment
The development machine is Windows. WSL can build and run the unit tests but is not a real desktop (no panel, tray host or proper compositor). Visual checks need a Linux Mint VM (X11) and an Ubuntu VM (Wayland), or real hardware; CPU numbers should come from real hardware.

## Risks
- **XWayland on GNOME:** an X11 overlay may not stay above native Wayland windows, and fullscreen Wayland apps (Firefox, video players) cannot be detected, so snow may fall over fullscreen video. Mitigation: prove in phase 1; offer *Pause* in the menu; consider a GNOME Shell extension later.
- **No compositor** (some MATE/Xfce setups): transparency impossible; detect and tell the user.
- **Fractional scaling on XWayland:** X11 clients may be scaled and blurred. Measure in phase 1.
- **Multi-monitor 4K cost:** same as Windows; keep dirty rects and the flake budget, and measure.

## Open questions
- How important is Ubuntu on Wayland compared with Mint? Decides whether a GNOME Shell extension is ever worth it.
- Stay a fork, or send the Linux version upstream to `rkl1976/christmas`? Decides which repository the updater checks and where releases are made.
- x86_64 only, or also aarch64 (e.g. Raspberry Pi, ARM laptops)?
