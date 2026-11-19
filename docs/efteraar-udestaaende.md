# Efterårstemaet: udestående

Status pr. 2026-11-19. Temaet er bygget på macOS, element for element (se `docs/temaer/index.html` for idéen).

## Mangler i temaet

- **Lyd: regn og vind.** Regnen er lydløs. De eneste efterårslyde er gæssene (optagelsen `assets/lyd/gaes-flok.wav`)
  og løvsugeren. En regnstemning til gæssene blev afprøvet og fravalgt ("den fungerer ikke"); lyd til selve regnen
  er ikke forsøgt.
- **Vinduer: et egern, der gemmer nødder.** Bladene samler sig på vinduerne, men der er intet egern dér.
- **Kamera: noget i skæggets sted.** Sydvest og regnfrakke er lavet. To forsøg er lagt væk:
  - Halstørklæde: lagt væk og ikke med i `main`. Koden (`Scarf.swift` og en halsmåling i `Parts.swift`, bygget på
    tøjmodellens hud-klasser) findes i historikken, commit `5c16027`. REL prøvede det på optagne billeder: "virker
    ikke for mig".
  - Røde kinder og næse: afprøvet og droppet samme dag, koden er fjernet. (Pletterne kom ikke frem i første forsøg;
    årsagen blev ikke fundet.)
- **Sydvesten, når hovedet er lænet tilbage og drejet.** Den tegnes set nedefra og ligner en ring om hovedet. REL har
  besluttet at lade det ligge. En mulig vej er noteret: tegn aldrig hatten nedefra.

## Bevidst udeladt

- **Kalender og nedtælling.** Skjult i efteråret; kalenderen med låger hører julen til.

## Uden for selve temaet

- **Windows.** Temaet er skrevet til Windows 2026-11-19 (`src/LayerAutumn.cs`, `src/Layer.cs`, `src/Controller.cs`):
  menuen "Tema" med skiftende tekster, løvfald og løvbunker, høstak med fugleskræmsel, gæs, løvsuger, pindsvin og
  egern, løvranke med lygter, drage og regn. Det kompilerer (mono på Mac'en, C# 5), men er **aldrig set køre**, og
  CPU-forbruget er ikke målt. Lydene er med: gæssenes to stemninger (optagelsen bygges ind i exe-filen af
  `build.ps1`, ca. 2 MB) og løvsugerens sug; de er ikke hørt på Windows. Kameraet findes ikke på Windows.
- **Linux.** Har efterårstemaet uden kameraet (2026-11-19): skrevet af efter Windows-koden uden Rust på Mac'en og
  kun bygget og set som stillbilleder i CI (`screen0-efteraar.png`). Ikke set køre, ikke hørt, CPU ikke målt, og
  bladene på vinduerne er aldrig tegnet (ingen vinduer under Xvfb). Nedfaldsrettelsen i `linux/src/window_snow.rs`
  har en test.
- **Gåsene som syntetisk lyd.** Undersøgt 2026-11-19 med optagelsen som forlæg (`macos/tools/sound-probe.swift` måler,
  `macos/tools/goose-synth.swift` laver en prøve, der matcher optagelsens tonehøjde, overtoner og spektrum). REL
  valgte at beholde optagelsen og ændre reglen i `AGENTS.md` i stedet.
- **Tøjmodellen** er en tredjeparts omsætning af Googles model til Core ML. Den kan erstattes af en, vi selv omsætter
  fra originalen (se `assets/model/KILDER.md`).
- **Hattens måling med tøjmodellen.** Vurderet, ikke lavet: modellens klasser kan skære hætte og krave fra hovedets
  omrids og give kæbelinjen i drejede stillinger. De bør ikke bruges til isse og bredde (for grove, og gråt hår findes
  kun delvist).
