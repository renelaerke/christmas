# JuleHygge for Linux

A native Rust version of JuleHygge for **Ubuntu 22.04+** and **Linux Mint 21+**. The plan, the design choices and
the phases are in [docs/linux-plan.md](../docs/linux-plan.md).

> **Status: all six phases built; tested on Linux Mint 22.3 (Cinnamon, X11).** Snowflake icon in the panel with
> the full menu (same items as on Windows), one transparent click-through overlay per monitor, falling snow (wind,
> changing weather), a snow pile on top of the bottom panel with storm drifts, and snow on the top edges of other
> windows. Christmas lights, elves, the snowman, the snow plow and Santa across neighbouring screens. The advent
> calendar with its 24 doors and their effects, daily notices, and synthesized sound (off by default). A
> fullscreen app pauses its screen and mutes the sound; a lock, the screen saver or a switched-off display stops
> everything; power-save follows the battery. A restart supervisor, self-update from the project's GitHub
> releases, and a per-user installer. Ubuntu on Wayland (through XWayland) has not been tested yet.

## Install (from a release)

Download `JuleHygge-linux-x86_64.tar.gz` from the release, unpack it and run the installer (no root needed):

```bash
tar -xzf JuleHygge-linux-x86_64.tar.gz && ./install.sh            # installs and starts it
./install.sh --autostart                                           # ... and start it at login
./install.sh --uninstall                                           # remove it again (settings are kept)
```

It goes to `~/.local/share/JuleHygge/` (a folder you can write to, so it can update itself), with *JuleHygge* in
the app menu and a `julehygge` command in `~/.local/bin`. It does not start at login unless you ask for it
(`--autostart`, or *Start ved login* in its menu).

A release build checks `rkl1976/christmas` for a newer release 1 minute after start and every 6 hours (menu:
*Opdatér automatisk*, *Søg efter opdatering nu*), downloads the Linux tarball, checks it (GitHub's SHA-256 digest,
and that the binary's version is the release's), puts it in place and restarts. Local builds are 0.0.0 and never
update themselves.

## Build

```bash
sudo apt install build-essential pkg-config libcairo2-dev libpango1.0-dev libasound2-dev
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh     # Rust, if not installed (stable >= 1.89)
./build.sh                                                          # -> build/JuleHygge and the release tarball
VERSION=1.6.0 ./build.sh                                            # stamped with a version (the release workflow does this)
```

## Run

```bash
build/JuleHygge                 # snow on every screen, snowflake in the panel; quit from its menu
pkill -x JuleHygge              # stop it from a terminal (e.g. when there is no tray icon)
```

- **Mint (Cinnamon, X11):** works directly. Needs the compositor, which Cinnamon always runs.
- **Ubuntu (GNOME, Wayland):** the app speaks X11 and runs through XWayland, which Ubuntu starts by itself.
  Whether the overlay stays on top of native Wayland windows is still to be tested.
- **No compositor** (e.g. some Xfce/MATE setups): a see-through window is impossible, so the overlay stays off and
  the tray menu says *Kræver en compositor*. It turns on by itself when a compositor starts.

Only one JuleHygge runs per session (lock file `$XDG_RUNTIME_DIR/julehygge.lock`). A normal start runs under a
restart supervisor (a second `JuleHygge` process) that restarts the app 5 s after a crash and gives up after 3
quick crashes; `pkill -x JuleHygge` stops both. Test flags and `JULE_NO_SUPERVISOR=1` run without it.

## Test aids

| Flag / environment variable | Effect |
|---|---|
| `--snapshot=DIR[,SEC]` | after SEC seconds (default 5) writes each screen's overlay over a dark background as `DIR/screenN.png`; also works without a compositor (e.g. Xvfb) |
| `--version` | prints the version |
| `--calendar` (`--kalender`) | opens the calendar at start |
| `--effect=N` (`--effekt=N`) | plays a calendar effect at start: 1 Santa, 2 snowstorm, 3 elf party, 4 star shower, 5 all |
| `--sound-test=DIR` (`--lyd-test=DIR`) | writes the synthesized sounds as WAV files and `summary.txt` (same names as on Windows) and exits; needs no display |
| `--update-test=github` | asks GitHub what an update would install now, downloads and checks it, but does not install; exits |
| `JULE_UPDATE_VERSION=x.y.z` | pretends to be that version when checking for updates |
| `JULE_UPDATE_TARBALL=file` + `JULE_UPDATE_TARBALL_VERSION=x.y.z` | a local tarball stands in for GitHub's latest release (try the whole update on a copy) |
| `JULE_UPDATE_DELAY=N` | the first update check after N seconds instead of 60 |
| `JULE_NO_SUPERVISOR=1` | runs without the restart supervisor |
| `--write-icon=FILE` | writes the app icon as a 256 px PNG (for `install.sh`) and exits |
| `--sprog-test` | prints the menu's languages (`assets/sprog`), the automatic choice and what each language lacks, and exits; `JULE_LOCALE=de_DE` pretends to be that locale (setting `Language`: empty = automatic, or a code) |
| `--folk-test` | prints whether this machine's language and region give nisser or elves (setting `Folk`: 0 automatic, 1 nisser, 2 alfer, 3 Wichtel, 4 kabouters, 5 päkapikud), and the rule for a list of locales, and exits; `JULE_LOCALE=en_US` pretends to be that locale |
| `--list-windows` | prints the windows as snow on windows sees them (frame, shown, maximized, which part of the top edge can carry snow) and exits; only reads from the X server |
| `--calendar-snapshot=FILE` | draws the calendar into a PNG (at `JULE_SCALE`, default 2) and exits, without opening a window |
| `--santa` (`--julemand`) | sends Santa right away |
| `--plow[=N]` (`--sneplov[=N]`) | sends the snow plow after N seconds (default 3) |
| `JULE_SETTINGS=path` | uses another settings file, so tests never change the real one |
| `JULE_DATE=yyyy-MM-dd` | pretends it is another date (weather, calendar doors, autumn's haystack, notices) |
| `JULE_SNOWMAN_SPEED=N` with `Theme=2` | builds the ofrenda of De dødes dag N times faster (3600: a step a second); `OfrendaSeconds=N` in the settings file starts it N seconds in (39600 is the finished altar) |
| `JULE_SNOWMAN_SPEED=N` | the children build the snowman N times faster (30 gives a whole snowman in 30 s and the plow a few seconds later) |
| `JULE_SNOWMAN_START=T[,X]` | the snowman starts T seconds into the build (0–899), X units from the primary screen's left edge, instead of somewhere at random |
| `JULE_WEATHER_TIME=HH:MM` | starts the day's weather at that time of day, to watch a change without waiting (the macOS name `JULE_VEJR_TID` works too) |
| `JULE_DEBUG=1` | debug lines in `$XDG_RUNTIME_DIR/julehygge-debug.log`, including fps, ms per frame and CPU % every 5 s |
| `JULE_FPS=N` | fixed frame rate (for measurements) |
| `JULE_SCALE=N` | overrides the desktop scale factor (otherwise `Xft.dpi / 96`) |
| `JULE_DEEPSNOW=1` | starts with a full snow pile (the plow comes by itself after 20 s) |
| `JULE_ELF_SECONDS=N` (`JULE_NISSE_SECONDS`) | an elf arrives or leaves every N seconds instead of every 1½–3 minutes |
| `JULE_NO_SHM=1` | sends pixels through the socket instead of MIT-SHM shared memory (to compare, or to rule it out) |

Settings: `~/.config/JuleHygge/settings.ini`, same keys as on Windows. Errors: `~/.local/state/JuleHygge/error.log`.

Unit tests (`cargo test`) cover the weather (against values computed with the Windows code), settings, the
snow layer and figures (no trails left behind), the snow plow and Santa runs, the calendar's door rules, the
sounds and the icon.

The sound noise uses .NET's `Random` with the Windows seeds, so `--sound-test` should give the same samples as
`--lyd-test` on Windows; compare the two `summary.txt` files (this has not been checked against a Windows run yet).

## Checklist for a new desktop (still to do on Ubuntu 24.04 or newer, Wayland)

1. `JULE_DEBUG=1 build/JuleHygge` and watch: snow falls on every monitor, and clicks, scrolling and hovering
   reach the windows below the snow.
2. The snow stays above normal windows, also after clicking around and opening new windows (Ubuntu: also above
   native Wayland apps such as Files, Settings and Firefox).
3. The snowflake shows in the panel, and *Afslut* quits.
4. CPU: `grep fps $XDG_RUNTIME_DIR/julehygge-debug.log` after a minute, at 20 fps (default) and with
   `JULE_FPS=30`. Note the screen sizes and scale.
5. Plug or unplug a monitor, or change the resolution: the overlays follow within a second or two.
6. Fractional scaling on Ubuntu (e.g. 125 %): is the snow sharp, and does it cover the whole screen?

## Code

| File | Contents | Windows counterpart |
|---|---|---|
| `src/main.rs` | arguments, single instance | `Program.cs` |
| `src/controller.rs` | main loop, frame timer, wind, weather, screens, test aids | `Controller.cs` |
| `src/layer.rs` | one screen's scene and pixel buffer: snow, snow pile, fullscreen pause, dirty rectangles | `Layer.cs` |
| `src/layer/*.rs` | the figures on a screen: lights, Santa and sparks, the haystack, snow plow, elves, snow on window edges; Cairo helpers | `Layer.cs` |
| `src/snowman_build.rs`, `src/layer/build.rs` | the snowman the children build: the story, and its drawing on the primary screen | `SnowmanBuild.cs`, `LayerSnowman.cs` |
| `src/window_snow.rs` | snow on windows: the piles on window edges, the window scan, clumps falling off | `WindowSnow.cs` |
| `src/figures.rs` | Santa, sparks and the plow run in global coordinates, across screens | `Controller.cs` |
| `src/x11.rs` | X11: monitors, overlay windows, click-through, MIT-SHM, panels, fullscreen window, DPMS | Win32 parts of `Layer.cs` |
| `src/session.rs` | lock and screen saver, notifications and clicks on them (D-Bus), battery | `SessionSwitch`, `PowerWatcher.cs`, balloon tips |
| `src/tray.rs`, `src/icon.rs` | panel icon and menu; the icon drawn with Cairo | `NotifyIcon`, `build.ps1` |
| `src/weather.rs` | changing weather (same random numbers as Windows and macOS) | `Weather.cs` |
| `src/settings.rs` | `settings.ini` | `Settings.cs` |
| `src/calendar.rs` | the advent calendar: doors, rules, window | `Calendar.cs` |
| `src/sound.rs` | synthesized sounds and playback (cpal) | `Sound.cs` |
| `src/updater.rs` | self-update from GitHub releases | `Updater.cs` |
| `src/supervisor.rs` | the restart supervisor | `Supervise` in `Program.cs` |
| `install.sh`, `build.sh` | per-user install; build and pack the release tarball | `build.ps1` |
| `src/autostart.rs` | "Start ved login" (`~/.config/autostart/julehygge.desktop`) | the `Run` registry value |
| `src/clock.rs`, `src/log.rs`, `src/rng.rs` | `JULE_DATE`, logs, random numbers | `JuleClock`, `ErrorLog` |
| `src/text.rs` | all user-facing text (Danish); code and comments are English | strings in the code |

Code, identifiers and comments are English. User-facing text is Danish and lives only in `src/text.rs`. Names
shared with the other versions keep their spelling: the `JULE_*` environment variables, the `settings.ini` keys
(`Nisser`, `NisseCount`) and the product name JuleHygge.
