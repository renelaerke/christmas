# AGENTS.md

JuleHygge er et juleoverlay til Windows (WinForms, .NET Framework 4.x) i `src/`, en native macOS-udgave (Swift/AppKit) i `macos/` og en native Linux-udgave (Rust, X11) i `linux/`. Al brugervendt tekst er på **dansk**.

## Byg
- Byg med `powershell -ExecutionPolicy Bypass -File .\build.ps1`. Den bruger den `csc.exe`, der følger med Windows. Der er **intet .NET SDK** på maskinen, og der må ikke bruges NuGet-pakker.
- Compileren forstår kun **C# 5**: ingen `$"..."`, `?.`, `nameof`, `out var`, expression-bodied members eller initializers på auto-properties.
- **Luk programmet før du bygger** (`Stop-Process -Name JuleHygge`). Ellers er `JuleHygge.exe` låst, og bygget fejler.
- `build.ps1` bruger `/codepage:65001`, så kildefiler skal være UTF-8 (æøå i strenge).

## Test
- `--kalender` åbner julekalenderen ved opstart.
- Miljøvariablen `JULE_DATE=yyyy-MM-dd` får programmet til at tro, at det er en anden dato.
- **Pas på:** En test med en falsk dato skriver åbnede låger og snemandens trin til den rigtige `%APPDATA%\JuleHygge\settings.ini`. Tag en backup af filen før testen, og sæt den tilbage bagefter.
- Prefer `JULE_SETTINGS=<path>` for tests: it points the app at another settings file, so the real one is never touched.
- Other Windows test aids (same as macOS): `--julemand`, `--effekt=N`, `--sneplov[=N]`, `--lyd-test=DIR` (writes the synthesized sounds as WAV + `summary.txt`), `JULE_DEBUG=1` (`%TEMP%\julehygge-debug.log`), `JULE_FPS=N`, `JULE_DEEPSNOW=1`, `JULE_NISSE_SECONDS=N`, `JULE_NO_SUPERVISOR=1`, `JULE_UPDATE_VERSION=x.y.z` (pretend to be that version when checking for updates).
- Normal starts run under a restart supervisor (a second `JuleHygge.exe` process). Test flags skip it. `Stop-Process -Name JuleHygge` stops both.
- Der er ingen automatiske tests. Kontrollér visuelt med skærmbilleder. `CopyFromScreen` fanger overlay-vinduerne, og processen skal være DPI-aware, ellers bliver koordinaterne forkerte.

## Ydelse
- Brugeren har **tre skærme**: 3456×2160 og 2× 4480×2520 (175 % skalering). Hver frame bliver lagt oven på skærmen med `UpdateLayeredWindow` i fuld skærmstørrelse, og det koster både CPU og GPU (dwm). Blæseren i den bærbare kan høres.
- Hold derfor fast i de optimeringer, der er lavet:
  - Kun de områder, der blev tegnet i forrige frame, ryddes (`Mark()` og `ClearRects`).
  - Snefnug tegnes direkte i pixelbufferen (`BlendDot`).
  - Julelysene caches som et billede.
  - Antallet af fnug skaleres efter den logiske skærmstørrelse.
- Alt nyt, der tegnes, **skal** registreres med `Mark()`. Ellers bliver det liggende på skærmen som spor.
- Mål CPU-forbruget før og efter ændringer i tegnekoden.

## Konventioner
- Ingen billed- eller lydfiler. Al grafik tegnes i koden med GDI+. (This is about the app. README screenshots and the GIF live in `docs/media/`; keep them small and free of private desktop content.)
- Figurerne skal være originale: dansk nisse med rød hue og gråt tøj, ingen kendte figurer.
- Indstillinger gemmes i `Settings`. Nye felter skal have en standardværdi, så gamle `settings.ini`-filer stadig virker.
- Fakta i `CalendarContent` er ikke kildetjekket. Tjek dem, før der tilføjes nye.

## Git
- Git og `gh` er installeret, men ligger måske ikke på PATH i ældre shells. Brug i så fald `C:\Program Files\Git\cmd\git.exe` og `C:\Program Files\GitHub CLI\gh.exe`.
- Remote: `rkl1976/christmas` on GitHub. Make releases with the **Make release** workflow (`.github/workflows/release.yml`; Actions tab, or `gh workflow run release.yml -f bump=patch`): it picks the next version, builds and attaches `JuleHygge.exe`, `JuleHygge-macOS.zip` and `JuleHygge-linux-x86_64.tar.gz`, and publishes only when all three are on the release. Merging a PR does not release anything. A hand-made `gh release create vX.Y.Z --notes-file ...` (with **no files**) also works: the build workflows attach their files on "release published". Never upload a local build: the app's self-update (`src/Updater.cs`) only installs an exe whose version matches the release tag, and local builds are 0.0.0.

## macOS (`macos/`)
- Byg med `macos/build.sh` (Swift Package + `.app`-bundle, ad-hoc-signeret). Luk appen først: `pkill -x JuleHygge`.
- Ændringer i figurer/logik bør laves i **begge** udgaver. Tegnekoden i `Overlay.swift` følger `src/Layer.cs` linje for linje (origo øverst til venstre).
- Skærmbilleder kræver skærmoptagelsestilladelse. Brug i stedet `--snapshot=MAPPE[,SEK]`, som gemmer overlayet som PNG.
- Brug `JULE_SETTINGS=<sti i projektet>` ved test med `JULE_DATE`, så de rigtige indstillinger ikke ændres.
- **Strøm:** Mål med `macos/measure.sh` før og efter ændringer i tegnekoden — både app og WindowServer. Brug ikke Core Animation-animationer (de kører med 120 Hz); alt drives af den fælles timer. Se afsnittet "Strømforbrug" i `macos/README.md`.
- Figurernes tegne-closures må aldrig holde overlayet som `unowned` (brug `[weak self]`): ved skærmskift kan AppKit bede et lag tegne, mens overlayet nedlægges. Det crashede appen, da en ekstern skærm blev taget ud (rettet 2026-11-16).
- Genstart efter crash klares af vagtprocessen i `main.swift`, ikke af en launch agent: `SMAppService.agent` er bundet til kodesignaturen og afvises efter hver ad-hoc-build. Når du tester med `build/`-kopien, så luk først den installerede app (`osascript -e 'tell application id "dk.julehygge.JuleHygge" to quit'`), ellers lukker testkopien sig selv (kun én ad gangen).
- **JuleHygge Kamera** (`macos/CameraExtension/`, `VirtualCamera.swift`): byg og installér med `macos/xcbuild.sh` (Xcode-projektet genereres af `tools/make-xcodeproj.py`). Erfaringer:
  - CoreMediaIO angiver strømmens retning set fra enheden: billedet apps læser er "input" (1), og udvidelsens sink er "output" (0). Det modsatte valg fylder sink-køen med udvidelsens egne billeder (rettet 2026-11-16).
  - Udvidelsens egne `Logger`-linjer kommer ikke frem i `log show`/`log stream` (den kører som systembruger). Fejlsøg fra appens side eller via en egen egenskab.
  - En ny version af udvidelsen (hæv `CFBundleVersion`) kræver typisk en genstart af Mac'en, før den nye kører. Ændringer kun i appen kræver ingen genstart.
  - Brug ikke `CALayer.render(in:)` til kamerabaggrunden. Den laver en offscreen-buffer for hvert lag med gennemsigtighed (~900 ms for ~260 snefnug). `ScreenOverlay.renderSceneImage()` tegner lagtræet selv (~10 ms). `CARenderer` gav kun magenta på macOS 27.
  - Vision-masken er 512×384 (4:3), mens kameraet er 1920×1080 (16:9). Stræk masken til kamerabilledet, og flyt begge med samme transformation. Beregn masken for hvert billede, ellers halter kanten.
  - Start aldrig den installerede app direkte fra en terminal (`/Applications/JuleHygge.app/Contents/MacOS/JuleHygge …`), mens kameraet skal virke: macOS regner så terminalen som ansvarlig og nægter kameraadgang (`camera access: false`), og preview dør. Brug `open -a /Applications/JuleHygge.app --args …`.
  - Kør hvert kamerabillede i `autoreleasepool` og tøm Core Images cache jævnligt (`ciContext.clearCaches()`). Uden det lækkede kameraet ét billede pr. frame (CG-bitmaps og IOSurfaces) og nåede 54 GB på en time (rettet 2026-11-17). Mål med `footprint -p <pid>`.
  - `timeout` findes ikke på macOS. Kør `log stream` i baggrunden og stop den med `kill`.
- Alt, der er "på vej" (julemanden, sneploven, deres lyd), skal afsluttes i `finishRuns()`, når overlayet stopper (pauseskærm, skærmsøvn, lås). Ellers hænger turen, når timeren står stille, og melodien looper (rettet 2026-11-16).
- Sne på vinduer (`WindowSnow.swift`): bunkerne ligger i globale koordinater i `Controller.ledges` og tegnes af hvert overlay, de krydser. Sneen hører til vinduets sidst stillestående placering (`settled`): under minimering krymper vinduet ind i Dock'en, og sneen skal falde fra det oprindelige sted. Tegn kun strækninger, hvor der faktisk ligger sne (ellers ses en tynd hvid streg på bare kanter).
- Nissehuen (`Hat.swift`) bygges på hovedets målte omrids (ny metode 2026-11-17, afprøvet live; se `docs/nissehue-overlevering.md`, afsnittet "Hue, 5" og frem):
  - **Plads og form fra udskæringsmasken i hvert billede:** omridset scannes langs hovedets egen akse fra under øjnene til issen. Pelskanten er lige så bred som omridset der, hvor den møder det, og stoffet er den mindste form uden talje om omridset over kanten og spidsen. Vinklerne former kun huen, så en vinkelfejl kan ikke flytte den væk fra hovedet.
  - **Vinkler fra Visions ansigtsramme (revision 3).** Yaw er pålidelig: den fulgte ansigtets forskydning i omridset fra 5° til 60° i en live-log. Den tidligere konklusion ("35° for et ansigt forfra") var forkert: brugeren sad drejet ca. 30° i forhold til kameraet. Tjek aldrig "forfra" mod, hvad personen kigger på; kun mod kameraet.
  - **Visions rækkefølge er R = Rz(roll)·Rx(pitch)·Ry(yaw):** roll er retningen af hovedets lodrette akse i billedet, ikke øjenlinjens hældning (øjenlinjen hælder atan(sin pitch · tan yaw) mere). Pitch er positiv, når man nikker ned. Kameraets højde (nedefra/oppefra) er bare en anden pitch.
  - **Målestok: hovedets største bredde** (med hår). Hovedets højde i billedet ændrer sig med nik og kameraets højde, bredden gør ikke. Dybde/bredde starter som et almindeligt hoved (1,25) og læres, når personen drejer.
  - Metoden skal virke for andre personer, hår, kameraer og siddestillinger: ingen konstant må være tilpasset én person. Huens egne proportioner står i enheder af hovedets bredde.
  - Test: `--nissehue-test=MAPPE` (`HatTest.swift`) simulerer syv hovedformer og fire kameraopstillinger med perspektiv, støj og fejlmålinger, og måler mod sandheden (dækning, øjne fri, størrelse, rysten). `HUE_CASE=N` kører én opstilling, `HUE_TRACE=1` viser forløbet. Simuleringen bruger samme vinkelrækkefølge som koden, så den kan ikke afsløre en forkert antagelse om Vision.
  - **Skæg og dragt (`Costume.swift`) bygger på samme målte hoved.** Skægget er et bånd på ansigtets flade fra øre til øre, drejet med hovedet; indersiden sidder på huden, og ydersiden står ud med skæggets tykkelse (højst ca. én tykkelse uden for ansigtet). Dragten finder tøjet ved at vokse op fra brystet og holder hovedets målte omrids fri.
  - **Se det, før det installeres:** `--kamera-debug=MAPPE` gemmer hvert 3. sekund det færdige billede, det rå kamerabillede og målingerne; `--kamera-replay=MAPPE` kører hue, skæg og dragt igen på de rå billeder (`ud-NNN.png`). Kig på nærbilleder i de stillinger, ændringen rører, før `xcbuild.sh`. Billederne viser personer: `build-test/` er uden for git.
  - `log show` gemmer ikke info-linjer længe, og i zsh er `log` en indbygget kommando: brug `/usr/bin/log show --info --last 1h --predicate 'subsystem == "dk.julehygge.JuleHygge" AND eventMessage CONTAINS "hue:"'` kort efter kørslen.
- `measure.sh` måler den nyeste JuleHygge-proces; den anden er vagtprocessen.
- Test-appen skal køre som `.app` (`build/JuleHygge.app`, ikke `.build/release/JuleHygge`), ellers crasher UserNotifications. Brug `JULE_LOG` og `JULE_SETTINGS` med stier i projektet.
- Sound is synthesized in code on both platforms (`macos/.../Sound.swift`, `src/Sound.cs`, played with `waveOut` on Windows) — still no sound files. Sound must always be off by default.
- Windows keeps feature parity with macOS: window snow (`src/WindowSnow.cs`, ported from `WindowSnow.swift`; macOS point sizes are scaled by the system DPI via `Ledge.U`), nisse gift meetings, storm drifts, three tunes with ±10% pace, and `FinishRuns()` when the overlay stops (lock, display off, suspend, screen saver polled via `SPI_GETSCREENSAVERRUNNING`, or a frame stall over 2 s). Windows deliberately differs on frame rate: Santa and the plow are boosted to 30 fps, not 60.
- **Automatisk opdatering (`Updater.swift`, som `src/Updater.cs`):** en udgivet app tjekker GitHub 1 minut efter start og hver 6. time, henter `JuleHygge-macOS.zip`, pakker den ud ved siden af sig selv, kontrollerer den (SHA-256, bundle-id, version lig udgivelsens tag, gyldig signatur) og bytter hele app-mappen ud. Vagtprocessen starter den nye app, når barnet slutter med kode 3.
  - Versionen stemples af `build.sh` med `VERSION=x.y.z` (workflowet giver udgivelsens tag). Uden den er appen 0.0.0 og opdaterer aldrig sig selv. Udgivelser til og med v1.4.0 er stemplet 1.0 og kan ikke opdatere sig selv.
  - En app med JuleHygge Kamera (`xcbuild.sh`) opdaterer aldrig sig selv: zip-filen er ad hoc-signeret og uden kameraudvidelsen.
  - Test på en kopi, aldrig den installerede: `--opdatering-test=ZIP,VERSION` installerer en lokal zip i stedet for den app, den køres fra; `--opdatering-test=github,-` spørger GitHub og henter og kontrollerer uden at installere. `JULE_UPDATE_VERSION=x.y.z` lader som om, appen har den version. Hele forløbet med genstart: start en kopi med `open -n KOPI.app --env JULE_UPDATE_ZIP=fil.zip --env JULE_UPDATE_ZIP_VERSION=x.y.z --env JULE_UPDATE_DELAY=4` (plus `JULE_SETTINGS` og `JULE_LOG` i projektet); zip-filen står da i stedet for GitHubs nyeste udgivelse, og `JULE_`-variablerne følger med over i den nye version. Luk den installerede app først.
- **Skiftende vejr** (`Weather.swift` og `src/Weather.cs`, ens linje for linje): snemængden "Skiftende vejr" (`SnowLevel=3`, standard i nye installationer) lader vejret skifte mellem let sne, normal og snestorm, i perioder af meget forskellig længde (let 8–90 min, normal 6–70, storm 4–25; korte perioder er de almindeligste). Dagens forløb regnes ud fra datoen alene med samme tilfældige tal i begge udgaver, så det er ens efter genstart, på alle skærme og på Windows og macOS. Det eneste sted, niveauet vælges, er `effectiveSnowLevel`/`EffectiveSnowLevel`. Overgangen glider: `snowAmount`/`SnowAmount` er et tal mellem niveauerne (en storm bygger op på 90 s og klinger af over 3 min; mellem let og normal tager det 4 min), og antallet af fnug følger det, mens vind, fart og driver følger niveauet. Test på macOS: `--vejr-test[=DAGE]` udskriver forløbet, fordelingen og en storms op- og nedtur; `JULE_VEJR_TID=TT:MM` starter dagens vejr på det klokkeslæt, så et skift kan ses uden at vente.
- Se `macos/README.md` for testparametre og `docs/macos-plan.md` for designvalg.

## Linux (`linux/`)
- Rust, no GUI toolkit: `x11rb` (X11), Cairo/Pango (drawing), `ksni` (tray), `zbus` (D-Bus), `cpal` (sound). Build with `linux/build.sh` (needs `build-essential pkg-config libcairo2-dev libpango1.0-dev libasound2-dev` and Rust). Code and comments are English; user-facing text is Danish and lives only in `linux/src/text.rs`. See `linux/README.md` for test aids and `docs/linux-plan.md` for the design.
- The drawing follows `src/Layer.cs` function by function (`linux/src/layer.rs` and `linux/src/layer/*.rs`, one file per figure). Changes to figures or logic should be made in all three versions.
- **Close the app before testing a new build:** `pkill -x JuleHygge` (it also stops the supervisor). Test with `JULE_SETTINGS=<file>` (and `JULE_DEBUG=1`, log in `$XDG_RUNTIME_DIR/julehygge-debug.log`), so the real settings and opened doors are not touched. `--snapshot=DIR`, `--calendar-snapshot=FILE`, `--sound-test=DIR` and `--list-windows` check drawing, sound and the window scan without showing anything on screen.
- X11 only: on Ubuntu's Wayland desktop it runs through XWayland and cannot see native Wayland windows (no snow on them, and their fullscreen state is unknown). Not tested on Wayland yet.
- Performance (two monitors, 11264x3456 at 2x scale; measure with `JULE_DEBUG=1` before and after drawing changes):
  - Pixels go to the X server through MIT-SHM (`JULE_NO_SHM=1` for the socket fallback), with each flake's old and new rectangle merged (`merge_rects`): a storm went from 48% CPU at 13 fps to about 30% at 20 fps.
  - The snow pile (with the snowman in it) and the light string are cached images that clearing restores, unlike Windows, which redraws them every frame. The pile is redrawn only when it changed by half a pixel, at most 4 times a second (every frame while the plow is on that screen); the lights redraw only their bulbs' boxes. The calm scene with everything on went from 37% to 27% CPU. Snow on windows is cached the same way per window (redrawn when it changed by half a pixel, at most 4 times a second, or when the lights over it twinkle): with four snowy windows a frame went from 6.0 to 3.5 ms.
  - Deliberate difference: snow breaking off a full window edge does not boost the frame rate to 30 fps (only a whole window's snow falling does); in a storm it otherwise stayed at 30 fps.
- The overlays are `override_redirect` and are raised again only when a managed app window is above them (`needs_raise`), never above menus: raising every 2 seconds like Windows hid the tray menu (an override-redirect `xapp-sn-watcher` popup on Cinnamon) behind the snow.
- Panels: Cinnamon draws its panels itself, so the ground comes from the per-monitor work areas in `_GTK_WORKAREAS_D<n>` (dock struts as fallback for Xfce, MATE, KDE). `_NET_WORKAREA` is one rectangle for all monitors and gives the wrong ground on a monitor with a taller panel.
- A lock shows on Cinnamon as the screen saver being active (logind's `LockedHint` stays false), so both are watched.
- **Self-update (`linux/src/updater.rs`, as `src/Updater.cs`):** checks `rkl1976/christmas`, downloads `JuleHygge-linux-x86_64.tar.gz`, checks GitHub's SHA-256 digest and that the binary's embedded version marker equals the release tag (the downloaded binary is never run), renames it over the running binary and exits with code 3; the supervisor then `exec`s the new binary. Test on a copy: `JULE_UPDATE_TARBALL=file.tar.gz JULE_UPDATE_TARBALL_VERSION=x.y.z` (with `JULE_UPDATE_DELAY=N`) stands in for GitHub; `--update-test=github` checks without installing. Local builds are 0.0.0 and never update.
- Install with `install.sh` from the release tarball (per user, `~/.local/share/JuleHygge`, no root); it never sets up autostart unless asked (`--autostart` or *Start ved login* in the menu).
