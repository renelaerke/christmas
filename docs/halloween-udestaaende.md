# Halloween: hvad der er lavet, og hvad der mangler

Tema nr. 3 i menuen "Tema" (`Theme.halloween`), kun macOS, første runde 2026-11-24 på grenen `halloween` (skåret af
`muertos`). Bygget ud fra skitsen "halloween" i `docs/temaer/index.html`.

## Lavet (macOS)

Efterårets blade for sne, græskarlygter i 12 trin (ét pr. time appen kører, som ofrendaen), heks på kost med kat og
flagermus, spøgelser og udklædte børn, lyskæde med græskarlygter og sovende flagermus, katte og edderkopper på
vindueskanterne, menutekster på alle sprogene og heksens melodi.

Set på `--snapshot`-billeder: hele skærmen med alt slået til, og lygterne ved trin 2, 4, 6, 9 og 12. Menuen er set
som tekst (`JULE_MENU_DUMP`). Melodien er skrevet ud som fil (10,1 s).

## Ikke set eller prøvet

- Ikke set live, kun stillbilleder: bevægelserne (spøgelsernes svæv, heksens kappe, flagermusenes vinger, kattens
  hale, edderkoppernes tråd, lygternes blink) er kun tegnet, ikke set bevæge sig.
- Melodien er ikke hørt af nogen.
- Skiftet til og fra temaet i menuen (som tager lygterne ned), og beskeden, når de er færdige.
- Strømforbrug er ikke målt med `measure.sh`.
- Kamerascenen (JuleHygge Kamera) i temaet.

## Valg, der er mine, og som REL ikke har taget stilling til

- **Lygterne bygges pr. time** ligesom ofrendaen (temaet er kun i brug nogle få dage). De deler `OfrendaSeconds`.
- **Bladene er efterårets** i efterårets farver; skitsen har mørkere blade og flagermus imellem. Flagermusene følger
  heksen i stedet.
- **Hver anden gående er et spøgelse**, resten skiftevis en lille heks og et lille græskar.
- Skitsens måne, tåge og spindelvæv i vinduernes hjørner er ikke lavet. Skitsens kalender og nedtælling (en
  Halloween-udgave af julekalenderen og dens nedtælling) er droppet af REL 2026-11-24 og skal ikke laves.

## Kameraet (samme dag, efter REL's anvisninger)

Ét valg i menuen, "Udklædning i kameraet": Ingen, Heksehat og heksenæse, Græskarhoved (`CameraHalloween`). REL:
de to skal være alternativer; heksen skal have næse, grønlig hud og sort tøj.

- **Heks:** hat, næse, sort tøj og grøn hud. Næsen blev lavet om tre gange. Først var den sat fast ved næseroden
  og hang ned; så stod den på den målte tip, men roden sad forkert, når hovedet var drejet (REL: 3D-modellen og
  ansigtsmålingens 2D-punkter passede ikke sammen); nu er den rigtige næse genopbygget i 3D (se AGENTS.md), og REL
  kaldte den "much better".
- **Græskarhoved:** hele hovedet som udskåret, lysende græskar, der drejer med.

Set på syv gemte kamerabilleder med `--kamera-replay` (forfra, drejet til begge sider, to rum, en hånd foran
ansigtet). Ikke set: live i et opkald, kig nedad og lænet tilbage, flere personer, andre næser end REL's, og hvad
det koster i strøm. Kameraets synsvinkel er antaget (70°), ikke målt.

## I plovens sted (samme dag)

REL valgte to af mine forslag, med lige stor chance pr. tur: heksen fejer, eller spøgelserne puster. Set på ét
stillbillede af hver (`build-test/vis/`). Ikke set i bevægelse, og lydene (kost, spøgelsessus) er ikke hørt.

## Mangler

- **Windows og Linux har temaet (uden kameraet), skrevet 2026-11-24 på REL's ord, men er ikke set:**
  - Windows (`src/LayerHalloween.cs`): kompilerer med mono, og de to lyde er skrevet ud under mono (heksens melodi
    10,1 s, spøgelsernes sus 4,0 s). Tegningen er aldrig set.
  - Linux (`linux/src/layer/halloween.rs`): aldrig kompileret her; bygges, testes og fotograferes i CI, når det
    bliver pushet.
- Oversættelserne af de 12 nye menutekster er mine og ikke læst af nogen med sproget som modersmål.
