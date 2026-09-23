# STATE.md — Faver

> Läs den här filen direkt efter CLAUDE.md varje session.

---

## Senast uppdaterad

2026-09-23 — Hela listan avbetad. Burst-set och videor finns nu på riktigt.

**Nuvarande fokus:** iOS 27, som väntar på att Xcode 27 blir installerat. Kräver
administratörslösenord: `sudo mas upgrade 497799835`.

**Klart sedan sist.** Videor spelas upp i stället för att visas som en frusen ruta.
Burst-set byggda: bilder tagna inom tre sekunder håller en position och sveps lodrätt.
Skärmdumpar ligger inte längre i kön. Misslyckade favoritmarkeringar rapporteras i
stället för att låtsas ha gått igenom. "Börja om" i Inställningar är den första
ångermöjligheten som funnits. Appen märker nya bilder när den kommer tillbaka i
förgrunden. Begränsad fotoåtkomst syns och går att vidga. Startsidan lägger ut sig
själv i stället för att räkna 254 punkter för hand.

**Dessförinnan:** två fel som bröt mot appens löften (framsteg sparades aldrig under
ett pass, favoritmarkering gömde osedda bilder), Liquid Glass på riktigt, tillgänglighet
upp till AA, och klustringen bort från huvudtråden.

---

## TestFlight

`./scripts/testflight.sh` bygger och skickar. Till skillnad från Ullared, som byggs i
Expos moln, byggs Faver här på maskinen. Det är ett vanligt Xcode-projekt, så vägen går
rakt till Apple utan mellanhänder. Tar ett par minuter. Interna testare slipper
granskning. `./scripts/status.sh` visar var byggena ligger.

Byggnumret hämtas från Apple och räknas upp automatiskt. Versionen (MARKETING_VERSION)
sätts i Xcode.

**Apple.** App-id 6814968962, bundle `com.jezper.Faver`, team Lorne Holding AB
(SUPDJZHQDA). Interna gruppen heter Team och får alla byggen automatiskt:
jezper.lorne@gmail.com och jezper@jezper.se.

Signeringen ligger i nyckelknippan `faver-signing`, utanför repot, tillsammans med
`~/.apple-signing/`. Certifikatet går ut **2027-09-22** och måste förnyas då.
API-nyckeln till Apple delas med Ullared och ligger i `~/.appstore-api`.

---

## Beslut

**Bygget sker lokalt, inte i molnet.** Ullared går via Expo för att det är cross
platform. Faver är bara iOS och har inga beroenden, så ett moln hade bara lagt en
halvtimme och en tredje part i vägen.

**Certifikat och profil skapades via Apples API**, inte i Xcodes gränssnitt. Maskinen
står utan skärm, och då finns inget gränssnitt att klicka i.

**Byggnumret bor hos Apple, inte i projektfilen.** En siffra i projektfilen glöms bort,
och Apple vägrar ta emot ett byggnummer som redan finns.

**Vanligt glas, inte klart.** Apple föreslår klart glas för kontroller ovanpå foton, men
villkoret är att det som ligger bakom är ljust och tydligt. Faver kan inte lova det:
innehållet är vad som råkar ligga i någons kamerarulle.

**Att lämna en stund bekräftas inte längre.** Det tog bort möjligheten att markera
återstoden som sedd i förtid. Kommer den saknas blir det en egen funktion, inte en
dialogruta tillbaka.

**iOS 26.2 behålls** som krav. Beslut 2026-09-22.

---

## Kvar att göra

- **iOS 27.** Lagerbyggd appikon i Icon Composer, `toolbarMinimizeBehavior` på
  bläddringsvyn, och migrering från `ObservableObject` till `@Observable`. Allt väntar
  på Xcode 27.
- **`AppIconExporter`** i `AppIconView.swift` är död kod som pekar på en katalog som
  inte finns. Tas bort när ikonen görs om.
- **`GeocodingCache` använder `placemark`**, som är utfasad i iOS 26.
- **Ingen ångra per bild.** "Börja om" nollställer allt; det finns inget sätt att ta
  tillbaka en enskild bild eller en enskild stund.

## Att veta

- Appen kräver iOS 26.2 eller senare. Beslut 2026-09-22, oförändrat.
- Neo står på macOS 27. Xcode är kvar på 26.6 tills `sudo mas upgrade 497799835` körts
  av en människa; `mas` kan inte mata in administratörslösenordet.
- Projektet använder synkroniserade grupper (objectVersion 77), så nya .swift-filer
  plockas upp automatiskt. Ingen redigering av projektfilen behövs.
