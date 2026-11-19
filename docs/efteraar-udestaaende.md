# Efterårstemaet: udestående

Status pr. 2026-11-19. Temaet er bygget på macOS, element for element (se `docs/temaer/index.html` for idéen).

## Mangler i temaet

- **Lyd: regn og vind.** Regnen er lydløs. De eneste efterårslyde er gæssene (optagelsen `assets/lyd/gaes-flok.wav`)
  og løvsugeren. En regnstemning til gæssene blev afprøvet og fravalgt ("den fungerer ikke"); lyd til selve regnen
  er ikke forsøgt.
- **Vinduer: et egern, der gemmer nødder.** Bladene samler sig på vinduerne, men der er intet egern dér.
- **Kamera: noget i skæggets sted.** Sydvest og regnfrakke er lavet. To forsøg er lagt væk:
  - Halstørklæde: koden ligger i `macos/Sources/JuleHygge/Scarf.swift` (og halsmålingen i `Parts.swift`), men intet
    kalder den. REL prøvede det på optagne billeder: "virker ikke for mig".
  - Røde kinder og næse: afprøvet og droppet samme dag, koden er fjernet. (Pletterne kom ikke frem i første forsøg;
    årsagen blev ikke fundet.)
- **Sydvesten, når hovedet er lænet tilbage og drejet.** Den tegnes set nedefra og ligner en ring om hovedet. REL har
  besluttet at lade det ligge. En mulig vej er noteret: tegn aldrig hatten nedefra.

## Bevidst udeladt

- **Kalender og nedtælling.** Skjult i efteråret; kalenderen med låger hører julen til.

## Uden for selve temaet

- **Windows.** Efterårstemaet findes kun i macOS-udgaven. To ting er dog lavet i `src/`: nedfaldet fra vinduer deler
  nu pladsen jævnt (`WindowSnow.cs`), og julemandens størrelse varierer uafhængigt af farten (`Controller.cs`).
  Ingen af dem er kompileret eller afprøvet på Windows.
- **Gåsene som syntetisk lyd.** Undersøgt 2026-11-19 med optagelsen som forlæg (`macos/tools/sound-probe.swift` måler,
  `macos/tools/goose-synth.swift` laver en prøve, der matcher optagelsens tonehøjde, overtoner og spektrum). REL
  valgte at beholde optagelsen og ændre reglen i `AGENTS.md` i stedet.
- **Tøjmodellen** er en tredjeparts omsætning af Googles model til Core ML. Den kan erstattes af en, vi selv omsætter
  fra originalen (se `assets/model/KILDER.md`).
- **Hattens måling med tøjmodellen.** Vurderet, ikke lavet: modellens klasser kan skære hætte og krave fra hovedets
  omrids og give kæbelinjen i drejede stillinger. De bør ikke bruges til isse og bredde (for grove, og gråt hår findes
  kun delvist).
