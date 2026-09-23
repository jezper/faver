# STATE.md — Faver

> Läs den här filen direkt efter CLAUDE.md varje session.

---

## Senast uppdaterad

2026-09-23 — Två fel lagade, Liquid Glass på plats, tillgänglighet och snabbhet.

**Nuvarande fokus:** inget pågående. Nästa naturliga steg står under Kvar att göra.

**Vad som gjordes.** Genomgången 2026-09-22 hittade två fel som bröt mot appens egna
löften, och båda är lagade:

1. Framstegen sparades bara när man nådde slutsidan, så ett avbrutet pass gav noll.
   Varje bild bokförs nu när den är den som visas, vilket gör att man landar exakt
   på bilden man slutade vid. Det gjorde också bekräftelserutan vid avslut onödig,
   och den är borta tillsammans med dragreglaget som skärmläsare inte kunde använda.
2. Att favoritmarkera en bild gömde hela stunden, inklusive osedda bilder. En stund
   hoppas nu bara över om den var städad innan Faver någonsin såg den.

**Liquid Glass finns nu på riktigt.** Appen låg på `.ultraThinMaterial` trots att
dokumentationen påstod annat. Granskningsskärmen, kartnålarna och navigeringsraderna
använder systemets glas. Kartan är vanlig karta i stället för satellit.

**Tillgänglighet:** skalbara textstorlekar, kontrast över AA, skärmläsaretiketter på
allt man trycker på, respekt för reducerad rörelse, 44 punkters träffytor.

**Snabbhet:** klustringen är av huvudtråden, granskningsskärmen väntar aldrig på
iCloud, startsidans kort laddas först när de syns, och de hårdkodade 350 ms av
död tid efter en tryckning är borta.

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

- **Ångra finns inte.** `ReviewStore` kan inte avmarkera, och Inställningar har ingen
  nollställning. En felaktig markering går inte tillbaka.
- **Misslyckade favoriter syns inte.** `LibraryService.favorite` struntar i resultatet,
  så hjärtat fylls även om skrivningen inte gick igenom.
- **Appen blir gammal medan den ligger öppen.** Ingen `PHPhotoLibraryChangeObserver` och
  ingen `scenePhase`-hantering, så nya bilder syns först efter omstart.
- **Begränsad fotoåtkomst behandlas som full.** Inget sätt att välja fler bilder, och
  löftet om ett komplett varv gäller i tysthet bara en handfull bilder.
- **Videor visas som frusna stillbilder** utan spelknapp. Man kan inte bedöma en video
  på en bildruta.
- **Skärmdumpar och kvitton ligger i kön.** Ingen filtrering på mediatyp.
- **Burst-set finns inte** trots att de står i designen.
- **Startsidans layout räknar punkter för hand** (254 pt reserverat) i stället för att
  låta stacken göra jobbet. Går sönder vid stora textstorlekar.
- **Liggande läge är påslaget men inte designat för.**

---

## Att veta

- Appen kräver iOS 26.2 eller senare.
- Xcode 27 kräver macOS 26.6. Neo står på 26.5. Omstarten är **uppskjuten** tills Jezper
  har tid att sitta bredvid. Nästan inget designarbete väntade på den: Liquid Glass fanns
  redan i iOS 26. Det som faktiskt kräver iOS 27 är den lagerbyggda appikonen
  (Icon Composer) och `toolbarMinimizeBehavior`.
- `AppIconExporter` i `AppIconView.swift` är död kod som pekar på en katalog som inte
  finns. Tas bort när ikonen görs om i Icon Composer.
