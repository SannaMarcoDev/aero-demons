# Garda — revisione paesaggio e confronto Nuclear Option

## Pass corrente — mosaico rurale, boschi misti e atmosfera (25 settembre 2026)

**Aeroporto, edifici, strade, DEM, scala e confini invariati.** Intervento sulla
mappa condivisa da freeroam/tutorial, non su una scena dimostrativa.

- Copertura immutabile 4096² dell'intero DEM: bosco/cultivazione in RG, quota
  a 16 bit in BA. Sottobosco, distribuzione degli alberi e fondale usano gli stessi
  dati, senza dipendere dalle zone già visitate. Generatore: `tools/bake_garda_landcover.gd`.
  Le esclusioni esistenti di `garda_development.gd` restano attive.
- Campi irregolari con colori delle colture, solchi filtrati e margini erbosi
  nello shader; nessuna nuova strada. Texture montana CC0 Aerial Rocks 02,
  transizioni ghiaiose alla riva e acqua animata con colore di basso fondale.
  Piano acqua esteso per rimuovere il bordo rettangolare precedentemente visibile.
- Conifera CC0 Poly Haven accanto alla latifoglia: miscela dipendente dalla quota,
  spaziatura nominale 12 m, massimo 797 tile residenti, stessi LOD e dissolvenza.
  [Sorgenti/bake](../assets/environment/garda_forest/SOURCES.md),
  [texture roccia](../textures/terrain/garda/SOURCES.md).
- Mattino fisso alle 09:00, luce indiretta ridotta e ombre Garda estese a 8/16 km
  per High/Ultra; Low/Medium e le altre mappe mantengono la distanza precedente.
  Nuvole volumetriche sparse 2600–4400 m, copertura massima Garda 0,68, cirri più
  discreti e foschia progressiva. La somma della luce nel compute Sunshine è ora
  normalizzata per il numero di campioni: è un correttivo dello shader condiviso.

### Confronto e misure

[Prima/dopo: cinque camere identiche](images/landscape-review/rural-before-after.jpg)
· [Passaggio basso](images/landscape-review/rural-motion.jpg)
· [Misure complete e frame time grezzi](images/landscape-review/rural-measurements.json).
Camera/FOV identici; luce e meteo cambiano volutamente. Le immagini al suolo
aggiunte dopo la baseline non sono presentate come confronti prima/dopo.

Godot 4.7.2, Linux/Vulkan Forward+, RX 9070 XT, 1920×1080 nativo, TAA, Ultra.
Catture statiche dopo streaming: 139–222 FPS nelle 13 viste del run `final`,
GPU mediana 4,24–6,79 ms; il passaggio ravvicinato aggiunto misura 124 FPS.
Ultimo run in movimento (`final-settled`), quattro segmenti da 8 s a circa
348 m/s, senza I/O delle immagini, vento e aggiornamenti Sunshine attivi:

| Segmento | FPS | GPU mediana ms | p95 frame ms | massimo ms |
|---|---:|---:|---:|---:|
| Valle | 124,8 | 5,165 | 10,914 | 15,757 |
| Lago | 173,6 | 3,813 | 7,573 | 10,763 |
| Alpi | 195,5 | 3,172 | 6,696 | 9,840 |
| Quota 5 km | 155,6 | 4,485 | 7,930 | 11,017 |

Memoria rendering indicata da Godot: circa **4820 MiB**, non una misura esterna
completa della VRAM. Massimo lavoro CPU per tile bosco 8,82 ms. I run precedenti
hanno FPS diversi: non sono medie di benchmark ripetuti né garanzie di fluidità
su tutta la mappa o per sessioni lunghe. I quattro segmenti coprono zone distinte,
non un volo continuo attraverso tutti i 250 km.

### Verifiche e limiti rimasti

- `git diff --check`: PASS; nessuna modifica alle regioni DEM o agli asset aeroportuali.
- `garda_surface_review.gd --check`: PASS headless, risorse e otto viste del DEM.
- `garda_forest_review.gd`: PASS headless e Forward+; adattato il verificatore
  esistente ai due gruppi di specie e alla maschera statica. Determinismo,
  inclusione/esclusione, riuso/eviction, LOD/proxy e readback dei buffer sulla GPU.
- `garda_screenshot_capture.gd`: PASS, dieci camere originali in `original-cameras/`;
  rimosso il limite di 60 frame che lasciava lo streaming incompleto. Il limite
  temporale è gestito dal runner esterno, non da una cattura parziale silenziosa.
- Catture e quattro tratti in movimento: PASS; volo con fisica/HUD per 12 s,
  circa 1893 m percorsi e salute 100. Marker espliciti, exit 0, nessun errore script.
- Freeroam (`r859881-1`) e tutorial (`r911192-2`) avviati tramite Godot AI MCP
  con `autosave=false`, confermati **live**, log game e boot/editor controllati;
  nessun errore del run. Errori `OptionsPanel` in vecchi verificatori controller
  erano già trattenuti nel log editor prima del cursore 6, non errori dei due avvii.
- Corretto il warmup della cattura: prima si assestava una posa troppo bassa e
  solo al primo frame misurato veniva applicata la distanza di sicurezza dal DEM,
  producendo macchie chiare temporali. Ora posa, orientamento, streaming e storia
  TAA/nuvole si stabilizzano prima del movimento. Le immagini `final-settled`
  sostituiscono le sequenze intermedie `final`/`final-motion`.
- Rimangono warning UID FA-N26, collegamento Road Generator e API deprecata;
  alla chiusura GPU sono segnalati RID Compute/Shader/Sampler/Vertex non liberati.
  Il run termina correttamente, ma **il teardown GPU non è privo di warning**.
  Non è stata eseguita l'intera suite; i vecchi controlli di cielo/impostazioni
  contengono aspettative di ora/meteo/distanza ombre precedenti a questa direzione.
- **Non è ancora parità con Nuclear Option**: chiome/impostori ripetuti, sponde e
  sagome limitate dal DEM, campi procedurali anziché GIS e dettaglio delle nuvole
  ancora morbido. Nessuna fog aggiunta per occultare i limiti geografici. Serve
  approvazione estetica dell'utente, distinta dai controlli di avvio.

Catture PNG: `subagent-artifacts/garda-lookdev/final/`; movimento corretto:
`final-settled/`; log: `subagent-artifacts/garda-lookdev/logs/`. Artefatti locali
ignorati da Git; i confronti JPEG e le misure qui collegate sono conservati in `docs/`.

```sh
node tools/run_godot_check.cjs 300 /tmp/garda-review.log GODOT --path . --script res://tools/landscape_review.gd -- --out=res://subagent-artifacts/garda-lookdev/new-run --motion --gameplay
```

Le sezioni seguenti documentano **revisioni storiche**, non i parametri correnti.

## Risultato e limiti (revisione precedente)

La revisione è integrata nella **mappa reale condivisa da freeroam e tutorial**, non in una scena dimostrativa: chiome ricostruite, boschi estesi con radure e margini irregolari, sottobosco collegato alla densità effettiva, erba locale, roccia meno blu, nuvole più frammentate e atmosfera meno opaca.

Il miglioramento più evidente è vicino al bosco. **Non è ancora la qualità dei riferimenti Nuclear Option**: rimangono una sola specie, ripetizione delle sagome/impostori lontani, distribuzione non geografica, DEM grossolano e assenza di campi/strade/dettagli territoriali. Non dichiaro 200 FPS costanti: alcune viste migliorano, altre peggiorano per la copertura molto più ampia.

Base di partenza: `fbb446b49378b5e605c7c9b344660dddfa4601cf`; checkout inizialmente pulito e allineamento `origin/HEAD` verificato. Nessun commit/push. Nessuna modifica ai dati height/control/region Terrain3D; nessun salvataggio delle impostazioni personali durante le catture.

## Aggiornamento: città aeroportuale

[Città integrata e misure correnti](../assets/environment/airport/source/CITY_DELIVERY.md).
I precedenti dischi vuoti da 4 km (boschi) e 3,5 km (erba) sono sostituiti da
`garda_development.gd` e dalla maschera statica `garda_development.res`: isolati,
strade, aeroporto e corridoi di avvicinamento restano liberi, i boschi tornano
negli interstizi. Nessun cambiamento ai file delle regioni Terrain3D.
Le misure sotto precedono questa aggiunta e non ne certificano le prestazioni.

## Aggiornamento: copertura continua dei boschi

La segnalazione delle vallate completamente spoglie era corretta: il codice popolava solo **16 ellissi predefinite**, non era un difetto del LOD. Quella limitazione è rimossa.

- `garda_forests.gd` genera ora boschi deterministici su qualunque zona idonea del DEM attraversata dalla camera, con noise continuo, radure e le stesse esclusioni acqua/pendii/quota/aeroporto. Spaziatura nominale 17 m: la prova a 15 m era più costosa.
- Finestra circolare di **797 tile al massimo**, lato 488,28 m, raggio circa 7,8 km. Un tile creato e uno ritirato per frame; i tile sovrapposti vengono riutilizzati, quelli lontani realmente liberati. Nessun limite globale consumato dalle prime zone, nessuna crescita senza limite durante il volo.
- MultiMesh Godot locali, riutilizzando mesh/materiale/LOD dello slot Terrain3D 1. Questo evita modifiche ai dizionari interni dell'instancer 1.0.2 e ai file delle regioni. LOD 140/650 m, medesimo proxy ombre LOD2; alberi sfumati fra **6 e 7 km**, prima del bordo di streaming. Non vengono caricati simultaneamente i 250 km di mappa.
- Copertura sottobosco RF 512², un texel per tile; al ritorno la densità è sovrascritta, non sommata. La memoria delle zone visitate rimane nella texture fissa, non nei nodi degli alberi. È più grossolana della precedente maschera 2048².
- Dopo avvio o teletrasporto la popolazione è progressiva, dal vicino al lontano: fino a circa 797 frame per la finestra intera (~13 s a 60 FPS), non un singolo blocco di generazione. Il normale attraversamento richiede soltanto la nuova fascia esterna. A FPS molto bassi/velocità estreme il margine di precaricamento può non bastare.

**Confronti effettivi**, stessa camera/FOV/meteo, nelle due valli prima escluse:

- [Valle est — prima/dopo](images/landscape-review/coverage-east-before-after.jpg)
- [Valle ovest — prima/dopo](images/landscape-review/coverage-west-before-after.jpg)
- [Misure e frame time grezzi](images/landscape-review/coverage-measurements.json)

Catture finali: `subagent-artifacts/landscape/coverage-delivery/`. Controllate anche viste al suolo, volo basso, pista libera e sequenza in movimento. Nessun cambiamento agli asset, all'erba, all'atmosfera o alle impostazioni personali in questo aggiornamento.

### Costo e verifiche di questa modifica

Godot editor 4.7.1, RX 9070 XT, D3D12/Forward+, 1080p nativo/TAA/Ultra, seconda finestra di misura dopo stabilizzazione dello streaming:

| Vista | FPS | GPU mediana ms | Alberi residenti |
|---|---:|---:|---:|
| Suolo | 140,1 | 6,716 | 240.544 |
| Volo basso | 146,4 | 6,297 | 231.811 |
| Aeroporto | 168,8 | 5,553 | 179.246 |
| Valle est | 178,4 | 5,241 | 257.360 |
| Valle ovest | 143,8 | 6,432 | 183.759 |

Passaggio di 8 s con ricambio reale dei tile: **140,8 FPS**, GPU mediana **5,873 ms**, p95 **10,098 ms**, massimo **109,891 ms**. Il picco non va nascosto: lo streaming non è ancora certificato privo di scatti. Massima costruzione misurata di un tile **4,846 ms** (non comprende tutto il lavoro differito del renderer); memoria rendering circa **4483 MiB**. Più copertura non è gratuita: rispetto alla precedente consegna, suolo 157→140, volo basso 171→146, aeroporto 243→169 FPS. Sono campioni editor, non una certificazione release né una misura controllata di ogni causa del costo.

Prove intermedie `coverage-after` (15 m), `coverage-final` (attesa camera incompleta), `coverage-shadows` (proxy limitato a 1500 m) non sono la consegna. La riduzione della distanza ombre dava meno draw call ma tempi peggiori in quella prova: ripristinata la politica precedente, senza dedurre un miglioramento dai soli contatori. La cattura finale attende esplicitamente il nuovo centro: `process_frame` da solo può riprendere prima di `_process` e leggere ancora `built=true` della vecchia camera.

Verifiche eseguite:

- `tools/garda_forest_review.gd`: **PASS headless e GPU**; determinismo, attraversamento/reimpiego tile, teletrasporto e ritorno, tre zone remote inclusa `(-120000,-114000)`, esclusioni, allineamento DEM, buffer di tutti i LOD (GPU), proxy, eviction effettiva, copertura senza accumulo e nessuna istanza scritta nelle regioni. Il renderer dummy non permette il readback dei buffer: quel controllo è realmente eseguito nel run GPU.
- `tests/garda_ground_cover_check.gd`: **PASS**. `tools/performance_benchmark.gd --quick --views=airport`: **PASS**, 167,6 FPS; il benchmark condiviso attende ora lo streaming dopo lo spostamento, congelando temporaneamente la fisica prima del warmup.
- Freeroam e tutorial avviati via **Godot AI MCP**, `autosave=false`, confermati **live**, log game/editor controllati senza nuovi errori; play fermato e mappa lasciata aperta. Questo è un controllo d'integrazione, non una certificazione del gameplay. Separatamente `landscape_review.gd --views=none --gameplay` **PASS**: tre catture con fisica/HUD attivi, 630–1893 m percorsi e salute 100 (`coverage-flight/`).
- `git diff --check`: **PASS**, salvo avviso di normalizzazione CRLF già presente. Restano warning preesistenti UID texture FA-N26, interpolazione deprecata e stile degli script.

Riproduzione: usare i comandi sotto con output nuovo e `--views=ground,low_flight,east,west,airport --motion`. Non usare più `garda_forest_review.gd --capture`: il controllo è dedicato alla regressione; catture e tempi sono in `landscape_review.gd`.

## Confronti conservati (revisione precedente)

Le immagini sotto sono catture Godot, non render Blender o immagini generate. Stesse camere/FOV tra prima e dopo; cambia volutamente il trattamento ambientale.

- [Vicino al bosco — prima/dopo](images/landscape-review/ground-before-after.jpg)
- [Volo basso — prima/dopo](images/landscape-review/low_flight-before-after.jpg)
- [Aeroporto — prima/dopo](images/landscape-review/airport-before-after.jpg)
- [Quota — prima/dopo](images/landscape-review/cruise-before-after.jpg): la baseline è immersa nelle nuvole; **non** è un confronto equivalente di visibilità del terreno.
- [Sei fasi a confronto](images/landscape-review/iterations.jpg)
- [Erba e alberi al suolo](images/landscape-review/meadow.jpg): vista aggiunta dopo la baseline, quindi nessun falso “prima” di questa camera.
- [Passaggio della camera](images/landscape-review/motion.jpg)
- [Volo con giocatore, HUD e fisica attivi](images/landscape-review/gameplay.jpg)
- [Misure complete delle varianti](images/landscape-review/measurements.json), inclusi i tempi grezzi del passaggio finale.

PNG originali, 240 fotogrammi finali, log, JSON, backup iniziali e sorgenti Blender sono in `subagent-artifacts/landscape/` e `subagent-artifacts/garda-forest/tree-source/` (ignorati da Git). Preview MP4: `subagent-artifacts/landscape/delivery/flight-preview.mp4`. È una sequenza di pose ricomposta a 60 fps, **non una registrazione della fluidità reale**: il salvataggio dei frame rallenta l'acquisizione e il vento usa il tempo reale. Le prestazioni in movimento sono misurate separatamente, senza I/O delle immagini.

## Esperimenti e decisioni

| Artefatto | Modifica sostanziale | Esito |
|---|---|---|
| `baseline` | Stato iniziale, cinque camere, 39.564 alberi | Chiome ad ombrello scure, boschi isolati, roccia blu, cielo molto coperto |
| `clear` | Boschi più estesi, palette, depth fog leggera | Più continuità, ma doppia atmosfera con Sunshine |
| `overcast` | Copertura .90, meno sole, foschia più densa | Scartato: immagine piatta, rilievo e silhouette meno leggibili |
| `canopy_clear` | Nuove chiome ovoidali stratificate e atlas rivisto | Migliore volume vicino; backface lontane troppo scure |
| `scattered` | Nuvole più piccole, crown-normal shader, impostore 18 triangoli, prima erba | Migliore cielo; alberi lontani piatti/chiari, erba troppo larga e pallida |
| `refined` | Erba curva più sottile/scura, occlusione chiome, ombre proxy ripristinate | Migliore suolo; 292.006 alberi e impostore suddiviso troppo costosi |
| `final_candidate` | Spaziatura 15 m, 219.320 alberi, impostore 6 triangoli | Riduzione netta del costo, conservando le aree boscate |
| `normal_atlas` | Normali object-space renderizzate da Blender per il LOD lontano | Prima prova sbagliata: Blender invertiva le normali delle backface, macchie nere |
| `delivery` | Bake corretto rimuovendo l'inversione backface | Selezionato: più volume degli impostori con circa 0,1 ms GPU aggiuntivi |

**Problema di cache accertato:** `clear` e `overcast` usavano ancora il vecchio GLB importato. Sono validi per popolazione/atmosfera, NON per giudicare la nuova geometria. Il comando MCP `reimport` aveva risposto positivamente senza aggiornare gli hash. Da `canopy_clear` in poi: scansione filesystem completa e confronto `source_md5` con i sorgenti.

Un'altra prova limitava le ombre a LOD1: aumentava la geometria elaborata rispetto al proxy LOD2. Scartata, non assunta come ottimizzazione solo perché aveva meno draw call. Depth fog aggiuntiva e maggiore sfocatura orizzonte scartate per leggibilità in volo; mantenuti esposizione, sole, post-process e controlli F6/F7 esistenti. Non ho aggiunto un grading aggressivo per nascondere i problemi degli asset.

## Implementazione consegnata

- **Albero:** generatore Blender esistente riutilizzato, 18 rami principali e 39 centri fogliame; LOD **3640 / 598 / 6 triangoli**, una superficie per LOD. Normali di chioma, alpha scissor .4, variazioni indipendenti di larghezza/altezza/tinta, lieve vento e dissolvenza lontana oggi 6–7 km. Lo streamer riutilizza gli asset Terrain3D con soglie di visibilità 140/650 m. Le mesh con suffissi Blender sono riconosciute correttamente: verificato sui tre mesh asset importati, non dedotto dai nomi.
- **Texture:** ramo fotografico CC0 e corteccia Poly Haven già nel progetto; luminosità/saturazione ramo 2.05/.65. Atlas albedo e normali lontane 2048² con mipmap e compressione VRAM. Catalogo Poly Haven esaminato, nessun nuovo modello/dependency necessario. [Fonti, hash, licenze e ricostruzione](../assets/environment/garda_forest/SOURCES.md).
- **Boschi:** streaming sull'intero DEM idoneo, descritto nell'aggiornamento sopra; sostituisce le 16 ellissi iniziali. MultiMesh, nessun nodo/collisione per albero. Conservato il margine 0.001 sulla normale di piazzamento contro gli arrotondamenti float vicino ai 35°.
- **Sottobosco:** texture runtime RF oggi 512² derivata dai tile accettati; scurisce il terreno sotto le masse boscate indipendentemente dal LOD. Nessuna pittura/salvataggio di control map.
- **Erba:** 25 tile locali da 40 m, massimo una costruzione/frame, 1500 candidati/tile deterministici; 12 fili curvi/36 triangoli per ciuffo. MultiMesh senza collisioni, ombre o alpha blending; dissolvenza geometrica 55–92 m, nascosta sopra 130 m AGL. Esclusioni di pendio, acqua e aeroporto. Non è ancora un prato fitto da simulatore a piedi.
- **Atmosfera:** Sunshine rimane l'unica foschia. Nuvole 2600–4400 m, scale 6500/1300/320, densità .022, aerial density 1.3, copertura predefinita .72. **Le preferenze meteo già salvate restano rispettate**, quindi una vecchia copertura .834 può produrre un cielo più coperto dei confronti. Per il confronto esatto usare il tool, non cancellare `user://settings.cfg`.

## Prestazioni misurate (revisione precedente, prima dello streaming)

Godot **4.7.1 editor binary**, Forward+/D3D12, RX 9070 XT, Ultra, **1920×1080 nativo/TAA**, VSync e limite fps disattivati; player/HUD nascosti per le camere fisse. Due finestre da 2 s dopo warmup da 2 s per vista; qui la seconda finestra. Nessuna rimozione degli outlier. Le differenze includono il nuovo cielo, non sono il costo isolato della vegetazione. Non sono misure release o una garanzia su altre GPU.

| Vista | FPS prima → dopo | Mediana GPU ms prima → dopo | p95 frame ms dopo |
|---|---:|---:|---:|
| Vicino | 119,4 → **157,4** | 7,70 → 5,82 | 12,29 |
| Bosco | 111,5 → **139,5** | 8,27 → 6,59 | 13,09 |
| Volo basso | 181,0 → **170,8** | 5,03 → 5,34 | 11,80 |
| Quota | 256,2 → **176,3** | 3,51 → 5,16 | 11,63 |
| Aeroporto | 243,0 → **243,3** | 3,71 → 3,71 | 4,06 |
| Prato, nuova camera | n/d → **217,4** | n/d → 4,17 | 4,55 |

Passaggio continuo di **8 secondi** senza screenshot: **163,0 FPS**, GPU mediana **5,05 ms**, p95 **11,28 ms**, massimo **15,45 ms**. Non significa “163 fps bloccati”: i picchi sono misurati e visibili nei dati.

- Primitivi vicino: 7,56 M → 3,80 M; quota: 0,88 M → 2,10 M. Più copertura costa più draw call: vicino 388 → 1287, quota 253 → 1071.
- Build finale osservata **2,62 s**, circa **4,56 GiB** riportati dal monitor render. Massimo tile erba **7,27 ms**. Un patch forestale può ancora bloccare l'avvio per circa **290 ms**: non ho nascosto questo costo nella media del volo.
- Il precedente report release oltre 200 FPS misurava altri asset/scene: non è una certificazione valida per questa revisione. **Resta da eseguire un benchmark release finale e ridurre il costo dei boschi estesi** prima di rivendicare quel budget.

## Verifiche e incidenti risolti

- `garda_ground_cover_check.gd`: PASS headless, determinismo, esclusioni, aderenza DEM, limite candidati/25 tile dopo teletrasporto, quota e mesh.
- `garda_forest_review.gd`: PASS headless e Forward+, tutti i 219.320 piazzamenti nativi, budget/LOD/proxy, atlas e mipmap; parametro forest-cover verificato con rendering reale perché il dummy renderer non riflette gli uniform. Teardown del compositor aggiunto al tool dopo warning RID di una prova breve; rerun senza quei warning.
- `sky3d_clear_day_check.gd`: PASS nelle due scene, nuovo default .72 e assenza di doppia fog.
- `horizon_graphics_check.gd`: assert passati; prima esecuzione fallita per teardown audio, rerun verbose PASS senza leak. Resta una possibile intermittenza del teardown audio headless, non un errore visivo dello shader.
- `boundary_return_check.gd`: PASS dopo aver impostato esplicitamente il fixture in volo: il tutorial ormai parte a terra, quindi il vecchio test non attivava la logica di rientro. Nessuna modifica al gameplay del rientro.
- `settings_apply_check.gd`: PASS **su GPU**. Il tentativo iniziale headless era improprio per questo test ed è stato interrotto dal runner; non è contato come pass.
- `garda_surface_review.gd --check`: PASS headless, otto viste e risorse Terrain3D; erba disattivata per isolare la superficie. Marker aggiornato al formato richiesto dal runner.
- `sunshine_ground_shadow_check.cjs`: PASS.
- Packing atlas: ricostruzione albedo e normali pixel per pixel PASS.
- Catture finali e volo controllato con giocatore: PASS, exit 0. La prima acquisizione di 240 PNG ha superato il deadline; runner ha chiuso solo il processo posseduto. Rilanciata in JPEG con deadline adeguato, completata.
- Mappa aperta e **freeroam/tutorial avviati tramite Godot AI MCP, autosave=false**, entrambi confermati `live`; log del run e log editor controllati, nessun nuovo parse/load/runtime error. Ispezionati volo, input e rullaggio. Il primo volo libero MCP lasciato in picchiata ha terminato contro il terreno: non viene presentato come prova di volo riuscita. Il passaggio controllato separato ha mantenuto fisica/HUD/giocatore reali e salute 100 nelle tre catture.
- Persistono warning preesistenti dei due UID texture FA-N26, interpolazione deprecata e warning di stile nei vecchi script. Nessun processo di test lasciato attivo; editor e Blender dell'utente conservati.

## Riprodurre / continuare

```text
node tools/run_godot_check.cjs 150 run.log GODOT --path . --script res://tools/landscape_review.gd -- --out=res://subagent-artifacts/landscape/new-run --motion
node tools/run_godot_check.cjs 230 video.log GODOT --path . --script res://tools/landscape_review.gd -- --out=res://subagent-artifacts/landscape/new-video --video
node tools/run_godot_check.cjs 120 flight.log GODOT --path . --script res://tools/landscape_review.gd -- --views=none --gameplay --out=res://subagent-artifacts/landscape/new-flight
node tools/run_godot_check.cjs 120 forest.log GODOT --headless --path . --script res://tools/garda_forest_review.gd
node tools/run_godot_check.cjs 120 grass.log GODOT --headless --path . --script res://tests/garda_ground_cover_check.gd
```

`GODOT` locale: `C:/Users/sanna/Workspace/Godot/Godot_v4.7.1-stable_win64.exe`.
Python locale: `C:/Users/sanna/AppData/Local/Programs/Python/Python313/python.exe`.
`--style=clear|overcast|scattered` riapplica le alternative atmosferiche sugli asset attuali; **non** ricrea gli asset storici. Default `authored`. `--views=ground,low_flight` permette controlli mirati. Le reference fornite dall'utente restano sotto `subagent-artifacts/landscape/references/`.

Prossimo lavoro utile, in ordine: profilare draw/shadow/batching e startup con build release; migliorare impostori multi-vista e seconda silhouette/specie; usare maschere geografiche di copertura; aggiungere dettagli del territorio. Evitare un'altra passata di sola saturazione o foschia: non risolverebbe i limiti rimasti.
