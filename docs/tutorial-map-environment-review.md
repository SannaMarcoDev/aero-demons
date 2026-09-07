# Tutorial map — analisi ambientale e ripresa lavori

## Stato e obiettivo

Richiesta: osservare la tutorial map da diverse angolazioni, anche sopra le nuvole, e individuare le migliorie ambientali necessarie per avvicinarla a una mappa finita di qualità AAA.

È stato creato e provato `tools/tutorial_survey.gd`. Dopo la review iniziale sono state abilitate le mipmap e tarata l'atmosfera SunshineClouds; sotto sono riportati interventi, confronti e limiti. Stato finale: dithering nuvole approvato e FSR2 nativo scelto come default dopo confronto visivo e benchmark. Confini e landmark rinviati. Le sezioni datate sotto conservano la cronologia, non sostituiscono questo stato.

**Conclusione:** non manca soltanto arredamento. Prima va sistemata la leggibilità di materiali, atmosfera e nuvole; poi si aggiungono landmark e dettagli ambientali.

## Scena effettivamente analizzata

- `scenes/maps/tutorial_map.tscn`: scena indicata come principale in `project.godot`.
- `scenes/levels/freeroam.tscn`: scena aperta nell'editor durante l'analisi; istanzia la stessa tutorial map e aggiunge player/HUD. Player a `(0, 2000, 0)`.
- `tutorial_map.tscn` nella root: copia non tracciata già presente, non modificata né usata per il survey. Fa riferimento a un diverso percorso della risorsa nuvole.
- Ambiente: Sky3D + SunshineClouds2 + Terrain3D.
- Nuvole: `resources/environments/tutorial_clouds.tres`.
- Dati terreno: `wc_data/WC_Terrain/`.

La scena della mappa contiene terreno, cielo/luci e driver nuvole, senza nodi dedicati a infrastrutture, landmark, acqua o effetti ambientali locali.

## Script di osservazione

File: `tools/tutorial_survey.gd`.

Da PowerShell, nella root del progetto:

```powershell
& "..\..\Godot_v4.7.1-stable_win64.exe" --path . --script tools/tutorial_survey.gd -- --hold
```

L'eseguibile trovato durante la sessione è:

```text
C:\Users\sanna\Workspace\Godot\Godot_v4.7.1-stable_win64.exe
```

Lo script carica la mappa separatamente dalla scena di gioco e crea otto viste:

1. Spawn del freeroam.
2. Nord, vicino al terreno.
3. Est, vicino al terreno.
4. Sud, vicino al terreno.
5. Ovest, vicino al terreno.
6. Sopra le nuvole, verso il terreno.
7. Sopra le nuvole, verso l'orizzonte.
8. Zenitale.

Le viste sopra le nuvole sono a 7.800 m con la configurazione attuale, ossia 1.800 m sopra il cloud ceiling. Le posizioni vengono calcolate dai limiti del terreno e dalla risorsa nuvole; lo spawn riprende le coordinate attuali del freeroam.

- Cattura PNG a 1280×720 e un `views.json` con le coordinate.
- Aspetta tre secondi per vista prima dello screenshot.
- `--hold`: resta aperto dopo le catture; frecce sinistra/destra cambiano vista, Esc esce.
- Senza `--hold`: termina dopo le catture.
- `--no-clouds`: disabilita l'intero compositor SunshineClouds, incluso il suo contributo atmosferico sul terreno, solo nel processo di osservazione. Non salva modifiche alla risorsa; non è un confronto con la sola geometria delle nuvole rimossa.
- `--atmosphere-baseline`: ripristina a runtime la densità atmosferica SunshineClouds precedente (0,4).
- `--atmosphere-sunshine`: prova la taratura scelta (0,8), senza nebbia Environment.
- `--atmosphere-godot`: prova nebbia Environment con densità 0,000035, colore `(0.74, 0.84, 0.96)`, aerial perspective 0,65, sky affect 0; azzera la densità atmosferica SunshineClouds per evitare sovrapposizioni. È un candidato diagnostico, non la configurazione salvata.
- I tre preset sono mutuamente esclusivi e combinabili con `--check` o `--hold`.
- `--check`: verifica geometria delle otto viste, senza richiedere rendering grafico.

Esempi:

```powershell
# Confronto senza nuvole
& "..\..\Godot_v4.7.1-stable_win64.exe" --path . --script tools/tutorial_survey.gd -- --no-clouds

# Check headless
& "..\..\Godot_v4.7.1-stable_win64.exe" --headless --path . --script tools/tutorial_survey.gd -- --check
```

Gli screenshot richiedono un renderer grafico Forward+, non headless.

## Catture e dati raccolti

Directory base:

```text
%APPDATA%\Godot\app_userdata\Aero Demons\tutorial_survey\
```

Passaggi finali:

- `2026-09-07T10-14-10`: con nuvole, viste laterali abbassate vicino al terreno.
- `2026-09-07T10-14-46`: senza nuvole, confronto diagnostico.
- `2026-09-07T10-12-55`: primo passaggio esplorativo; le viste laterali erano troppo alte e risultavano coperte dalle nuvole. Preferire i due passaggi finali.

Le immagini sono locali, fuori dal repository; non sono state copiate in `docs`.

Limiti del terreno riportati dallo script:

- X: −26.624 .. +26.624 m.
- Z: −26.624 .. +24.576 m.
- Altezze: 0 .. 3.468,276 m.

Questi sono limiti delle regioni Terrain3D, non una misura del percorso effettivamente giocabile.

## Findings e migliorie proposte

### P1 — Materiali del terreno

**Osservazione:** neve e roccia producono un effetto “sale e pepe”, visibile anche da lontano. Il dettaglio fine domina la lettura delle forme.

**Evidenza tecnica:** Terrain3D segnala mipmap mancanti per le texture albedo e normal dei sette asset. In `wc_data/textures/Texture_0_Albedo_packed.png.import` è stato verificato `mipmaps/generate=false`.

**Proposta:** abilitare mipmap, verificare filtraggio e scala dei materiali, poi rendere più ampie e coerenti le zone di neve, roccia e detrito. Non attribuire tutto il rumore alle mipmap prima del confronto visivo: anche distribuzione dei materiali e contrasto possono contribuire.

### Primo fix applicato — mipmap (7 settembre 2026)

- Abilitato `mipmaps/generate=true` nei 14 file `wc_data/textures/Texture_*_packed.png.import`: albedo e normal dei sette asset effettivamente referenziati dalla mappa. Texture reimportate.
- Confronto senza nuvole, stesse otto viste: prima `2026-09-07T14-20-03`, dopo `2026-09-07T14-22-00`, nella directory survey indicata sopra. Nuovo passaggio con nuvole: `2026-09-07T14-23-13`.
- Osservate le coppie spawn/est: nettamente ridotta la grana fine sulle superfici vicine e sul fondovalle. Restano macchie neve/roccia frammentate e rumore sulle montagne lontane: **il problema non è completamente risolto dalle mipmap**.
- Scala invariata (0,4 per gli asset 0–5, 0,2 per Debris); nessuna modifica a control map, geometria, contrasto o shader. I sampler degli shader di esempio Terrain3D usano filtraggio mipmap anisotropico; questo non costituisce una verifica dello shader generato attivo. Filtraggio runtime e distribuzione dei materiali restano da approfondire nel prossimo intervento.
- Verifiche: due survey finali completati (otto PNG ciascuno), check headless superato, `git diff --check` pulito. Nei survey finali e nel check non compaiono errori né warning di mipmap mancanti; restano warning di deprecazione/rilascio risorse.
- L'import globale dell'editor segnala anche risorse stradali mancanti (`road_pbr_detail.gdshader` e texture `asphalt_pbr`) e risorse non rilasciate in headless; non corrette in questo intervento. Non impediscono i survey della tutorial map.

Prossimo passo: diagnosticare il rumore residuo della distribuzione e del filtraggio a distanza, poi ampliare selettivamente le zone neve/roccia/detrito. Non compensarlo sfocando indiscriminatamente tutte le texture.

### P1 — Nuvole viste da sopra

**Osservazione:** sopra lo strato nuvoloso compare una distesa quasi bianca, con pochissimo rilievo leggibile e una fascia scura all'orizzonte. Lo mostrano soprattutto `06_above_clouds.png` e `07_cloud_horizon.png`.

**Configurazione attuale:**

- `clouds_coverage = 0.965`.
- `clouds_density = 0.1`.
- `cloud_floor = 2000.0`.
- `cloud_ceiling = 6000.0`.

**Proposta:** verificare prima illuminazione, esposizione e compositing, quindi lavorare su copertura, aperture e scala dei volumi. Aumentare semplicemente la qualità del raymarch non garantisce di correggere l'aspetto. La causa precisa della fascia scura e della perdita di rilievo non è stata diagnosticata.

### P1 — Profondità atmosferica

**Osservazione:** montagne vicine e lontane mantengono contrasti simili; la separazione tra piani è debole.

**Evidenza tecnica:** la nebbia Sky3D è disattivata nella scena. Questo non significa che SunshineClouds non applichi alcun contributo atmosferico.

**Proposta:** introdurre foschia atmosferica progressiva e banchi locali nelle valli, mantenendo leggibili ostacoli e percorso tutorial. Verificare l'interazione con l'atmosfera già applicata dalle nuvole, evitando sovrapposizioni eccessive.

### Secondo fix applicato — taratura atmosferica (7 settembre 2026)

**Scelta:** riutilizzare SunshineClouds, portando `atmospheric_density` da 0,4 a 0,8 in `resources/environments/tutorial_clouds.tres`. Nessun nuovo sistema di nebbia, shader, volume o modifica alle maschere/materiali del terreno. La nebbia Sky3D e quella Environment rimangono disattivate.

Confronti effettuati, tutti con nuvole attive e otto viste:

| Passaggio | Directory survey |
|---|---|
| SunshineClouds 0,8, candidato | `2026-09-07T16-37-19` |
| Nebbia Godot, candidato | `2026-09-07T16-37-56` |
| Baseline SunshineClouds 0,4 | `2026-09-07T16-39-54` |
| Configurazione finale salvata, senza override | `2026-09-07T16-40-31` |

Osservazione delle immagini: SunshineClouds 0,8 attenua e tinge maggiormente i rilievi lontani, mantenendo il primo piano sostanzialmente invariato. Nel preset Godot provato la velatura interessa maggiormente anche i rilievi vicini e risalta la fascia scura all'orizzonte. Questo confronto sceglie fra **due tarature concrete**, non dimostra un limite generale della nebbia Godot. Il bianco quasi uniforme sopra le nuvole rimane in entrambi: non è risolto da questo intervento.

Verifiche: quattro survey completati, check headless della configurazione salvata e di tutti e tre i preset superati, nessun `ERROR` nei relativi log, `git diff --check` pulito. Restano warning di deprecazione e rilascio GPU. Le catture hanno il limite di convergenza/vento già descritto; non sono confronti pixel-identici.

**Ancora da verificare:** scintillio durante il volo, comportamento durante salita/discesa e frame time. Questa sessione valuta immagini statiche, non certifica stabilità temporale o costo GPU. Prima di ridipingere neve/roccia, giudicare in movimento questa configurazione; intervenire sulle maschere solo dove il rumore resta effettivamente disturbante. Non aumentare ulteriormente la foschia solo per nasconderlo.

### Verifica del volo e diagnosi nuvole (7 settembre 2026)

Aggiunto `--flight` al survey: camera diagnostica (non fisica dell'aereo), 12 s lungo 2.400 m verso nord con quota campionata a 300 m dal terreno, 20 s di salita verticale fino a 7.800 m, 4 s in quota, 20 s di discesa. Il check verifica campioni finiti e partenza/arrivo sotto/sopra lo strato nuvoloso. È un percorso locale ripetibile, non una verifica di tutte le valli o delle collisioni del player.

Registrazione locale: `tutorial_survey/flight-review/flight.avi`, 1.772 frame a 30 FPS, 1920×1080, circa 59 s inclusa attesa iniziale. Il Movie Maker ha usato la risoluzione del progetto nonostante l'argomento `--resolution`; non confrontare i pixel direttamente con i survey 1280×720. Nella stessa directory: `overview.png` (campioni ogni 5 s) e `terrain-consecutive.png` (sei frame consecutivi da 8 s).

Comandi dalla root (per il movie, creare prima la directory di destinazione):

```powershell
$godot = "..\..\Godot_v4.7.1-stable_win64.exe"
& $godot --headless --path . --script tools/tutorial_survey.gd -- --check --flight
& $godot --path . --script tools/tutorial_survey.gd -- --flight
& $godot --path . --script tools/tutorial_survey.gd --write-movie "$env:APPDATA\Godot\app_userdata\Aero Demons\tutorial_survey\flight-review\flight.avi" --fixed-fps 30 -- --flight
& $godot --path . --script tools/tutorial_survey.gd -- --cloud-dim-sun
```

**Evidenze:**

- Shader Terrain3D attivo interrogato nel renderer grafico: sia `_texture_array_albedo` sia `_texture_array_normal` dichiarano `filter_linear_mipmap_anisotropic`; `get_texture_filtering()` restituisce 0 (lineare). Non serve abilitare un altro filtro. Headless non è usato per giudicare il codice shader generato.
- Nei frame consecutivi del tratto basso le creste restano leggibili e le macchie neve/roccia sono ancora frammentate. Questo esame di frame non certifica l'assenza di scintillio durante riproduzione continua.
- I campioni durante salita/discesa mostrano una trama regolare, a celle/reticolo, all'interno delle nuvole. È un difetto distinto dalla distribuzione dei materiali del terreno; causa ancora da isolare fra campionamento, risoluzione e ricostruzione temporale. Non attribuirlo già a uno specifico algoritmo.
- La parte superiore dello strato rimane quasi bianca e la fascia all'orizzonte resta visibile.

**Prova di illuminazione:** `--cloud-dim-sun` usa a runtime `directional_light_power_multiplier = 0.25` sul driver, aggiornando i dati delle luci. Il sole inviato a SunshineClouds passa da energia 2 a 0,5, senza modificare la luce del terreno. Questo influisce anche sul contributo atmosferico SunshineClouds alimentato dalle stesse luci: non isola la sola illuminazione interna dei volumi.

Survey della prova: `2026-09-07T17-33-13`, otto PNG. Nella vista `06_above_clouds` riemergono dettagli dei volumi e aperture prima quasi bianchi; la fascia all'orizzonte persiste. Questo indica che l'intensità luminosa contribuisce fortemente alla perdita di dettaglio, ma non dimostra da solo dove avvenga la saturazione nella pipeline HDR/tonemapping. **Nessuna taratura permanente delle nuvole applicata in questa sessione.**

Verifiche: volo registrato completato, check finale `--check --flight --cloud-dim-sun` superato, survey diagnostico completato, nessun `ERROR` nei rispettivi log, `git diff --check` pulito. Restano warning di deprecazione/rilascio GPU. Movie Maker ha impiegato circa 95 s per 59 s di video: include cattura e scrittura, **non è un benchmark del gioco**. L'analisi video diretta tramite tool non era disponibile; sono stati ispezionati i frame estratti. Validazione percettiva continua e prestazioni real-time rimangono aperte.

**Intervento consigliato ora:** tarare l'energia inviata alle nuvole confrontando anche la resa atmosferica da sotto; diagnosticare separatamente la fascia all'orizzonte e il reticolo nell'attraversamento. Non aumentare alla cieca i passi di raymarch e non modificare ancora le maschere del terreno.

### Terzo fix applicato — luce delle nuvole (7 settembre 2026)

In `scenes/maps/tutorial_map.tscn`, `SunshineCloudsDriverGD.directional_light_power_multiplier = 0.35` (prima default 1). Il driver aggiorna continuamente i dati: energia solare inviata al compositor **2 → 0,7**, luce del terreno sempre **2**. Non modificare soltanto `directional_lights_data` nella risorsa: il driver la sovrascrive. Nessuna modifica a esposizione globale, shader, copertura, densità, passi raymarch, antialiasing o materiali del terreno.

Quattro survey grafici da otto viste, directory locali:

| Moltiplicatore | Directory | Valutazione sopra/sotto lo strato |
|---|---|---|
| 1, baseline | `2026-09-07T18-28-29` | Distesa quasi bianca dall'alto |
| 0,5 | `2026-09-07T18-29-46` | Migliora, ma il rilievo rimane debole |
| 0,25 | `2026-09-07T18-32-33` | Più dettaglio dall'alto, base molto scura |
| **0,35, salvato** | `2026-09-07T18-34-58` | Compromesso fra rilievo superiore e luminosità della base |

Esaminate le quattro coppie `01_spawn` / `06_above_clouds`. Nel preset salvato riemergono dettaglio e aperture; la copertura resta estesa. La base delle nuvole è più scura della baseline, volutamente: non è una correzione limitata alla faccia superiore. La foschia rimane a 0,8, ma la luce alimenta anche lo scattering atmosferico SunshineClouds, quindi non si afferma che l'atmosfera sia pixel-identica. Il primo piano rimane leggibile nei confronti.

Verifiche: survey finali senza `ERROR`; check headless verifica energia compositor 0,7, sole terreno 2 e otto viste; percorso grafico `--flight` completo (salita, attraversamento, quota e discesa) terminato con `PASS`, senza `ERROR`. Il percorso è uno smoke test runtime, non una certificazione percettiva continua né una misura di prestazioni. Check dei preset diagnostici superati e `git diff --check` pulito; persistono warning di deprecazione e RID all'uscita.

Per confronto ripetibile: `--cloud-original-sun` ripristina a runtime il vecchio moltiplicatore 1; `--cloud-dim-sun` resta la prova 0,25. La prova iniziale usava 0,35; il valore finale scelto dall'utente e salvato è **0,3**, anche in freeroam. I due override sono mutuamente esclusivi e funzionano con `--flight`/`--check`.

**Restano aperti:** fascia scura all'orizzonte e reticolo nell'attraversamento, non corretti dalla taratura luminosa. Prossimo passo: isolare la fascia fra cielo, atmosfera e compositing, senza ritoccare nuovamente il terreno. La resa del nuovo compromesso va approvata dall'utente in freeroam.

### Prova applicata — raccordo orizzonte Sky3D (7 settembre 2026)

L'utente ha scelto luce nuvole **0,3**, già presente nella scena e preservata. Il survey ora calcola l'energia attesa dal moltiplicatore del driver (con lo stesso arrotondamento), anziché imporre il precedente 0,7; energia verificata 0,6, sole terreno sempre 2.

Diagnosi precedente, solo runtime: baseline `2026-09-07T18-49-51`, compositor spento `18-50-28`, atmosfera Sunshine azzerata `18-51-05`, max step count 600 `18-51-42`, horizon offset −0,02 `18-54-27` (tutte directory con prefisso `2026-09-07T`). Senza compositor emerge il fondo scuro Sky3D sotto l'orizzonte; senza atmosfera la fascia diventa quasi nera; raddoppiare i passi la restringe ma non la elimina. L'offset attenua il raccordo fra il fondo del cielo e il limite lontano delle nuvole. Non è un'estensione fisica dello strato nuvoloso.

Su richiesta di prova, salvato **`horizon_offset = -0.02`** nel nodo `Sky3D/SkyDome` e nel parametro del materiale cielo in `scenes/maps/tutorial_map.tscn`. Nessun cambio a luce 0,3, terreno, AA, atmosfera o passi raymarch.

Confronto esteso: quattro direzioni (nord, est, sud, ovest), da `(0,7800,0)` e `(0,12000,0)`, target 20 km avanti e 1.800 m sotto la camera. Baseline offset 0: `2026-09-07T19-03-32`; candidato −0,02: `2026-09-07T19-04-09`. File `horizon_00`–`03` alla quota bassa, `04`–`07` alla quota alta; coordinate nei rispettivi `views.json`. Esaminate le otto coppie in fogli di confronto.

**Risultato: miglioramento parziale.** A 7.800 m la fascia scura non è più evidente nelle quattro direzioni; a 12.000 m rimane, pur più sottile. Un offset fisso non copre qualsiasi quota. Non dichiarare il difetto risolto globalmente e non aumentare alla cieca l'offset senza verificare la resa dal basso.

Survey ordinario con impostazione salvata: `2026-09-07T19-04-46`, otto viste; spawn esaminato, terreno ancora leggibile. Volo grafico completo fino a 7.800 m e ritorno terminato con PASS, senza ERROR; è uno smoke test runtime, non una certificazione visiva continua. Check headless superato, energia 0,6 confermata, `git diff --check` pulito. Restano warning di deprecazione e rilascio RID. La prova è disponibile riavviando freeroam; per tornare indietro impostare Horizon Offset a 0 nel nodo e nel materiale cielo.

### Prima prova applicata — dithering alla scala dei pixel (7 settembre 2026)

In `addons/SunshineClouds2/SunshineCloudsCompute.glsl`, sostituito il tiling UV normalizzato ×40,037 con `(vec2(uv) + 0.5) / vec2(textureSize(dither_small, 0).xy)`: un texel della texture blue-noise per pixel del raymarch. La texture continua a ripetersi alla propria dimensione nativa, ma non viene più ricampionata alla scala dello schermo. Invariati sequenza temporale, sampler nearest, risoluzione Half, accumulo 0,7, passi, blur, luce 0,3 e offset orizzonte −0,02. Nessun nuovo campione o pass.

La diagnosi precedente aveva riprodotto la trama a 4.000 m: Native, passi dimezzati con budget raddoppiato e più blur non la eliminavano. Dither costante eliminava il reticolo ma introduceva fasce nette; accumulo 0,9 migliorava da fermo senza risolvere il movimento. Baseline statica: `2026-09-07T19-32-55`; nuova prova: `2026-09-07T21-29-32`, tre quote 2.500/4.000/5.700 m, esaminata in particolare `02_north` a 4.000 m.

**Esito promettente, non definitivo:** nei campioni del movimento la trama regolare e le strisce della baseline sono molto meno evidenti; resta grana fine. Non sono comparse le grosse fasce della prova con dither costante. Due registrazioni a fixed-fps 30 e 60, con salita da 2.500 a 5.500 m in 10 secondi e avanzamento 120 m/s, terminate con PASS senza ERROR. Confrontati fogli da sei fotogrammi a partire da 7 s dei video (incluso preriscaldamento di 3 s). Non è una misura degli FPS reali né una verifica percettiva di tutti i fotogrammi.

Script diagnostici, baseline video 30 FPS e nuovi video/fogli di confronto sono conservati localmente in `user://tutorial_survey/grid-sampling-review/`: `grid-base.gd`, `grid-motion-base.gd`, `grid-motion-base.avi/.png`, `grid-pixel-30.avi/.png`, `grid-pixel-60.avi/.png`. Per ripetere il probe usare `Godot --path . --script <percorso-assoluto>/grid-motion-base.gd --fixed-fps 30 --write-movie <output>.avi -- --flight`; lo script usa lo shader corrente, non incorpora quello baseline.

Survey ordinario `2026-09-07T21-32-52` completato senza ERROR, esaminate spawn e vista sopra le nuvole; nessuna regressione evidente in quelle viste. L'import editor ha invece segnalato errori Terrain3D (copia DLL), risorse strada mancanti e rilascio RID: non dichiarare l'import globale pulito. Le esecuzioni grafiche successive del survey e dei probe sono riuscite. `git diff --check` pulito. Da far approvare in freeroam prima di aggiungere correzioni temporali o aumentare la qualità.

### Sfarfallio a media distanza — confronto mirato (7 settembre 2026)

Segnalazione utente: montagne vicine corrette, sfarfallio ancora presente a media distanza. Non considerare quindi chiuso il problema dopo mipmap/atmosfera.

Registrati sette passaggi identici di 360 frame (12 s a 30 FPS, 1920×1080) nella directory locale `tutorial_survey/aliasing-review/`. `--quit-after 360` interrompe intenzionalmente il percorso durante il tratto basso. Tutti con `--flight --no-clouds`, quindi senza compositor né atmosfera SunshineClouds:

| AVI / opzione aggiuntiva | Cosa isola | Risultato nei frame esaminati |
|---|---|---|
| `baseline.avi` / nessuna | Configurazione corrente | Grana fine sulle creste intermedie |
| `no-sun-shadows.avi` / `--no-sun-shadows` | Ombre solari disattivate | La grana resta; le ombre non sono l'unica causa |
| `terrain-no-normal-maps.avi` / `--terrain-no-normal-maps` | Forza normal depth a zero sui sette asset | Nessun miglioramento netto della zona intermedia |
| `terrain-grey.avi` / `--terrain-grey` | Albedo grigia uniforme, illuminazione conservata | Dettaglio rumoroso ancora nei rilievi: non attribuirlo solo alle macchie neve/roccia |
| `terrain-soft-mips.avi` / `--terrain-soft-mips` | `depth_blur = 2` nel materiale | Poco cambiamento nel dettaglio disturbante a media distanza |
| `msaa.avi` / `--msaa` | MSAA 4× | Contorni più regolari, grana interna ancora presente |
| `taa.avi` / `--taa` | Antialiasing temporale | Attenuazione evidente della grana, ma anche ammorbidimento del primo piano |

Nella stessa directory, PNG a 6 s e fogli `*-sequence.png` con sei frame consecutivi della zona centrale (crop a `(800,380)`, 400×200 pixel, ingrandimento nearest). Giudizio qualitativo su frame estratti, **non misura quantitativa dello sfarfallio né visione continua certificata**. La camera si muove: una differenza fra frame non misura da sola aliasing. Le distanze dei singoli pixel del crop non sono state misurate.

Evidenza runtime: `TAA=false`, `MSAA=0` nella configurazione attuale. Lo shader attivo usa mipmap anisotropiche per albedo/normal, ma campiona height/control map con `texelFetch(..., 0)`; l'interpolazione di più campioni dipende da `region_mip < 0`. Le mipmap delle texture di superficie non filtrano automaticamente questo dettaglio del terreno. È una pista concreta di aliasing dello shading/campionamento del terreno, non una diagnosi definitiva di una singola istruzione.

Il parametro di prova `depth_blur` moltiplica le derivate delle texture a distanza: nel codice generato il fattore passa da `mipmap_bias` (default shader 1) a `depth_blur + 1`, dopo `bias_distance` (default shader 512 m), con transizione di 1.024 m. Non è una sfocatura dello schermo né un filtro della control map. I valori `null` restituiti dal getter nella baseline non vanno interpretati come zero: sono stati letti anche i default del codice shader generato.

**Decisione:** nessuna modifica permanente a terreno, nebbia o antialiasing. La prova TAA è la candidata più efficace fra quelle esaminate, ma va giudicata nel gioco con aereo, bersagli e nuvole (blur/ghosting e costo GPU non ancora validati). Evitare di aumentare la foschia o degradare le texture vicine per compensare questo difetto.

**Confronto direttamente in freeroam:** aprire `scenes/levels/freeroam.tscn` e avviarla con F6 dell'editor (scena corrente). Durante il gioco, premere **F6** per ciclare `Attuale → TAA → Mipmap morbide a distanza → Attuale`; il nome appare a schermo. I preset sono esclusivi, non salvano risorse e il ritorno ad Attuale ripristina i valori iniziali. MSAA è stato rimosso dal toggle: il cambio con SunshineClouds attivo su D3D12 ha prodotto perdita del device GPU (`0x887a0005` in `initialize_compute`) e una cascata di errori. La causa interna plugin/driver non è ancora isolata; il toggle non modifica più MSAA. Il primo test era insufficiente perché cambiava tutti i preset nello stesso frame. Test corretto `tests/freeroam_filter_check.gd`: 60 frame iniziali e 60 per modalità, due cicli completi con nuvole attive, ripristino e pressione prolungata/rilascio ignorati. Superato senza `ERROR`; restano warning di deprecazione e RID all'uscita.

Per ripetere il confronto nel viewer automatico:

```powershell
& "..\..\Godot_v4.7.1-stable_win64.exe" --path . --script tools/tutorial_survey.gd -- --flight
& "..\..\Godot_v4.7.1-stable_win64.exe" --path . --script tools/tutorial_survey.gd -- --flight --taa
```

Le opzioni sono override runtime nel survey; non salvano le risorse. Documentazione consultata: [Godot 4.7 — antialiasing](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html), [Terrain3DMaterial](https://terrain3d.readthedocs.io/en/stable/api/class_terrain3dmaterial.html). Sette catture completate senza `ERROR` nei log; non usare i tempi di Movie Maker come benchmark. Check finali headless dei probe e grafico di TAA/MSAA/depth blur superati, `git diff --check` pulito. Un primo check headless è fallito perché il getter del parametro shader restituisce `null` senza renderer: il controllo del valore GPU è stato spostato nel check grafico e i check sono stati rieseguiti.

### Sfarfallio — decisione utente e ripresa futura

**Stato: rinviato su richiesta dell'utente, non risolto.** Nel confronto manuale in freeroam l'utente giudica TAA l'unica modalità attualmente decente; baseline non accettabile e mipmap morbide peggiorative. Questo feedback in movimento prevale sulle valutazioni precedenti dei soli frame. Non è stato chiesto di abilitare TAA permanentemente: il toggle F6 resta diagnostico e la configurazione di avvio non cambia.

Alternative inizialmente documentate, ora disponibili nel confronto F6 descritto sotto:

- SSAA con scala 3D bilineare 1,25 e 1,5: prima alternativa da confrontare con TAA, senza accumulo temporale. A 1,5 si renderizzano 2,25 volte i pixel, non necessariamente 2,25 volte il tempo GPU. Verificare prima la ricreazione dei buffer con SunshineClouds attivo; il precedente crash MSAA impone un test grafico reale prima di esporre nuovi toggle.
- FSR2 a risoluzione nativa: diversa ricostruzione temporale, non elimina per principio blur/ghosting. Compatibilità e resa con le nuvole da verificare.
- Filtraggio mirato dello shading Terrain3D a distanza: possibile soluzione che preserva il vicino, ma la causa precisa va isolata prima di introdurre uno shader custom.
- FXAA a bassa priorità: non ci si aspetta una stabilizzazione temporale paragonabile al TAA. MSAA escluso dal toggle per il crash già documentato, non riproporlo senza diagnosi separata.

Fonte per SSAA/scaling: [Godot 4.7 — antialiasing](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html). Alla ripresa confrontare in movimento nitidezza vicina, scintillio intermedio, scie e frame time; non aggiungere foschia per nascondere il problema.

### Ripresa sfarfallio — confronto F6 esteso (7 settembre 2026)

Su richiesta dell'utente, riaperto il confronto in `scenes/levels/freeroam.tscn`. F6 cicla: **Attuale → TAA → SSAA 1,25× → SSAA 1,5× → FSR2 nativo → FXAA → Terreno: blending a distanza → Mipmap morbide a distanza → Attuale**. Tutto esclusivo e a runtime; nessuna scelta definitiva salvata. Attuale ripristina TAA, scala, algoritmo di scaling, AA screen-space, shader originale e depth blur iniziali. MSAA non viene mai modificato.

SSAA usa scaling bilineare senza TAA/FXAA; FSR2 usa scala 1,0 e la propria ricostruzione temporale, senza TAA aggiuntivo. FXAA è a scala nativa. Il candidato terreno riusa lo shader Terrain3D generato e rimuove soltanto il cutoff `region_mip < 0.0` dalla condizione del blending a quattro celle: mantiene interpolazione di materiali/normali anche in minificazione. Non è un filtro integrato sull'intera impronta del pixel, non garantisce di eliminare aliasing e aumenta il lavoro dello shading lontano. Viene creato solo in memoria, con controllo che la condizione originale sia presente una volta; nessuna copia permanente dello shader o nuova dipendenza. Il vecchio preset depth blur 2,0 resta per confronto.

Verifica grafica D3D12: `Godot --path . --script tests/freeroam_filter_check.gd -- --capture` ha renderizzato due cicli completi, 60 frame per modalità, con nuvole attive; PASS e nessun ERROR nel log. Verificati ritorno ai valori iniziali, MSAA invariato, pressione prolungata e rilascio F6. PNG per ciascun preset in `user://filter_comparison/00.png`…`07.png`; la camera segue l'aereo in movimento, quindi non sono coppie pixel-identiche. Esaminate le catture FSR2 e blending terreno: scena, nuvole e HUD presenti, nessun evidente errore di compositing in quelle viste. Questa è una verifica di funzionamento e commutazione, non un verdetto su scintillio/scie né un benchmark. L'utente deve scegliere in volo; attendere qualche secondo dopo ogni cambio per la convergenza temporale. Il precedente crash MSAA resta distinto e irrisolto.

### Benchmark dei due finalisti — SSAA 1,5× e FSR2 nativo

Utente: SSAA 1,5× e FSR2 nativo sono i migliori visivamente. Creato ed eseguito `tools/freeroam_filter_benchmark.gd`: freeroam a 1920×1080, RX 9070 XT, Forward+/D3D12, VSync e cap FPS disattivati, nuvole e HUD presenti. Fisica del player disattivata per imporre lo stesso avanzamento rettilineo di 180 m/s per 12 s da quota 2.000 m; camera di inseguimento ancora attiva. Tre passaggi per modalità, ordine ruotato, 5 s di preriscaldamento prima di ciascuno. Nessuna registrazione video, nessun fixed-fps. Meteo/vento non congelati; benchmark locale senza combattimento, non rappresentativo di tutte le quote o del carico CPU del volo normale.

Mediane dei tre risultati per modalità (FPS è la media temporale di ciascun passaggio; P99 è il percentile 99 del frame time):

| Modalità | FPS | Frame mediano | Frame P99 | GPU mediana viewport |
|---|---:|---:|---:|---:|
| Attuale | 429,0 | 2,317 ms | 2,773 ms | 2,168 ms |
| SSAA 1,5× | 240,5 | 4,140 ms | 4,951 ms | 3,991 ms |
| FSR2 nativo | 373,1 | 2,667 ms | 3,286 ms | 2,514 ms |

FSR2 produce circa il 55% di FPS in più di SSAA 1,5× in questo percorso, con tempo GPU mediano circa il 37% inferiore. Rispetto ad Attuale: −13% FPS per FSR2, −44% per SSAA. Intervalli FPS fra passaggi: Attuale 422,0–430,7; SSAA 239,3–242,4; FSR2 371,1–375,9. Raccomandazione prestazionale: FSR2 nativo, salvo preferenza visiva per SSAA. Successivamente approvato dall'utente e impostato come default in `project.godot` (`scaling_3d/mode=2`, scala 1,0). F6 resta disponibile; Attuale ripristina ora FSR2. Il benchmark forza invece il riferimento non filtrato prima di caricare la scena, per mantenere confrontabili i risultati.

Dati locali: `user://filter_benchmark_2026-09-07T22-54-23.json`. Ripetere con `Godot --path . --script tools/freeroam_filter_benchmark.gd`, senza altri carichi GPU. Esecuzione terminata con PASS e nessun ERROR; restano warning di deprecazione e rilascio RID alla chiusura. Misura GPU tramite timestamp viewport Godot, non misura VRAM né latenza input-to-display. `git diff --check` pulito.

**Nota storica — precedente problema attivo: P1 — nuvole viste da sopra.** Ripartire dalla prova `--cloud-dim-sun`: recupera rilievo ma modifica anche l'atmosfera. Tarare prima la luce inviata al compositor confrontando sopra e sotto lo strato; fascia scura e reticolo sono difetti distinti ancora aperti.

### P2 — Confini del mondo

**Osservazione:** la zenitale senza nuvole rivela bordi rettangolari netti sul vuoto. `world_background = 0` nel materiale Terrain3D.

**Proposta:** montagne di sfondo semplificate e una transizione periferica coerente. Non affidarsi soltanto alle nuvole per nascondere i bordi, dato che il giocatore può salire sopra lo strato nuvoloso.

### P2 — Ricognizione dei confini (7 settembre 2026)

Aggiunto `--edges` a `tools/tutorial_survey.gd`: otto viste aggiuntive, due per lato (bassa e 7.800 m), dalle regioni effettivamente più esterne verso l'esterno. La mappa non occupa tutto il rettangolo dei bounds: il punto medio del lato può cadere fuori dalle regioni. La selezione usa quindi le regioni presenti; il check verifica quota campionabile e coordinate finite. `--background-noise` prova `world_background = 2` esclusivamente a runtime.

Tre survey completi da 16 PNG, senza ERROR nei log finali:

- `2026-09-07T22-17-27`: baseline senza compositor.
- `2026-09-07T22-18-30`: background NOISE nativo, senza compositor.
- `2026-09-07T22-20-12`: configurazione salvata, con nuvole/atmosfera.

`edge_08/09` nord, `edge_10/11` est, `edge_12/13` sud, `edge_14/15` ovest (bassa/alta). Le prime due esecuzioni erano state interrotte dal limite di frame prima dell'ultima vista; usare i tre passaggi completi sopra, non quelli parziali. Check headless `--check --edges` superato, 16 viste; `git diff --check` pulito.

**Risultato:** il background NONE espone direttamente il cielo sotto il bordo. Il NOISE predefinito riempie gran parte del vuoto, ma non raccorda in modo convincente questo terreno importato: stacco netto fra montagne dettagliate e rilievi lisci, discontinuità scura particolarmente evidente a est e bordo lontano ancora riconoscibile. Con nuvole attive, nella vista alta est il vuoto resta visibile attraverso le aperture. Non è sufficiente aumentare foschia o copertura.

**Decisione:** non salvare il NOISE predefinito come fix; `world_background` resta 0. Questa prova non esclude una taratura migliore dello sfondo nativo. Prossimo intervento consigliato: prototipo su un solo bordo, con una fascia di terreno semplificato raccordata alle altezze esistenti; valutare prima se i parametri del background nativo bastano, altrimenti mesh periferica statica. Non generare subito una corona su tutta la mappa. Lo sfondo NOISE è soltanto visivo e non aggiunge collisioni: il limite giocabile e la gestione dell'uscita sono una decisione separata, non risolta da montagne decorative.

Ripetere con `Godot --path . --script tools/tutorial_survey.gd -- --edges --no-clouds`, aggiungendo `--background-noise` per il candidato o togliendo `--no-clouds` per la scena normale. Nessuna modifica permanente a geometria, maschere, atmosfera o confini di gameplay in questa ricognizione.

### P2 — Identità e orientamento

**Osservazione:** il paesaggio è quasi esclusivamente terreno innevato; mancano riferimenti costruiti riconoscibili nelle viste e nodi dedicati nella scena.

**Proposta:** pochi landmark grandi e leggibili in volo, per esempio:

- Una base aerea.
- Un radar su una cresta.
- Un'infrastruttura importante nella valle.

Collegarli visivamente tramite strade e infrastrutture secondarie. La loro posizione deve supportare orientamento e percorso tutorial, non essere decorazione casuale.

### P3 — Dettaglio ambientale

**Osservazione:** fondovalle e pendii non raccontano usi o processi differenti. Nella vista ovest emerge un bacino/fondovalle molto scuro; non è stata verificata la sua destinazione artistica.

**Proposta:** ghiacciai, accumuli e cornici di neve, ghiaioni e strade di servizio. Acqua o ghiaccio nel bacino soltanto se coerenti con la direzione artistica. Non assumere che la zona scura sia già un lago.

### P3 — Vita ambientale

**Evidenza:** la scena della mappa non contiene effetti ambientali locali dedicati. Audio e resa in movimento non sono stati valutati nel survey statico.

**Proposta:** neve sollevata sulle creste, pennacchi localizzati, luci di segnalazione e audio del vento variabile con quota/esposizione. Distribuire gli effetti in punti significativi, non uniformemente su tutta la mappa.

## Opzioni di intervento

### A — Polish tecnico

Materiali, atmosfera, nuvole e bordi.

È il miglior primo investimento: migliora tutta l'immagine senza riempire la mappa di asset. Non richiede di sostituire preventivamente i sistemi già installati.

### B — Scenario alpino militare (consigliato)

Polish tecnico più tre landmark collegati visivamente da strade/infrastrutture.

Dà identità e aiuta l'orientamento nel tutorial. È una proposta di direzione artistica, non una scelta già approvata dall'utente.

### C — Scenario cinematografico

Aggiunge meteo articolato, ghiacciai/acqua e dettagli localizzati lungo il percorso.

Richiede più lavoro artistico e un budget GPU misurato. Non è ancora disponibile una stima prestazionale o temporale affidabile.

**Raccomandazione:** partire da A, poi aggiungere i landmark di B. Vegetazione e particelle non correggono i problemi dominanti attuali. Il livello “AAA” non deriva dal numero di effetti, ma dalla coerenza artistica e tecnica del risultato.

## Verifiche eseguite e limiti

- Check headless finale: superato, otto viste valide e due sopra il cloud ceiling.
- Due passaggi grafici finali completati: con/senza nuvole, otto PNG ciascuno.
- Rendering: Godot 4.7.1 stable, Forward+, D3D12, AMD Radeon RX 9070 XT.
- Immagini selezionate aperte e osservate, incluse spawn, viste laterali, sopra nuvole e zenitale senza nuvole.
- Nessun `SCRIPT ERROR` o `ERROR:` nei log dei due passaggi grafici finali.
- Presenti warning sulle mipmap e sul rilascio di risorse GPU alla chiusura. La causa dei warning di rilascio non è stata isolata; non sono stati corretti.
- `git diff --check` senza segnalazioni.
- Prestazioni/frame time, stabilità temporale delle nuvole, audio e navigazione manuale del viewer non ancora validati.
- L'attesa fissa di tre secondi è una semplificazione: non misura la convergenza della history delle nuvole. I confronti non sono garantiti pixel-identici, anche perché il vento continua ad aggiornarsi.

Documentazione API consultata: Godot 4.7, cattura del viewport dopo `RenderingServer.frame_post_draw` e script standalone che estendono `SceneTree`.

## Controllo finale prima del commit

Rieseguiti: due cicli F6 grafici con default FSR2, check survey headless `--edges --background-noise` e `--flight --taa`, survey grafico ordinario (`2026-09-07T23-03-12`), benchmark completo e `git diff --check`. Tutti completati senza ERROR nei log; restano i warning noti di deprecazione/rilascio risorse. Isolati il riferimento senza filtri del benchmark e i probe TAA/MSAA del survey dal nuovo default FSR2.

Ripetizione benchmark: `user://filter_benchmark_2026-09-07T23-06-45.json`, mediane FPS Attuale 388,4, SSAA 226,8, FSR2 343,4. Conferma il vantaggio FSR2, ma valori assoluti inferiori al primo run e un P99 di 13,604 ms nel terzo passaggio FSR2 (gli altri due 3,513 e 3,446 ms): causa dello spike non isolata, non dichiarare assenza generale di stutter. Nessun crash o errore di rendering osservato. Non modificati i punti ambientali rinviati.

## Riprendere al prossimo incontro

1. Mantenere le scelte approvate: luce nuvole 0,3, atmosfera 0,8, horizon offset −0,02, dithering per pixel e FSR2 nativo.
2. Non riaprire confini e identità/landmark senza richiesta: entrambi rinviati.
3. Residui tecnici: distribuzione neve/roccia frammentata, fascia scura a 12.000 m, grana fine nuvole e verifica prestazioni in combattimento/ad altre quote. Il confronto sfarfallio è concluso per ora con FSR2.
4. P3 ancora da affrontare: dettaglio ambientale, destinazione del bacino ovest, effetti locali e audio; confermare la direzione artistica prima di aggiungere asset.
5. Problemi collaterali ancora aperti: risorse strada/import Terrain3D, warning RID e crash al cambio MSAA. DLSS/FSR3 sono opzioni future, non integrazioni già disponibili.

### Protezione del lavoro esistente

All'inizio della sessione erano già presenti modifiche a:

- `addons/SunshineClouds2/SunshineClouds.gd`
- `project.godot`
- `scenes/player/player.tscn`
- `scripts/camera/follow_camera.gd`
- `scripts/player/player_flight.gd`
- `scripts/vfx/explosion_fx.gd`
- `wc_data/WC_Terrain/terrain3d_12_04.res`

Erano inoltre già non tracciati `scenes/levels/`, `tests/player_camera_check.gd`, il relativo UID e `tutorial_map.tscn` nella root.

Non ripristinare né sovrascrivere questi file per ripartire dall'analisi. Le aggiunte di questa attività sono lo script di survey e questo documento; nessun commit è stato creato.
