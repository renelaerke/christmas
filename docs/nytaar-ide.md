# New Year as a theme: research and a proposed mapping (2026-11-25)

> **Status:** built on macOS 2026-11-25 (see `docs/nytaar-udestaaende.md`); this is the idea as it was written before that. There is no New Year sketch in `docs/temaer/index.html` (its nine themes are
> jul, muertos, halloween, sankthans, forår, påske, sommer, vinter, efterår), so this starts from the elements the
> four built themes share. REL ruled on the open choices the same day; see "REL's rulings" at the end, which
> win over anything above them that says otherwise.

## What makes New Year different from the other themes

1. **It has a moment.** Every other theme is a mood that lasts for days. New Year is five quiet days and then one
   minute, midnight, that everything points at. A theme without that minute would miss the point.
2. **It is short.** In use from about 27 December to 1 January, like the Day of the Dead and Halloween. So what is
   built in the snowman's place should grow by the running hour (`Theme.growsByHour`, `OfrendaSeconds`), not by
   the day.
3. **It is winter.** Snow still fits. The other themes replace the snow; here that is a choice.
4. **It is the same everywhere, with local luck on top.** Clock, fireworks, confetti, bubbles and paper hats are
   understood in every language the menu has. What differs by country is what brings luck, and the app already
   has a table for "who walks at the bottom, by language and region" (`Folk`).

## Proposed mapping

`Theme = 4`, in the menu "Tema" as "Nytår". Never chosen automatically, like the others. A version that does not
know the number shows Christmas (the rule from Halloween).

| Christmas | New Year | Built on |
|---|---|---|
| Snow | **Confetti and paper streamers** in gold, silver and a few strong colours, falling thinly. Small pictures like leaves and petals. | `fallImages` / `LeafSprite` / `leaf_sprites`: the petals did exactly this on all three platforms. |
| Pile at the bottom and on windows | A carpet of confetti, with curls of streamer in it. | Autumn's pile code, another colour (`pile_fill`). |
| On window edges | A sparkler that burns down and is replaced, and party poppers lying with their streamers out. No glasses or bottles. | The pool that holds the Day of the Dead's candles and Halloween's cats (`addLedgeSpooks`, `DrawLedgeCandles`). |
| Snowman | **A large clock on a stand**, whose hands show the real time. It is decorated in 12 steps, one for every hour the app runs (streamers, pennants, lanterns, a sparkler on top), and stands finished until another theme is chosen. | The ofrenda's clock and reset, unchanged; the hands are new. |
| Santa | **A volley of rockets**: they rise from the bottom, burst in a band across the top of the screen and fade. | Santa's schedule and the star shower effect (`starShower`). The particles go straight into the pixel buffer like snow. |
| Nisser | **Party guests** in paper hats with party horns. Where the nisser swap gifts, the guests swap party crackers and blow their horns. | The nisse skeleton in other clothes, as every folk and theme has done. |
| Christmas lights | A string of pennants and paper lanterns, with a few gold bulbs that blink. | The lights' cached image with blinking bulbs. |
| Snow plow | **A small street sweeper** the morning after, with a turning brush, that takes the confetti. No horn. | The leaf blower and the donkey cart. |
| Calendar and countdown | **The countdown to midnight** (see below). The advent calendar is hidden. | The menu's countdown line. |
| Camera (macOS only) | A **paper party hat**: a stiff cone with a pompom, which `CameraLook` already can (`bend` 0 is a stiff cone). Nothing in the beard's place. | `CameraLook`, one new entry. |

Sounds, all synthesized and off by default as always: a rocket's whistle and a soft crackle for the volley, the
brush for the sweeper, and at midnight twelve strokes of a bell.

## Midnight

Nothing in the app today is tied to a time of day; the calendar is tied to a date. This is the one new piece of
machinery:

- **Before:** the menu's countdown line says how long there is to midnight on 31 December (days, then hours, then
  minutes), in the place where it counts the days to Christmas.
- **The last ten seconds:** nothing new. A number on the screen would need care on three screens, and the moment
  is better kept for the stroke itself.
- **At 00:00 on 1 January, local time, if the theme is on and the screens are awake:** about a minute of the big
  effect: rockets one after the other over the whole width, a burst of confetti, the guests jump (in Denmark one
  jumps down from a chair into the new year), and **the new year's four digits written in sparks**. Digits need no
  translation. With sound on: twelve bell strokes first.
- **After:** the theme goes on as before, and the sweeper comes by some minutes later. If the screens were asleep
  at midnight, the effect is simply skipped; it is not played late.
- **Test aid:** `JULE_DATE` only moves the date, so this needs its own: for example `JULE_NYTAAR_OM=N` (midnight
  in N seconds), in the manner of `JULE_VEJR_TID`.

REL dropped Halloween's calendar and countdown because a theme that is never chosen automatically has no date to
count to. New Year is the opposite case: the date is the theme. But the same objection can be raised, so it is
his call (see the open choices).

## Local luck (optional, later)

The `Folk` tables could give the guests a companion by language and region, the way they give the nisser their
national cousins. What people actually do on the night:

| Where | Tradition | As a figure or detail |
|---|---|---|
| Denmark, Norway | Kransekage; jumping into the new year from a chair | Already the proposal's centre. |
| Germany, Austria | Lucky charms given on the night: chimney sweep, pig, four-leaf clover, ladybird; pouring molten tin to read the year | A chimney sweep among the guests, a small pig trotting after one. |
| Netherlands | Oliebollen | A bowl of oliebollen in a guest's hands. See the note on fireworks below. |
| Spain, Mexico | Twelve grapes on the twelve strokes | Guests holding a bunch of grapes; at midnight they eat. |
| Italy | Lentils and red clothes for luck | A red scarf on the guests. |
| Portugal, Brazil | Twelve raisins; in Brazil white clothes and flowers thrown into the sea | Guests in white for `pt-BR`. |
| Estonia | Eating seven, nine or twelve times for strength | Hard to draw; leave out. |
| Britain, the USA | Auld Lang Syne, linking arms | Guests link arms when they meet. |

This is a second round at the earliest: the first is the same guests everywhere.

## Two cautions

- **Fireworks are not welcome everywhere.** The Netherlands banned consumer fireworks nationwide from 1 August
  2026, so this New Year is the first under the ban, chiefly out of concern for animals and injuries; sparklers
  are still allowed there. A drawn rocket harms no one, but the rockets should be a menu item of their own that
  can be switched off (as Santa is), and the sound stays off by default. The sparkler and the confetti carry the
  theme without them.
- **Flashes on a work screen.** Bursts should be soft and slow (a bloom that fades over a second or two), in the
  top band only, and never a full-screen flash. Santa's "30 fps while he flies" boost applies during a volley;
  measure CPU and power as for any drawing change.

## The tune

Every flyer so far has an original tune. Two ways: an original one (a light waltz or a fanfare for brass), or
"Auld Lang Syne", whose melody is traditional and old enough to be free of rights. The project's rule is that
figures must be original and sound is synthesized; a traditional melody breaks neither, but it would be the first
tune that is not ours. **REL.**

## Size of the work

Close to Halloween, which was one day for all three platforms once macOS was seen and steered: one new drawing
file per platform (`OverlayNytaar.swift`, `src/LayerNytaar.cs`, `linux/src/layer/nytaar.rs`), the theme's flags,
about a dozen menu texts in every language file, two or three sounds, CI snapshots for Linux. On top of that the
midnight event, which is new in all three controllers, and its test aid. No new techniques: confetti is the
petals, the kransekage is the ofrenda, the rockets are the star shower.

As always: macOS first and seen on snapshots and live before the ports; Windows compiled with mono but not seen
here; Linux only in CI.

## Open choices (REL)

1. **Confetti instead of snow, or snow with confetti only at midnight?** The proposal is confetti all the time,
   because every theme has its own fall and the pile, the windows and the sweeper follow from it.
2. **The countdown and the midnight minute:** build them, or keep the theme a mood like the others?
3. **What stands in the snowman's place:** the kransekage (Danish and Norwegian, and the app is Danish), or
   something every country knows: a tower of champagne glasses, or a large clock whose hands creep to twelve.
4. **Rockets as the flyer**, given the caution above, or something quieter in Santa's place (a cork that pops and
   a spray of bubbles; a paper lantern drifting across).
5. **The tune:** original or Auld Lang Syne.
6. **Local luck:** worth a second round?

## Sources

- The element slots: `docs/temaer/index.html`, `macos/Sources/JuleHygge/Theme.swift`, `AGENTS.md`.
- The Dutch ban: [IamExpat, first New Year's Eve under the ban](https://www.iamexpat.nl/expat-info/dutch-news/first-new-years-eve-under-dutch-fireworks-ban-what-expect), [NL Times, 1 July 2026](https://nltimes.nl/2026/07/01/dutch-consumer-fireworks-ban-cleared-take-effect-new-years-eve), [business.gov.nl](https://business.gov.nl/amendments/no-sales-consumer-fireworks-due-to-ban/).
- Traditions by country: [Wikipedia, New Year's Eve](https://en.wikipedia.org/wiki/New_Year%27s_Eve), [CGTN, traditions across Europe](https://newseu.cgtn.com/news/2019-12-31/Grapes-singing-and-coal-New-Year-s-Eve-traditions-across-Europe-MQHJ5hthny/index.html). The search confirmed the Spanish grapes, the German tin pouring and the Estonian meals; the Danish, Italian, Portuguese and Brazilian rows are from general knowledge and were not checked against a source.

## REL's rulings (2026-11-25)

1. **Confetti all the time.**
2. **In the snowman's place: something every country knows, and it must not promote drinking.** So no kransekage
   and no tower of glasses: the large clock. The rule reaches further than that one slot, and the mapping above
   is corrected to match: no champagne glasses on the window edges, no clinking guests, no bottles or corks
   anywhere in the theme. (That it covers the whole theme is my reading of his sentence.)
3. **Rockets** as the flyer. Still a menu item that can be switched off, as Santa is.
4. **Auld Lang Syne** as the tune.
5. **Local luck by region: yes.** As the second round, after the common guests. Its rows must keep to ruling 2
   (the table above has no drink in it).
6. **Midnight:** "countdown activity and menu bar - but burst of activity at midnight". My reading: the countdown
   is shown in the menu bar and also as activity on the screen, and midnight itself gets the burst. This
   replaces "the last ten seconds: nothing new" above. What I propose for it:
   - **Menu bar:** on macOS the time left stands beside the snowflake in the menu bar on 31 December (hours and
     minutes, seconds in the last minute). Windows' tray and most Linux panels show only an icon, so there it is
     the icon's tooltip and the menu's countdown line.
   - **On the screen:** the clock's hands are the countdown all along. In the last ten minutes the guests gather
     at the clock; in the last ten seconds the seconds are written in sparks above it, one digit at a time.
   - **At midnight:** the burst as described under "Midnight".
