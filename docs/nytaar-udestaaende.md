# New Year theme: where it stands (2026-11-25)

The idea and REL's rulings are in `docs/nytaar-ide.md`; how it is built is in `macos/README.md` ("Nytår") and
`AGENTS.md`. Built on macOS only, directly on `main`, uncommitted when this was written.

## Seen and not seen

Seen on snapshots (`macos/tools/nytaar-snapshots.sh`, pictures in `build-test/nytaar`): the scene, the clock at
steps 1, 4, 8 and 12, the guests, the garland, a volley, the sweeper, the guests gathered with a second written
over the clock, and midnight with the year in sparks. The paper hat was seen on five saved camera frames.

**Not seen or heard:**
- Anything moving. Snapshots are stills: the rockets' rise and bloom, the confetti's fall, the guests' jump and
  the sweeper's brush have only been seen frozen. REL saw the test runs on his screens in passing.
- The menu bar countdown. Its text is right in the log (`menu bar: '…'`), but how it looks beside the snowflake
  (font, width, the icon's place) has not been looked at.
- Every sound. `--lyd-test` writes `nytaar-melodi.wav` and `nytaar-klokke.wav`; nobody has listened to them.
- The camera's scene (rockets and the year behind the person, guests in front) and the hat live.
- A real midnight, and a midnight with the screens asleep or the camera in use.

## Measured

Calm scene, three guests, 30 s with `measure.sh` on REL's three screens: New Year 9.4 % of a core (WindowServer
57 %), Halloween in the same minute 8.1 % (55 %). Not measured: a volley, and midnight (rockets on three screens,
a confetti storm and the year at once).

## Not built

- **Windows and Linux.** Nothing. A version that does not know theme 4 shows Christmas.
- **Local luck by region** (REL: yes, as a second round). The rows are in `docs/nytaar-ide.md`; they must keep
  to the no-drinking ruling.
- **Sounds:** a rocket's whistle and the crackle of a burst. The sweeper borrows the leaf collector's suction and
  a quieter plow engine; it has no sound of its own.
- **Translations of the notice** when the clock is finished (notices are Danish in every theme).
- The menu texts are in en, de, sv, nl, it, es, fr and pt; es-MX and pt-BR fall back to es and pt. None has been
  read by a native speaker. Words to check first: nl "sterretjes" and "confettiknallers", de "Tischbomben",
  it "sparacoriandoli", es "lanzaconfetis".

## Choices made while building (mine, not ruled on by REL)

- The clock itself stands from step 1 and only the decoration grows, because the hands are the countdown.
- The bell and everything else start together at midnight; the tune waits for the twelve strokes. (The idea said
  "twelve strokes first", which would have delayed the burst by 16 s whenever sound is on.)
- The confetti burst at midnight is the storm setting for 35 s, which also brings the storm's wind.
- The year stays in the menu bar for ten minutes after midnight, and the greeting in the menu for an hour.
- With the rockets switched off, midnight still has the confetti, the jump and the year in sparks.
- Rockets go up over all screens at once, where Santa crosses one row of screens.
- The camera hat (REL's rulings, in order): stripes; bands round it instead of stripes running up it; two bands,
  not three; its colour drawn at random from the guests' hat colours each time the camera is taken into use; and
  a true cone that follows its band's angle. On a gold or orange hat the bands and brim are silver (my choice).
