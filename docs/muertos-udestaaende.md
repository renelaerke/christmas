# De dødes dag: udestående

Status pr. 2026-11-19. Temaet er påbegyndt på macOS på grenen `muertos` (idéen står i `docs/temaer/index.html`).

## Lavet

Kronblade og tagetes-tæppe (bund og vinduer), ofrenda over 12 dage, monarksommerfugle, calacas, papel picado,
menutekster og beskeden, når alteret vokser. Set på `--snapshot`-billeder (fuldt tæppe, færdigt alter og trin 5).

Lavet samme dag, anden runde:
- **Lys på vindueskanterne**, med flakkende flamme og glød. Lysene falder ikke ned, når vinduet minimeres
  (REL: "måske behøver lysene ikke falde ned"); kronbladene falder som sneen, og lysene forsvinder med vinduet.
- **Æselkærre i sneplovens sted**, så kronbladene ikke bare hober sig op. Set på billeder.
- **Melodi til sommerfuglene**: en original vals i d-mol (16 takter, ca. 18 s) med marimba og guitar. Målt
  (tonehøjde og styrke pr. takt), men **ikke lyttet til**.

Lavet 2026-11-24:
- **Lyd til æselkærren:** hovtramp (fire hove pr. skridt, i takt med tegningens ben: skridtet regnes ud af
  benenes svingning og hjulets fart, 0,59 s), et knirk for hver omgang hjulet tager (løkken er 8 skridt = præcis
  5 omgange), kostens sus på hvert fremadstrøg og et "i-a, i-a" i hornets sted. Lydpunktet hedder "Lyd: hovtramp,
  hjulknirk og æselbrøl fra æselkærren" og er slået fra som standard. Målt (styrke pr. 10 ms: et hovslag er ca. 17
  gange lydstyrken mellem slagene, knirket står 2–3 gange over baggrunden, brølet er lige så kraftigt som hornet),
  og en kørsel med lyden slået til gik uden fejl. **Ikke lyttet til**; om æselbrølet lyder som et æsel, kan kun
  øret afgøre (en syntetisk gås lød for kunstig, se `assets/lyd/KILDER.md`). Lyden følger ikke benenes fase, kun deres tempo.

Lavet 2026-11-24, kameraet (`CameraCostume.muertos`):
- **Blomsterkrans** i hattens sted (`NisseHat.flowerCrown`): 14 tagetes rundt om hovedet med en lilla eller lyserød
  blomst imellem og blade i hullerne, på samme målte ring som nissehuens pels, lidt højere (blomsternes underkant
  holder sig over øjenbrynene). Den bagerste halvdel ses kun ved siden af hovedet, som pelsen.
- **Calavera-sminke** i skæggets sted (`Makeup.swift`, menupunktet "Calavera-sminke på ansigtet i kameraet"): hvid
  bund, der beholder ansigtets lys og skygge, sorte øjenhuler (blomsterformede, fra kindbenet op til brynet) med en
  ring af farvede kronblade og øjnene selv fri, et sort hjerte på næsen, mørke læber med sting over, en lille blomst
  og prikker på panden, hjerter på kinderne og prikker på hagen. Alt er placeret ud fra Visions landemærker (øjne,
  bryn, næse, læber, kæbe) i hvert billede, også øjne og bryn, som nu glattes sammen med resten.
  Over øjnene holder tøjmodellens "ansigtshud" den hvide bund fra håret; under øjnene bestemmer kæbelinjen alene,
  for modellen kalder skægstubbe hår, og den hvide stoppede så under næsen (set på genafspilning).
- Ingen dragt i temaet.
- Set på 56 genafspillede kamerabilleder fra to steder (tog og stue; `HUE_MUERTOS=1 --kamera-replay`), forfra og
  drejet. Sminken tager i genafspilningen 25,6 ms pr. billede i median, tøjmodellen (ca. 20 ms) og gengivelsen af
  hele billedet medregnet; live kører modellen hvert andet billede, som for dragten.

Flettet sammen med main 2026-11-24 (folkene, menuen på flere sprog): calacas går i nissernes sted uanset folk,
og valget "Nisser eller alfer" er skjult i temaet, som i efteråret. Kameraets hue, skæg og dragt pr. folk gælder
kun julen; temaet har sin krans og sminke. Temaets menutekster står i alle sprogfilerne, og italiensk (`it.ini`) og
spansk (`es.ini`) er kommet til med hele menuen (REL). Tjekket med `JULE_MENU_DUMP` på dansk, spansk og italiensk.
Oversættelserne er mine og ikke læst af nogen, der har sproget som modersmål.

## Mangler i temaet

Status 2026-11-24 (REL): kameraet virker live, animationerne er i orden, og strømmåling springes over.

- **Ofrendaens datoer, udskudt:** alteret skal bygges op til 2. november i stedet for over 12 dage fra første
  start. Det er skrevet og testet, men taget ud igen her, fordi snemandens 12-dages-opbygning allerede er ændret
  på main; koden og testresultatet ligger i `docs/muertos-ofrenda-datoer.swift.txt` og lægges ind oven på main's
  udgave efter sammenfletningen.

## Uden for selve temaet

- **Windows og Linux** har ikke temaet (udskudt af REL 2026-11-24).
