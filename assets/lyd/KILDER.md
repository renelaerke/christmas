# Lydoptagelser

Projektets to lydoptagelser. Alt andet lyd syntetiseres i koden.

| Fil | Titel | Side | Format |
|---|---|---|---|
| `gaes-flok.wav` | Geese Honking | https://soundbible.com/235-Geese-Honking.html | 15,8 s, stereo, 32 kHz |
| `hannerl-polka.wav` | Hannerl Polka (uddrag) | https://commons.wikimedia.org/wiki/File:Hannerl_Polka.ogg | 63,3 s, mono, 32 kHz |

## Gæssene

Hentet 2026-11-18 fra SoundBible, hvor den er mærket "Public Domain" og krediteret fws.gov
(U.S. Fish & Wildlife Service). Mærkningen er SoundBibles; originalen er ikke fundet på fws.gov.

Bruges af efterårstemaets trækgæs (`Synth.geese` i `macos/Sources/JuleHygge/Sound.swift`): alene, og dæmpet
med syntetiseret blæst under. `macos/build.sh` og Xcode-projektet kopierer filen ind i appens
Resources.

## Hannerl Polka

Hentet 2026-11-25 fra Wikimedia Commons (`Hannerl_Polka.ogg`, 2 min 36 s). Komponist: Hans Kummerer
(Weinviertel, Østrig). Spillet af Blaskapelle Franz Stremnitzer, fra cd'en "30 Jahre Blasmusik Franz
Stremnitzer". Lagt op af Franz Stremnitzer under **Creative Commons Attribution 3.0 Unported**
(https://creativecommons.org/licenses/by/3.0/). Licensen kræver kreditering, et link til licensen og at det
siges, hvad der er ændret: det står i appen under menupunktet "Licenser…" (`Licenses.swift`) og her.

**Forbehold:** licensen er givet af orkestrets leder, som har lagt optagelsen op. Commons-siden siger ikke,
at komponisten (Hans Kummerer) selv har givet lov; det er ikke undersøgt nærmere.

Ændret: uddraget er de første 128 slag (63,3 s), mikset til mono i 32 kHz, med få millisekunders ind- og
udtoning, så det kan spilles i ring. Lavet sådan (originalen ligger ikke i git):

    afconvert -f WAVE -d LEI16@32000 -c 1 Hannerl_Polka.ogg hannerl32.wav
    python3 tools/takt.py hannerl32.wav 122 > hannerl.takt
    python3 tools/klip.py hannerl32.wav hannerl.takt 128 assets/lyd/hannerl-polka.wav assets/lyd/hannerl-polka.takt

`hannerl-polka.takt` er tidspunktet for hvert slag i uddraget (sidste linje er uddragets længde). Bruges af
Rhinlandets karnevalsvogn (`Synth.rheinBand`, `Synth.rheinBeats`): orkestret holder 121–122 slag i minuttet,
ikke præcis, så figurerne går efter de målte slag og ikke efter et ur (`Controller.advanceBeat`). Valgt, fordi
fire syntetiserede marcher aldrig kom til at lyde som messingblæsere (REL 2026-11-25), og fordi den er et lille
landsbyorkester og ikke et stort militærorkester. Den er østrigsk, ikke rhinsk: karnevalssange fra Köln er
ophavsretligt beskyttede.
