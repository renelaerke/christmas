# Nisser eller alfer: udestående

Status pr. 2026-11-20, i worktree `christmas-alfer` (gren `alfer`, fra `main` `57003d3`). Alle tre udgaver har
reglen efter sprog og region, indstillingen `Folk`, menuen "Nisser eller alfer", de fire andre folk som figurer (alf, Wichtel, kabouter, päkapikk) og alfetekster i
de menupunkter og den notifikation, der nævner nisser.

| Udgave | Hvad der er kontrolleret |
|---|---|
| macOS | Bygget. Alle fem folk set på `--snapshot`-billeder; reglen kørt med `--folk-test`. Menuen og skiftet mens appen kører er ikke set af mig. |
| Windows | Kompilerer som C# 5 med mono. `--folk-test` kørt med mono på Mac'en. Figurerne og menuen er **aldrig set**; CPU ikke målt (figurerne tegnes i hvert billede ligesom nissen, alfen med lidt flere former). |
| Linux | **Aldrig kompileret** (ingen Rust på Mac'en). CI bygger, kører testene i `folk.rs`, `--folk-test` og gemmer et billede af hvert folk, når grenen kommer på GitHub. |

## Afgørelser, REL bør se på

- **Hvem får hvad** (tabellerne `byLanguage`/`byRegion`, ens i de tre udgaver). Sproget først: nordisk giver
  nisser, tysk Wichtel, hollandsk kabouters, estisk päkapikud. Ellers regionen: Norden; DE, AT, CH, LI; NL; EE.
  Alle andre får alfer. Schweiz får Wichtel også på en fransk- eller italiensksproget maskine, og Belgien får kun
  kabouters, når sproget er hollandsk.
- **De fire nye figurers udseende.** Mine bud. Alfen, Wichtel, kabouter og päkapikk er set på macOS-billeder
  (`build-test/alfer/`), ikke af REL endnu undtagen alfen.
- **Kabouteren** er med vilje ikke den kendte bogfigur: jakke i grøn, okker, rust eller blågrå og gule træsko.
- **Ordene i menuen:** "Alfer", "Wichtel (tyske nisser)", "Kabouters (hollandske nisser)", "Päkapikud (estiske
  nisser)". Menupunkterne "Nisser" og "Antal nisser pr. skærm" hedder kun noget andet for alferne.

## Mangler

- **Windows og Linux skal ses køre** (se tabellen). På Windows er regionen landet i det regionale format, ikke
  "Land eller område"; på Linux er den `LC_TIME`/`LC_MONETARY` (skrivebordets "Formater") eller `LANG`.
- **Julekalenderens tekster** nævner nisser (låge 1, 11, 18, 21 og teksten før 1. december). Låge 11 handler om
  nissen på gården og giver kun mening for nisser.
- **Kameraet** (macOS) følger nu folket: hue, skæg og dragt pr. folk (`CameraLook`). Set på genafspillede
  kamerabilleder (`--kamera-replay` med `HUE_FOLK`), og installeret og prøvet live af REL 2026-11-20 ("works as
  expected"). Mangler: spidse ører til
  alfen (intet måler ørerne), og `--nissehue-test` (simuleringen) er ikke kørt for de nye former.
- **README.md** (forsiden) nævner kun nisser.
- **Sproget.** Al tekst er dansk, også for dem, der får alfer. En oversættelse er en opgave for sig.
