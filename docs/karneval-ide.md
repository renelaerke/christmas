# Brazilian carnival as a theme: research and a proposed mapping (2026-11-25)

> **Status:** an idea, nothing built, and nothing here is ruled on by REL. There is no carnival sketch in
> `docs/temaer/index.html`, so this starts from the elements the five built themes share (jul, efterår, de dødes
> dag, halloween, nytår).

## What makes carnival different from the other themes

1. **It is a procession.** Every other theme's walkers wander back and forth. Carnival is people moving the same
   way, in order, to the same beat: a samba school's parade, a bloco behind its band, a crowd behind a truck.
   A theme where the figures only wander would be a costume party, not carnival.
2. **It is music first.** The other themes have a tune that plays while something flies over. Here the drums are
   the thing itself: the bateria sets the pace of everything that moves.
3. **Its date moves.** Carnival Tuesday is 47 days before Easter Sunday. In 2027 Easter is 28 March, so carnival
   runs from Friday 5 February (Saturday 6 in some places) to Tuesday 9, and Ash Wednesday is 10 February. A
   countdown needs the Easter calculation, which nothing in the app has yet.
4. **It has an end, not a moment.** New Year points at midnight. Carnival runs for days and then stops on Ash
   Wednesday morning, when the streets are swept.
5. **It is short**, like the three before it: in use for about a week, so what is built in the snowman's place
   should grow by the running hour (`Theme.growsByHour`, `OfrendaSeconds`).
6. **It is three carnivals, not one.** Rio de Janeiro: samba schools parading in the Sambadrome. Salvador: the
   trio elétrico, a truck with a band on it that the crowd follows (since 1951), and the blocos afro. Recife and
   Olinda: frevo, a fast brass music danced with a small umbrella, and giant puppets carried through the streets.

## Proposed mapping

`Theme = 5`, in the menu "Tema" as "Karneval". Never chosen automatically; a version that does not know the
number shows Christmas.

| Christmas | Carnival | Built on |
|---|---|---|
| Snow | **Confetti and serpentina** (both are what is actually thrown), with feathers and a few sequins among them so it does not look like New Year. | New Year's confetti pictures and code, with two more shapes. |
| Pile at the bottom and on windows | A carpet of confetti, with feathers lying in it. | New Year's pile. |
| On window edges | **Toucans** perched on the edges, turning their heads and now and then clacking their beaks; fringe garlands hanging under the edge. | The pool that holds Halloween's cats and New Year's sparklers. |
| Snowman | **A carnival float (carro alegórico) being built**, 12 steps, one for every hour the app runs: the chassis, the platform, the skirt, steps, columns, a great figure on top (a sun, or a bird with its tail spread), feathers, lights. Building the floats is the samba schools' work all year. | The ofrenda's clock and reset, as the clock and the lanterns. |
| Santa | **A flight of macaws**, scarlet and blue-and-yellow, crossing in a loose row and calling. | Santa's trip, as the geese and the butterflies. |
| Nisser | **The parade** (see below): a flag couple, baianas in wide skirts who spin, dancers in feather headdresses, drummers, and the old carnival trio Pierrot, Columbine and Harlequin. | The nisse skeleton in other clothes, and New Year's fixed looks (`Nisse.look`). |
| Christmas lights | Fringe garlands in bright colours with carnival masks hanging between coloured bulbs. | The lights' cached image with blinking bulbs. |
| Snow plow | **The street sweepers of Ash Wednesday**: two sweepers in orange with brooms and a cart, one of them dancing as he sweeps. No horn. | The Day of the Dead's cart and broom, with its broom sound. |
| Calendar and countdown | A countdown to carnival Saturday; during carnival "Carnival!"; the calendar is hidden. | The menu's countdown line and the Easter calculation (new). |
| Camera (macOS only) | A **band of tall feathers** on the brow in the hat's place, and a **sequin half-mask** over the eyes in the beard's. No suit. | The flower crown's ring (`NisseHat.flowerCrown`) and the calavera make-up's landmarks (`Makeup.swift`). |

Sounds, all synthesized and off by default: a samba batucada (the drums), a whistle that starts it, the macaws'
call, and the broom.

## The parade (the one new piece of machinery)

Two ways to do the walkers, and they differ a lot in work:

- **As the other themes:** the figures wander, stop, wave and meet. It costs nothing new, and "meeting" has a
  natural form here: the flag bearer (porta-bandeira) and her escort (mestre-sala) dance round each other, which
  is exactly what the couple does in a real parade.
- **As a procession:** every few minutes a parade crosses the screens in one direction and in the order a real
  one has: the opening group, the flag couple, a wing of baianas, the drums, dancers, and last the float from the
  snowman's place rolling by when it is finished. Between parades the stragglers wander as usual. This is new in
  all three versions (it is closest to the plow's run across the screens, with many figures instead of one).

A cheap step toward the second: **walk in time**. With sound on or off, lock every walker's step to the drums'
beat, so the whole bottom of the screen moves together. That alone makes it read as carnival.

A real samba school parades in sections, and these are the ones worth drawing: the comissão de frente (ten to
fifteen people who open the parade), the mestre-sala and porta-bandeira with the school's flag, the ala das
baianas, the bateria, and the floats.

## Three carnivals, one theme

Rio's parade is the proposal's core, because it is the picture most people have. The other two could come in as
details in the first round or as regional forms later:

| Where | What | As a figure or detail |
|---|---|---|
| Rio de Janeiro | Samba schools, the Sambadrome | The parade above. |
| Salvador | Trio elétrico; blocos afro | A truck with a band on it in the plow's place during carnival (the sweepers only on the last day), followed by walkers. |
| Recife, Olinda | Frevo; giant puppets | Dancers with small coloured umbrellas; a giant puppet in the snowman's place instead of the float. |

The app cannot tell a Brazilian state from the system's language or region (`pt-BR` is all it sees), so these
cannot be chosen automatically the way the `Folk` tables choose a nisse or a Wichtel.

**The same days elsewhere.** Carnival is the same feast as Danish fastelavn (Sunday 7 February 2027), German
Karneval and Fasching, Dutch carnaval, Venice and New Orleans. The `Folk` mechanism could one day give the theme
a local form by language and region. REL asked for the Brazilian one; this is only noted.

## Cautions

- **Drinking.** REL ruled for New Year that the theme must not promote drinking. I assume it holds here too: no
  cans, cups or bottles anywhere, though street carnival is full of them.
- **Costumes on a work screen.** The best-known carnival costume is very little costume. The dancers here should
  be drawn as the figures always are: small, clothed, friendly, with the feathers and the colour carrying it.
- **People, not caricatures.** Samba, the baianas and the blocos afro are Afro-Brazilian culture. The figures
  should have the range of skin tones New Year's guests have, and the baianas' dress should be drawn as it is
  (white lace, wide skirt, head wrap, beads), not exaggerated. Costumes that dress up as another people
  ("Indian" costumes) are contested in Brazil and should be left out.
- **Original figures and music.** Olinda's giant puppets often portray real people: ours must not. The drum
  pattern must be our own, and no samba school's song (samba-enredo) can be used: they are under copyright.
- **Brightness.** Bulbs and sequins twinkle; nothing should flash. The same rule as the rockets.

## Size of the work

More than Halloween or New Year, mostly because of the parade:

- **Reused as it is:** the confetti, the pile, the hour clock, the sweeper's broom sound, the fixed looks.
- **New drawing:** one file per platform with the float in 12 steps, five or six kinds of walker, the macaws, the
  toucans, the garland, the sweepers; two camera pieces on macOS.
- **New logic:** the Easter calculation for the countdown; walking in time with the drums; and, if chosen, the
  procession in all three controllers.
- **Sound:** a batucada is several drums in a pattern, more work to synthesize well than a melody. The geese
  needed a recording after two failed tries at synthesis; drums are easier than voices, but it should be listened
  to early.

As always: macOS first and seen on snapshots and live before the ports; Windows compiled with mono but not seen
here; Linux only in CI.

## Open choices (REL)

1. **Which carnival:** Rio's parade as the core (the proposal), or a mix of the three from the start?
2. **The walkers:** wandering as in the other themes, wandering in time with the drums, or a real procession?
3. **In the snowman's place:** a float being built, or an Olinda giant puppet?
4. **The flyer:** macaws, or nothing in the air and a trio elétrico on the ground instead?
5. **On the window edges:** toucans, or something else (masks, garlands only)?
6. **The countdown:** build it (with the Easter calculation), or leave it out as on Halloween?
7. **Drinking:** does the New Year ruling hold here? (Assumed yes.)
8. **The name in the menu:** "Karneval", or "Brasiliansk karneval" to leave room for fastelavn later?

## Sources

- Dates for 2027: [Band](https://www.band.com.br/entretenimento/quando-e-o-carnaval-em-2027-veja-a-data), [InfoMoney](https://www.infomoney.com.br/brasil/quando-e-carnaval-2027/), [Diário do Pará](https://diariodopara.com.br/carnaval/quando-sera-o-carnaval-2027-veja-como-a-data-e-definida/) (the Friday or the Saturday is given as the start, depending on the source).
- The parade's sections: [Wikipedia, Samba school](https://en.wikipedia.org/wiki/Samba_school), [The Rio Times, carnival glossary](https://www.riotimesonline.com/rios-carnival-glossary/).
- The three carnivals: [Wikipedia, Brazilian Carnival](https://en.wikipedia.org/wiki/Brazilian_Carnival), [Wikipedia, Frevo](https://en.wikipedia.org/wiki/Frevo), [National Geographic Brasil](https://www.nationalgeographicbrasil.com/viagem/2024/02/carnaval-no-brasil-conheca-4-formas-de-comemorar-a-festa), [NPR on Recife](https://www.npr.org/2014/02/28/283974795/in-recife-3-rhythms-get-the-carnival-party-started).
- **Not checked against a source** (from general knowledge): that confetti and serpentina are what is thrown;
  the drums of a bateria and their roles; Pierrot, Columbine and Harlequin as carnival figures; the street
  sweepers of Ash Wednesday and their dancing; that "Indian" costumes are contested; the dates of fastelavn and
  the other countries' carnivals; that samba-enredos are under copyright.

## REL's rulings (2026-11-25)

These win over anything above that says otherwise.

1. **Rio's parade** is the core.
2. **The walkers wander in time with the drums.** No procession across the screens.
3. **A float being built** stands in the snowman's place ("I think").
4. **A band truck on the ground**, and nothing in the air: no macaws. My reading of where it goes: it takes
   Santa's place (his schedule, his menu items and his switch, and the drums play while it passes), driving along
   the bottom of the screens like the plow, and the street sweepers stay in the plow's place. A trio elétrico is
   Salvador's, not Rio's; REL chose it knowing that, so the theme is Rio's parade with Salvador's truck.
5. **Toucans** on the window edges.
6. **No countdown**, as on Halloween. So no Easter calculation is needed, and the calendar and the countdown line
   are both hidden.
7. **The no-drinking ruling holds here too.**
8. **"Karneval"** in the menu, because the theme can be built to vary by region and culture later.

What follows from them:
- With no flyer, nothing crosses the upper part of the screen in this theme. The truck and the sweepers both run
  along the bottom, so they must never be out at the same time.
- "In time with the drums" needs one beat that every screen's walkers share, kept by the controller whether the
  sound is on or off.

## Later rulings (2026-11-25, same day)

9. **macOS only for now.** Windows and Linux wait.
10. **The camera is not built now**: "document the camera extension for karneval - we will do that later". Until
    it is built, the carnival theme shows nothing on the person in JuleHygge Kamera: the hat, beard and suit items
    are hidden in the menu and switched off (`VirtualCamera`), while the scene behind and in front of the person
    is the carnival one.

## The camera, for later: what to build and how

What the person wears, in the hat's and the beard's places; nothing in the suit's:

| Piece | What it is | Built on | Pitfalls already met |
|---|---|---|---|
| **Feather band** | A band round the brow with a fan of tall feathers standing up from it, tallest over the forehead, in two or three colours, each feather bending a little outward. | The measured brim ring, exactly as the Day of the Dead's flower crown (`NisseHat.flowerCrown`, `place(ph:size:lift:out:)`): things placed round the ring, the far half kept on the measured outline. Each feather is a narrow quad strip along the ring's own axis `g.N`, leaning out along the ring's normal. | Build it on the ring's axis, not upright in the picture: the paper hat stood upright while its band tilted, until it was rebuilt as a cone on the ring (`CameraLook.cone`). Feathers behind the head must be clamped to the outline as the crown's flowers are. |
| **Sequin half-mask** | A mask over the eyes and the bridge of the nose, with two eye holes, a glitter edge and a small plume at one temple. | The calavera make-up's face landmarks (`Makeup.swift`): the eyes' outlines give the holes, the brows its upper edge, the nose crest its lower point. | A landmark that stands out from the face must be rebuilt in 3D with the head's axes before anything is built on it (the witch's nose: `witchNose`, `Track.noseTop/noseUnder`). The eyes lie on the face, so the mask itself can follow the landmarks directly; the plume at the temple cannot. Glasses: the mask is drawn over them, as the make-up is. |

How it is wired, following the other themes:
- `CameraCostume.karneval`, set from the theme before each camera frame in `VirtualCamera` (the hat and costume are
  drawn on the camera's queue and do not see the controller); `HUE_KARNEVAL=1` sets it in `--kamera-replay`.
- The feather band is drawn where `parts()` returns the flower crown for `CameraCostume.muertos`; the mask where
  `applyMakeup` is called (`wantsMakeup`).
- Menu: "Nissehue på i kameraet" becomes "Fjerpragt på i kameraet", "Nisseskæg i kameraet" becomes "Maske i
  kameraet"; the suit item stays hidden. Both texts need all eight language files.
- A random colour for the feathers each time the camera is taken into use, as the paper hat has
  (`CameraLook.partyHat`), would fit.

How to see it before installing: `HUE_KARNEVAL=1 … --kamera-replay=MAPPE` on the saved frames in
`build-test/kamera` (28 frames, with the head turned about 50° each way and leaned back), and look at the turned
and leaned-back ones first: that is where the hat, the nose and the pumpkin head each went wrong.
