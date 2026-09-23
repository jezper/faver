# STATE.md — Faver

> Läs den här filen direkt efter CLAUDE.md varje session.

---

## Senast uppdaterad

2026-09-23 — Tester finns nu. Fem rättningar väntar oskickade.

**Nuvarande fokus:** oskickade rättningar, se nedan. Inget nytt byggs förrän de är ute.

**Tester.** `./scripts/test.sh` kör 46 snabba tester på sekunder och körs automatiskt
före varje TestFlight-bygge, som vägrar gå vidare om de faller. De täcker reglerna för
gruppering, burst-set, vilka stunder som ska visas, och genomgångsstatus — alltså precis
de ställen där misstag kostat riktigt arbete.

`./scripts/uitest.sh` kör gränssnittstesterna mot ett riktigt fotobibliotek i
simulatorn. **De passerar inte ännu**, och testerna är inte orsaken: simulatorn vägrar
ge appen fotobehörighet, så den fastnar på välkomstskärmen. Se filhuvudet i
`FaverUITests/ReviewFlowUITests.swift`.

**Oskickat, klart och byggt lokalt:**

1. Pinch-zoomen skrev om positionen vid varje steg och tog ankaret från fingrarna.
2. Den skarpa bilden nollställde scrollvyn mitt i ett svep.
3. `PHImageManagerMaximumSize` packades upp på huvudtråden vid bytet.
4. Kort identifierades med sin plats i raden, så en avklarad stunds bilder ärvdes av
   nästa. Det var buggen där en genomgången stund såg ut att ligga kvar.
5. Videor spelades utan ljud, eftersom appen saknade egen ljudsession.

Plus förhämtning av kommande bilder i granskningsvyn.

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

- **Gränssnittstesterna går inte att köra grönt.** Simulatorns fotobehörighet biter inte.
  Troligen rätt väg: ge appen ett testläge med ett påhittat bibliotek i stället för att
  slåss med simulatorn, vilket också gör dem snabba.
- **iOS 27.** Lagerbyggd appikon i Icon Composer, `toolbarMinimizeBehavior`, och
  migrering till `@Observable`. Väntar på att Xcode 27 installeras, vilket kräver
  `sudo mas upgrade 497799835` körd av en människa i en riktig terminal.
- **`AppIconExporter`** i `AppIconView.swift` är död kod som pekar på en katalog som
  inte finns.
- **`GeocodingCache` använder `placemark`**, utfasat i iOS 26.

## Att veta

- Appen kräver iOS 26.2 eller senare. Beslut 2026-09-22, oförändrat.
- Neo står på macOS 27. Xcode är kvar på 26.6 tills `sudo mas upgrade 497799835` körts
  av en människa; `mas` kan inte mata in administratörslösenordet.
- Projektet använder synkroniserade grupper (objectVersion 77), så nya .swift-filer
  plockas upp automatiskt. Ingen redigering av projektfilen behövs.
