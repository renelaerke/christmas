# Carnival theme: where it stands (2026-11-25)

The idea, REL's rulings and the plan for the camera are in `docs/karneval-ide.md`; how it is built is in
`macos/README.md` ("Karneval") and `AGENTS.md`. Built on macOS only, directly on `main`.

## Seen and not seen

Seen on snapshots (`macos/tools/karneval-snapshots.sh`, pictures in `build-test/karneval`): the scene with the
finished float, the garland with its masks, toucans on window edges, six of the eight kinds of walker, the band
truck, and the cart of the street sweepers.

**Not seen or heard:**
- Anything moving, which is the point of this theme: that everyone steps in time has not been watched.
- The two sweepers with brooms (they were outside the close-up), and the float at its earlier steps.
- The drums. `--lyd-test` writes `karneval-trommer.wav`; nobody has listened to it. Drums are harder to make
  sound right than a melody, so listen before judging the theme.
- The camera's scene (nothing is drawn on the person, by design, but the scene behind and in front is carnival).

## Not measured

CPU and power. The confetti is New Year's (measured there at 9.4 % of a core against 8.1 % for Halloween); the
toucans are a few image layers. The band truck is redrawn every other frame for as long as it is out, and it
takes over a minute to cross three screens at its walking pace, with the frame rate boosted all the while. That
is the thing to measure.

## Not built

- **Windows and Linux**: REL first said macOS only, then asked for them on 2026-11-25, after the macOS work was
  committed. Until they are done, a version that does not know theme 5 shows Christmas.
- **The camera** (REL: later). What to build and how is written in `docs/karneval-ide.md`.
- **A procession** across the screens (REL chose walking in time instead).
- **Regional forms** of carnival by language and country, which is why the menu says just "Karneval".

## Choices made while building (mine, not ruled on by REL)

- The beat is 120 to the minute, and every walker steps on it or half a bar off it.
- The band truck drives at 70 points a second, slower than Santa flies, so the drums last.
- The walkers carry a shaker where the nisser carry a gift; the flag bearer and the two drummers never do.
- The garland keeps the Christmas lights' coloured bulbs, with the fringe and the masks added.
- The float's great figure is a smiling sun.
- The menu texts are in the eight languages, with Brazilian Portuguese's own words (trio elétrico, garis,
  foliões) in `pt-BR.ini`. None has been read by a native speaker.

## The Rhineland's form (added 2026-11-25, on REL's "extend with a german carnival version")

A second carnival beside Rio's, chosen in the menu "Karneval fra" or automatically where the language or the
country is German. Built on macOS only. What it is, slot by slot, is in `macos/README.md`.

- **Seen on snapshots** (`build-test/karneval-rhein`): the finished float with its jester's head, the garland of
  pennants and jester caps, a cap and a doughnut on a window edge, five of the eight walkers (clown, guardsman,
  guard girl, tuba player, bee), and the tractor with its wagon, band, prince and thrown sweets.
- **Not seen:** anything moving; the prince, the drummer and the jester as walkers; the guard girl's kick.
  The music is settled, see the last section.
- **Not checked against a source:** everything about the Rhineland's carnival here is from general knowledge
  (the town guards' red and white, the dancing guard girl, the patchwork clown, the prince, Kamelle, the
  doughnuts). No web research was done for this form, unlike Rio's.
- **Choices of mine:** the automatic rule also gives this form in Austria and Switzerland, whose own carnivals
  (Fasching, Fasnacht with wooden masks) are different; the guardsman carries flowers, not a rifle; no greeting
  is written anywhere; the wagon's great figure is a jester, not a caricature.

## The Rhineland wagon's music (2026-11-25)

- Four synthesized marches never sounded like brass to REL (thin, flute, organ, "still not brass"), big U.S.
  Marine Band recordings were "not simple brass bands", and the paid libraries he found (TunePocket, audiohub)
  forbid putting the audio file in a public repository. He chose the **Hannerl Polka** (Blaskapelle Franz
  Stremnitzer, CC BY 3.0 on Wikimedia Commons): `assets/lyd/hannerl-polka.wav`, source in `assets/lyd/KILDER.md`.
- The walkers follow the recording's measured beats (`tools/takt.py`, `Controller.advanceBeat`); measured live
  within 0.02 of a beat. REL heard the test build play it and had it committed ("i already heard it"); he has not said how the
  walkers look against it.
- Open: the licence was given by the band's leader, and the Commons page does not show the composer's (Hans
  Kummerer) own permission. The loop joins after 128 beats, chosen by count, not by ear. The piece is Austrian,
  not Rhenish. Not installed: the installed app still has the second synthesized march.

## Windows (written 2026-11-25, on REL's "Start looking at the windows and linux animations")

Ported from the macOS code on a Mac: `src/LayerKarneval.cs`, `src/LayerKarnevalRhein.cs` and the hooks in
`Controller.cs`, `Layer.cs`, `Settings.cs`, `Sound.cs`, `build.ps1`. Both forms, without the camera.

- **Checked:** it compiles with mono at C# 5 (no errors), and `--lyd-test` under mono writes the drums (4.0 s) and
  the band recording (63.3 s, read from the exe's resources) at the same lengths and levels as macOS.
- **Never seen:** every drawing (GDI+ cannot run on the Mac), the menu, the beat-following. The walkers' phases
  come straight from the beat, so they should move more smoothly than the macOS frames, but nobody has looked.
- **To check first on Windows:** that nothing leaves marks (the walkers' cleared box was widened for the flag,
  the float's for the feather fans); that the walkers hit the band's beat (the delay taken off is only the queued
  buffers, 186 ms); CPU with the band truck out (it crosses slowly, with the frame rate boosted all the way).

## Linux (written 2026-11-25 by a sub-agent, reviewed in part)

`linux/src/layer/karneval.rs`, `karneval_rhein.rs` and hooks in 13 files, ported from the Windows C# (not from
the Swift). **Never compiled**: there is no Rust on the Mac, so the first compile is CI after a push. The CI
workflow now saves `screen0-karneval.png` and `screen0-karneval-rhein.png` and checks the two sounds' lengths.

- Reviewed by me: the sound code (drums, recording, playback position) and the truck and sweets in `figures.rs`.
  Not read line by line: the 1600 lines of drawing.
- Likeliest to fail first in CI, by the port's own list: `output_delay` (cpal's timestamp API, written from
  memory), the new test `carnival_leaves_no_trails` (stricter than its model, so a mark box that is too small
  shows there), and two tests with pixel positions worked out by hand (the masks' eye holes, the garland's height).
- Differs from Windows: two of the leaves' ten confetti pictures become a feather or a sweet (about one in five,
  in two colours, against one in six in seven colours).
