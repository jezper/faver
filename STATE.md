# STATE.md — Faver

> Läs den här filen direkt efter CLAUDE.md varje session.

---

## Senast uppdaterad

2026-09-22 — Första bygget ligger i TestFlight.

**Nuvarande fokus:** uppgradering till iOS 27 och dess designsystem, och en
genomgång av appens viktiga flöden så den känns modern.

**TestFlight.** `./scripts/testflight.sh` bygger och skickar. Till skillnad från
Ullared, som byggs i Expos moln, byggs Faver här på maskinen. Det är ett vanligt
Xcode-projekt, så vägen går rakt till Apple utan mellanhänder. Tar ett par
minuter. Interna testare slipper granskning.

Byggnumret hämtas från Apple och räknas upp automatiskt. Versionen
(MARKETING_VERSION) sätts i Xcode.

**Apple.** App-id 6814968962, bundle `com.jezper.Faver`, team Lorne Holding AB
(SUPDJZHQDA). Interna gruppen heter Team och får alla byggen automatiskt:
jezper.lorne@gmail.com och jezper@jezper.se.

Signeringen ligger i nyckelknippan `faver-signing`, utanför repot, tillsammans
med `~/.apple-signing/`. Certifikatet går ut **2027-09-22** och måste förnyas då.
API-nyckeln till Apple delas med Ullared och ligger i `~/.appstore-api`.

---

## Beslut

**Bygget sker lokalt, inte i molnet.** Ullared går via Expo för att det är
cross platform. Faver är bara iOS och har inga beroenden, så ett moln hade bara
lagt en halvtimme och en tredje part i vägen.

**Certifikat och profil skapades via Apples API**, inte i Xcodes gränssnitt.
Maskinen står utan skärm, och då finns inget gränssnitt att klicka i.

**Byggnumret bor hos Apple, inte i projektfilen.** En siffra i projektfilen
glöms bort, och Apple vägrar ta emot ett byggnummer som redan finns.

---

## Att veta

- Appen kräver iOS 26.2 eller senare. Höjs vid uppgraderingen till 27.
- Xcode 27 kräver macOS 26.6. Neo står på 26.5 och måste uppdateras först,
  vilket kräver omstart.
