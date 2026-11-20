# JuleHygge til macOS 🎄

Native macOS-udgave (Swift + AppKit + Core Animation) af juleoverlayet. Samme indhold som Windows-versionen: snevejr, sne der lægger sig i bunden af skærmen, julemanden med rensdyr på tværs af skærme, nisser, julelys under menulinjen, snemand der bygges over 12 dage, sneplov og julekalender med 24 låger.

- Bor i **menulinjen** (snefnug-ikonet), ingen Dock-ikon. Klik på ikonet for indstillinger og julekalender.
- Overlayet ligger over alle vinduer og Docken, men man klikker igennem det. Det følger med til alle Spaces.
- Sne og nisser ligger i **bunden af skærmen** på alle skærme.
- Mængden varierer organisk: snefaldet svinger langsomt mellem ca. 60 % og 140 % af den valgte mængde (to bølger på ca. 3 og 7 minutter), og hvert 1½–3 minut kommer eller går en nisse (højst ±2 fra det valgte antal, med træk tilbage mod det). Nye nisser går ind fra skærmkanten. Nisser der skal gå, går ud ad en kant uden skærm bagved, hvis der er en.
- **Nisser skifter skærm:** Når en nisse når en kant med en skærm ved siden af, går den cirka halvdelen af gangene videre over på den anden skærm (samme tøj og retning) i stedet for at vende om.
- Pauser automatisk, når en app kører i fuldskærm (kan slås fra).
- **Strømspare** slår til på batteri eller i macOS' strømsparetilstand: lavere billedfrekvens (se "Strømforbrug"). Sneen falder stadig over hele skærmen (også i Windows-udgaven).
- **Sne på vinduerne** (menuen, `WindowSnow`, til som standard): cirka halvdelen af fnuggene lander på overkanten af andre apps' vinduer (ikke fuldskærm), hvor sneen hober sig op fra ingenting og runder af mod hjørnerne. Den skjules bag vinduer, der ligger foran. Flyttes vinduet, følger sneen med, når det står stille igen. Minimeres eller lukkes vinduet, falder sneen lodret ned fra stedet, hvor vinduet stod, og lander i bunken i bunden. Når bunken bliver dyb, kryber sneen langsomt ud over kanten og hænger ned foran vinduet i bløde lapper af forskellig længde (et fast mønster pr. vindue), lidt mere ved hjørnerne. Når kanten er fuld, knækker et stykke af og til af og falder ned (cirka 1 chance ud af 15 i sekundet), så sneen ikke bare bliver liggende i samme højde. Vinduerne aflæses med `CGWindowListCopyWindowInfo` 4 gange i sekundet (og hver frame, mens et vindue med sne bevæger sig), hvilket ikke kan måles i strømforbruget.
- **Snedriver i snestorm:** Vinden flytter langsomt sne med sig langs bunken og langs vindueskanterne, så den hober sig op mod skærmkanten og vinduets ende i vindretningen. Sneen lægger sig i lange bølger, der hænger sammen på tværs af skærmene. Driverne må blive højere i storm og synker langsomt tilbage bagefter. En fuld bunke beholder bløde bugter på toppen.
- **Nisser mødes:** Når to nisser går mod hinanden, og mindst den ene bærer en pakke, stopper de op ansigt til ansigt. Har kun den ene en pakke, får den anden den; har begge, bytter de.
- **Lyd** (slået fra som standard, slås til hver for sig i menuen): julemandens kane spiller bjælder og en af tre melodier, valgt tilfældigt for hver tur: omkvædet af "Jingle Bells" (Pierpont 1857), "Deck the Halls" (walisisk folkemelodi) eller "We Wish You a Merry Christmas" (engelsk folkemelodi), alle fri af ophavsret. Julemandens fart varierer ±10 % fra tur til tur, og melodien spilles med samme tempo (lidt hurtigere og lysere, eller langsommere og dybere). Sneploven har dieselmotor, skraben der bliver højere med mængden af sne, og et kort horn når den kører ind. Lyden panoreres med figuren hen over skærmene, fader ind og ud ved kanterne og er slået fra under fuldskærmspause. Julens lyde syntetiseres i koden, og lydmotoren kører kun mens noget spiller. (Efterårets gæs er en optagelse, se "Efterårstema".)
- Notifikationer når dagens låge er klar (klik åbner kalenderen).
- "Start ved login" er et almindeligt login-emne. Appen **genstarter sig selv, hvis den crasher**: den starter som en lille vagtproces, der kører selve appen som underproces og starter den igen 5 sekunder efter et crash (den giver op efter 3 hurtige crash i træk). Afslutter man fra menuen, lukker begge. Derfor ses to `JuleHygge`-processer i Aktivitetsovervågning. (En launch agent via `SMAppService.agent` blev afvist af macOS ved hver ny ad-hoc-build — "Launch Constraint Violation" — fordi den er bundet til kodesignaturen.)
- Indstillinger: `~/Library/Application Support/JuleHygge/settings.ini` (samme format som Windows). Fejllog: `~/Library/Logs/JuleHygge.log`.

## Efterårstema

Menuen **Tema** (`Theme`: 0 = jul, 1 = efterår; jul er standard) skifter hele overlayet til efterår. Hvert juleelement har sin efterårsform, og menupunkterne skifter navn med temaet. Temaet findes kun i macOS-udgaven. Idéen bag (og de andre årstider, der ikke er lavet) står i `docs/temaer/index.html`, og det, der mangler, i `docs/efteraar-udestaaende.md`.

| Jul | Efterår |
|---|---|
| Snevejr | Løvfald: færre og større blade, der vender sig i faldet. To former, ovale blade og ahornblade (ca. 80/20), i fem farver og flere størrelser. I efterårsstormen regner det også. |
| Sne i bunden og på vinduerne | Løvbunker af enkelte blade. De vokser, flytter sig i blæst og falder fra vinduer, præcis som sneen. |
| Snemand over 12 dage | En høstak (trin 1–3) og derefter et fugleskræmsel ved siden af (trin 4–12). |
| Julemanden i kane | Otte gæs i kile på vej sydpå. Størrelsen varierer fra tur til tur (dybde), uafhængigt af farten. Ingen gnister. |
| Sneplov | Løvsuger: en grøn vogn med slange og mundstykke, der suger bunken op. |
| Nisser, der bytter pakker | Pindsvin og egern, der bærer og bytter æbler. |
| Julelys | En løvranke med små lygter. |
| (intet) | En drage, der hænger i vinden (menuen "Drage", `Kite`, til som standard). |
| Julekalender og nedtælling | Skjult: kalenderen hører julen til. |
| Nissehue, skæg og dragt i kameraet | Sydvest og gul regnfrakke. Skæggets plads er tom. |

- **Lyd** (stadig slået fra som standard): gæssene er en optagelse, `assets/lyd/gaes-flok.wav` (kilde i `assets/lyd/KILDER.md`), fordi syntetiske gåsekald ikke kom til at lyde ægte. Hver tur vælger en af to stemninger: flokken alene (to ud af tre gange) eller længere væk i blæst (altid i storm). Løvsugeren har motor, en sugelyd i stedet for sneplovens skraben, og horn.
- **Strøm** (målt med `./measure.sh`): dragen koster ca. 0,7 % af en kerne og regnen ca. 1,8 % i storm. WindowServer er uændret.
- **Test:** sæt `Theme=1` i en settings-fil og brug den med `JULE_SETTINGS`. `--julemand` sender gæssene afsted og `--sneplov` løvsugeren; `JULE_DEEPSNOW=1` starter med fuld løvbunke, også på vinduerne; `JULE_NO_RAIN=1` slår regnen fra (til måling); `--lyd-test=MAPPE` gemmer også `gaes-*.wav` og `loevsuger-sug.wav`.

## Byg og kør

Kræver Xcode eller Command Line Tools (Swift 5.10+), macOS 14+.

```bash
./build.sh
```

```bash
open build/JuleHygge.app
```

Installér i `~/Applications` med start ved login (login-emnet peger på den installerede kopi, så senere builds ikke ødelægger det):

```bash
./install.sh
```
Appen er ad-hoc-signeret; til distribution kræves Developer ID-signering og notarisering.

## JuleHygge Kamera (baggrund i Teams)
Et virtuelt kamera, der viser dig foran en levende julescene: nattehimmel, snevejr, julelys, nisser, snemand og julemanden en gang imellem. Vælg "JuleHygge Kamera" som kamera i Teams, og slå Teams' egen baggrund fra.

- `CameraExtension/` er en CoreMediaIO-kameraudvidelse, der kun videresender billeder. Den har en sink-strøm (ind fra appen) og en kilde-strøm (ud til Teams). Når der ikke kommer billeder, viser den et roligt snefnug.
- Appen gør arbejdet (`VirtualCamera.swift`), men kun mens en app læser kameraet. Udvidelsen melder det via en egen egenskab (`jhsr`). Appen læser det rigtige kamera, skærer personen fri med Vision og tegner julescenen på en virtuel "tredje skærm" (`ScreenOverlay(virtualFor:)`, 1280×720, uden vindue). Derefter lægger den personen ovenpå og sender billedet til udvidelsen.
- Kræver Xcode-projektet (`JuleHygge.xcodeproj`, genereres af `tools/make-xcodeproj.py`) og signering med teamets Apple Development-certifikat. Byg og installér i `/Applications` med `./xcbuild.sh`, og vælg derefter **Installér JuleHygge Kamera** i menuen og godkend udvidelsen i Systemindstillinger.
- Engangsforudsætning: Mac'en skal være registreret som enhed på teamet. Åbn projektet i Xcode > Signing & Capabilities > "Register Device", eller tilføj Mac'ens Provisioning UDID på developer.apple.com.
- Ydelse mens kameraet bruges (målt): cirka 27 billeder/s ud, julescenen tegnes på cirka 10 ms (20 gange/s), udskæring på cirka 32 ms pr. billede, og appen bruger cirka 50 % CPU. Skærm-overlayet holder pause imens. Appen skriver `perf:`-linjer i systemloggen (`log show --predicate 'subsystem == "dk.julehygge.JuleHygge"'`).
- **Nisser og sne foran mig i kameraet** (menuen, `CameraFront`, til som standard): kamerascenen tegnes i to lag. Himlen, julelysene, snevejret og julemanden ligger bag personen; sneen i bunden, snemanden, nisserne og sneploven ligger foran. I kameraet er julemanden mindre og flyver i et bånd, hvor hele kanen altid er inde i billedet.
- **Nisseskæg i kameraet** og **Nissedragt i kameraet** (menuen, `CameraBeard` og `CameraSuit`, hver for sig, til som standard):
  - **Skægget:** Visions ansigtspunkter (kæbelinje, næse, læber) giver skæggets form i hvert billede. Det er et hvidt fuldskæg langs kæben og under hagen, med overskæg og åben mund, krøllet struktur og blød kant.
  - **Dragten:** Tøjet farves julerødt (i efteråret gult, som en regnfrakke), så folder og skygger bevares. Hvad der er tøj, afgør en trænet model (`Parts.swift`): Google MediaPipes "Multiclass Selfie Segmentation", som for hvert punkt siger, om det er baggrund, hår, kropshud, ansigtshud, tøj eller andet (briller). Hals, ansigt, hår og hænder går derfor fri i al slags lys, også foran tøjet. Modellen kører for hvert andet kamerabillede (ca. 20 ms pr. gang) og kræver macOS 15. Den ligger i `assets/model/` (kilde og kontrolsummer i `KILDER.md` der) og er udgivet under Apache 2.0; licensen ligger i `licenses/`, følger med i appen og vises fra menuen ("Licens for tøjmodellen i kameraet…").
  - **Uden modellen** (macOS 14, og de første sekunder mens den indlæses) findes tøjet ved farve: et område vokser op fra brystet, så længe farven kun ændrer sig gradvist, halsen findes ved sin kontrast til tøjet, og et hudtonefilter målt på personens egne kinder holder hænderne fri. Det er mindre sikkert: en jakke i flere farver stopper væksten, og hud i skygge kan ligne tøj. `--nissedragt-test` gemmer også `hals.png` med halsen markeret med grønt.
  - **Målt:** appen bruger 66 % af en kerne med modellen mod 82 % med farvereglen (modellen kører på grafikkort/neural-chip, farvereglen på processoren). `HUE_INGEN_MODEL=1` slår modellen fra til sammenligning.
  - **Test uden kamera:** `--nissedragt-test=MAPPE,BILLEDE`.
- **Skiftende vejr** (menuen: Snemængde > Skiftende vejr, `SnowLevel=3`): sneen skifter selv mellem let sne, normal og snestorm i løbet af dagen. Perioderne er meget forskellige i længde: let sne 8–90 minutter, normal 6–70 og snestorm 4–25, og korte perioder er de almindeligste. Overgangene glider (en storm bygger op på 90 sekunder og klinger af over 3 minutter). Forløbet afhænger kun af datoen. `--vejr-test[=DAGE]` udskriver forløbet og fordelingen (ca. 47 % let, 44 % normal, 9 % storm); `JULE_VEJR_TID=TT:MM` starter dagens vejr på det klokkeslæt.
- **Nisser eller alfer** (menuen: Nisser eller alfer; `Folk`: 0 = automatisk, 1 = nisser, 2 = alfer, 3 = Wichtel, 4 = kabouters, 5 = päkapikud): i Norden går der nisser i bunden af skærmen, i Tyskland, Østrig, Schweiz og Liechtenstein Wichtel (høj filthue ned over øjnene, langt skæg), i Holland kabouters (stiv kegleformet hue, kort skæg, gule træsko), i Estland päkapikud (helt i rødt med hvide kanter, intet skæg) og i resten af verden julealfer (grøn eller rød kjortel, spidse ører, hue med bjælde, stribede strømper). Det automatiske valg følger Mac'ens sprog og region: først sproget, hvis det har en figur (dansk, norsk, svensk, finsk, færøsk, islandsk, grønlandsk, samisk; tysk; hollandsk; estisk), ellers regionen. Menuen viser, hvad det automatiske valg blev, og de to andre punkter er til, når det er forkert. Alle fem gør det samme som nisserne. I JuleHygge Kamera følger hue, skæg og dragt med: alfer får grøn hue med rødt takket bånd og bjælde og grøn dragt (intet skæg), Wichtel en høj grå filthue, langt skæg og mosgrøn frakke, kabouters en stiv rød kegle, kort skæg og rustfarvet jakke, og päkapikud nissens hue og dragt uden skæg. Menuens tekster er stadig danske for alle.
- **Sprog** (menuen: Sprog / Language; `Language`: tom = automatisk, ellers en sprogkode): menuen vises på Mac'ens sprog, når der er en fil til det i `assets/sprog/` (dansk, engelsk, svensk, tysk, hollandsk), ellers på engelsk. Et nyt sprog er en ny fil; se `assets/sprog/README.md`.
- **Automatisk opdatering** (menuen: "Version x.y.z", "Opdatér automatisk", "Søg efter opdatering nu"): en udgivet app henter selv nye udgivelser fra GitHub (`rkl1976/christmas`) og genstarter i den nye version. Indstillingen `AutoUpdate` er slået til som standard. En lokalt bygget app (version 0.0.0) og en app med JuleHygge Kamera opdaterer ikke sig selv; menuen siger hvorfor. Appen skal ligge i en mappe, den selv kan skrive i (`~/Applications` eller `/Applications` for en administrator). Test: `--opdatering-test=ZIP,VERSION` og `--opdatering-test=github,-` på en kopi af appen, og `JULE_UPDATE_VERSION=x.y.z`.
- **Nissehue på i kameraet** (menuen, `CameraHat`, til som standard): en nissehue på hvert hoved (højst 3), bygget på hovedets målte omrids i udskæringsmasken i hvert billede. Visions ansigtsvinkler (drej, nik, hældning) former kun huen. Størrelsen følger hovedets bredde. `perf:`-loggen viser tiden, `hue:`-loggen målingerne. Test uden kamera: `--nissehue-test=MAPPE` simulerer syv hovedformer og fire kameraopstillinger (`hue-NN.png` og tal), `--nissehue-test=MAPPE,BILLEDE` sætter huen på ansigtet i et billede. Se `docs/nissehue-overlevering.md`.
- **Fejlsøgning af kameraets hue, skæg og dragt:** start appen med `open -a /Applications/JuleHygge.app --args --kamera-debug=MAPPE`. Hvert 3. sekund gemmes det færdige billede med målepunkter (`billede-NNN.png`), kameraets rå billede (`raa-NNN.jpg`) og målingerne (`log.txt`). `build/JuleHygge.app/Contents/MacOS/JuleHygge --kamera-replay=MAPPE` kører det hele igen på de rå billeder uden kamera og skriver `ud-NNN.png` (og tøjmodellens tid pr. billede). Med `HUE_EFTERAAR=1` afspilles efterårets sydvest og regnfrakke. Uden parameteren gemmes intet. `swift tools/parts-probe.swift MODEL.mlmodelc BILLEDMAPPE UDMAPPE` viser modellens opdeling alene, med en farve pr. klasse.
- **Send julemanden/sneploven ind i kameraet** (menuen): sender figuren kun ind i kamerabilledet, så den ses bag dig i mødet. Menupunkterne virker kun, mens kameraet er i brug. Imens kører scenen med 30 billeder/s (ellers 20). Når skærmene holder pause, går julemandens automatiske ture også ind i kameraet.
- `--kamera-scene-test=MAPPE` gemmer kamerabaggrunden som PNG uden kamera (sender julemand og sneplov ind efter 1 s).

## Test

| Parameter / miljøvariabel | Effekt |
|---|---|
| `--kalender` | åbner julekalenderen ved start |
| `--julemand` | sender julemanden afsted med det samme |
| `--sneplov` / `--sneplov=N` | sender sneploven ud efter 3 / N sekunder |
| `--effekt=N` | kalendereffekt: 1 julemand, 2 snestorm, 3 nissefest, 4 stjerneregn, 5 det hele |
| `--snapshot=MAPPE[,SEK]` | gemmer overlay pr. skærm (og kalenderen) som PNG efter SEK sekunder — kræver ikke skærmoptagelsestilladelse |
| `JULE_DATE=yyyy-MM-dd` | lader som om det er en anden dato |
| `JULE_SETTINGS=sti` | brug en anden settings-fil (så tests ikke ændrer de rigtige indstillinger) |
| `JULE_DEBUG=1` | debuglinjer i fejlloggen |
| `JULE_LOG=<sti>` | fejlloggen skrives her i stedet for `~/Library/Logs/JuleHygge.log` (til test i projektet) |
| `JULE_FPS=N` | fast billedfrekvens (til målinger) |
| `JULE_DEEPSNOW=1` | starter med fuld snedrive, også på vinduerne (til test af sneploven og af nedfald) |
| `JULE_NO_RAIN=1` | efterår: ingen regn i stormen (til måling) |
| `HUE_FOLK=1…5` | kameratestene klæder personen som det folk (1 nisser, 2 alfer, 3 Wichtel, 4 kabouters, 5 päkapikud) |
| `HUE_EFTERAAR=1` | kameratestene (`--kamera-replay`, `--nissehue-test`) bruger efterårets sydvest og regnfrakke |
| `HUE_INGEN_MODEL=1` | kameraet finder tøjet ved farve i stedet for med modellen (til sammenligning) |
| `JULE_TICKS=1` | skriver faktiske billeder/s til stderr |
| `--skærmskift-test` | genopbygger overlay-vinduerne hvert 0,3 s (stresstest af skærmskift) |
| `--lyd-test=MAPPE` | gemmer de syntetiserede lyde som WAV-filer (så man kan lytte til dem) og afslutter |
| `--sprog-test` | udskriver menuens sprog, det automatiske valg og hvad hvert sprog mangler, og afslutter |
| `JULE_MENU_DUMP=fil` | skriver menuen som tekst, som den ville åbne (til kontrol af et sprog; brug sammen med `JULE_LOCALE` og `--snapshot`) |
| `--folk-test` | udskriver, om denne Macs sprog og region giver nisser eller alfer (og reglen for en række lande), og afslutter |
| `JULE_LOCALE=en_US` | lader som om, Mac'en har det sprog og den region (til test af nisser/alfer) |
| `JULE_NISSE_SECONDS=N` | nisser kommer/går hvert N. sekund, og antal/snemængde skrives til stderr |
| `--register-login` / `--unregister-login` | slår start ved login til/fra og afslutter |
| `JULE_NO_SUPERVISOR=1` | kør uden vagtproces (testparametrene som `--julemand` slår den også fra) |

Eksempel (kør binæren direkte for at kunne sætte miljøvariabler):

```bash
JULE_SETTINGS=$PWD/build/test.ini JULE_DATE=2026-12-13 build/JuleHygge.app/Contents/MacOS/JuleHygge --kalender --julemand --snapshot=$PWD/build/shots,4
```

## Kode

| Fil | Indhold |
|-----|---------|
| `Sources/JuleHygge/main.swift` | Opstart, én instans, kommandolinje |
| `Sources/JuleHygge/Controller.swift` | Menulinje-menu, hovedløkke, julemanden, effekter, daglige notifikationer, strøm, fuldskærm, autostart |
| `Sources/JuleHygge/Overlay.swift` | Ét klik-igennem vindue pr. skærm: sne, sneplov, nisser, julelys, snemand |
| `Sources/JuleHygge/Calendar.swift` | Julekalender-vinduet og indholdet bag lågerne |
| `Sources/JuleHygge/Settings.swift` | Indlæsning og gemning af indstillinger |
| `Sources/JuleHygge/Sound.swift` | Lydsyntese (jingle, sneplov, løvsuger), gåseoptagelsen og delt lydmotor |
| `Sources/JuleHygge/Theme.swift` | Temaet (jul eller efterår) og hvad der skifter med det |
| `Sources/JuleHygge/Parts.swift` | Tøjmodellen i kameraet: tøj, hud og hår hver for sig |
| `Sources/JuleHygge/Licenses.swift` | Vinduet med tøjmodellens licens |
| `tools/parts-probe.swift`, `tools/sound-probe.swift`, `tools/goose-synth.swift`, `tools/window-probe.swift` | Måleværktøjer: tøjmodellen på billeder, en lyds tonehøjde og spektrum, en prøve på syntetiske gæs (ikke valgt), vinduernes størrelse under minimering |
| `Sources/JuleHygge/Icon.swift` | Snefnug-ikonet (menulinje og app-ikon, tegnes i koden) |
| `install.sh` / `measure.sh` | installation med start ved login / CPU-måling af app og WindowServer |
| `Sources/JuleHygge/Util.swift` | Dato, log, dataklasser og GDI+-agtige tegnehjælpere |

### Strømforbrug
Det dyre er ikke appens egen CPU, men at **WindowServer** skal sammensætte overlayet på ny ved hver ændring. Målt med `./measure.sh` (MacBook + 2560×1440-skærm, WindowServer ~12 % uden appen):

| | App | WindowServer ekstra | I alt |
|---|---|---|---|
| Første version (30 fps med Timer, alt gentegnet) | 27 % | ~21 % | ~48 % |
| Billedfrekvens 12 (også strømspare) | ~5 % | ~4 % | **~9 %** |
| Billedfrekvens 20 (standard) | ~8 % | ~10 % | **~18 %** |
| Billedfrekvens 30 | ~11 % | ~22 % | **~33 %** |
| Billedfrekvens 60 | ~19 % | ~36 % | **~55 %** |
| Mens julemanden flyver (60 fps, ~10-20 s ad gangen) | ~20 % | ~40 % | ~60 % |
| Mens sneploven kører, inkl. sne der sprøjter op (30 fps, ~25 s over to skærme) | ~15 % | ~14 % | ~29 % |

Billedfrekvensen for den rolige scene vælges i menuen **Billedfrekvens** (gemmes som `FrameRate`). Strømspare bruger højst 12. Separate frekvenser pr. element ville ikke spare noget: enhver ændring får WindowServer til at sammensætte overlayet, så det er det samlede antal opdateringer pr. sekund, der koster.

Valg der holder det nede:
- **Én fælles display link** (`NSScreen.displayLink`) og én `CATransaction` pr. frame. Den følger skærmens opdatering, så billederne kommer med helt jævne mellemrum (ved 20 fps på 120 Hz præcis hver 6. opdatering). En almindelig `Timer` driver i forhold til skærmen og får sneen til at hakke. Lav frekvens når scenen er rolig (20 fps / 12 fps i strømspare), 60 fps (30 i strømspare) kun mens julemanden flyver, og 30 fps (20) mens den langsomme sneplov kører.
- **Ingen Core Animation-animationer** (`CABasicAnimation` m.fl.): de kører altid med skærmens fulde frekvens (op til 120 Hz) og fik WindowServer op over 50 %. `preferredFrameRateRange` hjalp ikke.
- **Nisser** tegnes ikke pr. frame: hver positur (16 gangbilleder, 8 stå, 8 vinke) tegnes én gang pr. tøjvariant og genbruges; størrelse og retning er GPU-skalering.
- **Julelys**: ledning og slukkede pærer tegnes én gang; hver pæres lyse udgave er et færdigt billede, hvis gennemsigtighed ændres ~7 gange/s.
- Julemand og sneplov flyttes hver frame, men gentegnes kun hver anden. Snedriven opdateres 5 gange/s.
- Timeren stopper helt, når skærmen sover, pauseskærmen kører, eller skærmen er låst. Er julemanden eller sneploven undervejs, afsluttes turen med det samme, som om de var nået frem (ellers blev de hængende "på vej", og melodien kørte videre i ring). Det samme sker, hvis der af anden grund ikke er kommet billeder i over 2 sekunder. Test med `swift tools/pauseskaerm-signal.swift start|stop`.

### Tegning
Hver figur (julemanden, nisser, snemand, sneplov, julelys) er et lille `CALayer`, der kun gentegnes i sin egen størrelse. Snefnug, gnister og sneklumper er genbrugte billedlag, som kun flyttes. Sneploven køres af `Controller` i globale koordinater, så den kører én sammenhængende tur hen over skærme, der står ved siden af hinanden (ligesom julemanden). Snedriven er et `CAShapeLayer`. Al sammensætning sker på GPU'en, så der er ingen dirty-rect-håndtering som i Windows-versionen. Tegnekoden bruger skærmkoordinater med origo øverst til venstre, så den kan sammenlignes linje for linje med `src/Layer.cs`.
