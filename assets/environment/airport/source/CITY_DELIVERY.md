# Città aeroportuale — consegna integrata

## Aprire

- **Blender:** `airport.blend`, collezioni separate `airport_asset` e `city_authored`.
- **Godot:** `res://scenes/maps/garda_final.tscn`, nodo `AirportCity`; condivisa da freeroam e tutorial.
- **Asset città:** `../airport_city.glb`, contenitore `res://scenes/maps/airport_city.tscn`.
- **Immagini Godot:** [insieme](previews/city/overview.jpg), [quartieri](previews/city/district.jpg), [strada](previews/city/street.jpg), [lungomare](previews/city/waterfront.jpg), [avvicinamento](previews/city/approach.jpg), [passaggio basso](previews/city/low_pass.jpg).

L'intervento riguarda aeroporto e dintorni, non l'intera mappa: quattro quartieri, **42 isolati**, centro con tre torri e sede ricerca a gradoni, campus e servizi civici, logistica, controllo aeroportuale, banchina con pontili, viadotto, centro telecomunicazioni e sei turbine ferme. Auto e arredo sono statici. La città è ordinaria nell'aspetto: nessuna cinta da fortezza o segnaletica che ne esponga il segreto narrativo.

Pista **2400 × 60 m**, posizione, hangar e geometria aeroportuale conservati; asfalto scurito. Le strade preesistenti dell'utente non sono state riscritte. Nessun livellamento del DEM, nessuna modifica a costa, acqua o regioni Terrain3D. I **180.525 campioni altimetrici** del sito coincidono esattamente fra rilievo iniziale e finale. Tolte le due aggiunte `AirportCity`, il file della mappa coincide con il backup iniziale.

## Struttura e materiali

- Città: **179 mesh visive**, **117 collisioni**, 12 materiali; ingombro circa **4,74 × 4,98 km**. Circa **1.400.932 triangoli** visivi alla risoluzione sorgente, prima dei LOD Godot. GLB: **195.827.736 byte**.
- Aeroporto conservato: 103 mesh visive, 13 materiali, 379.294 triangoli contando le istanze. GLB aggiornato: **74.186.156 byte**.
- `city_layout.json`: 42 isolati, **64 tracciati stradali**, esclusioni, landmark e **168 alberi urbani**. Questi ultimi riutilizzano la mesh forestale esistente in MultiMesh statici, senza vento né ombre proprie.
- Materiali fotografici Poly Haven CC0 già disponibili, più `brick_wall_006`: [provenienza, URL e hash](../textures/polyhaven/provenance.json). UV metriche, albedo/normal map 2K; maschere ereditate 1K, roughness del mattone 2K. Colori derivati nelle immagini `city_*_albedo.jpg`.
- Strade e pavimentazioni triangolate sulle stesse diagonali del DEM, 20 cm sopra la superficie campionata; fondazioni individuali raggiungono il terreno. Il check Blender verifica normali e distanza dal terreno su **228.990 triangoli**, inclusi i baricentri.
- `tools/import_airport_city.gd`: LOD delle superfici aderenti al terreno conservati con `lod_bias=128`, senza ombre/GI; dettagli piccoli rimossi oltre 1800 m. Il resto usa i LOD generati dall'importatore Godot. Non sono impostori/HLOD urbani aggregati.
- Proxy `-colonly`: edifici, infrastrutture e impalcati; niente collisioni per ogni finestra, lampione o albero. Non è una simulazione pedonale degli interni.

## Vegetazione

`res://scripts/maps/garda_development.gd` legge la maschera CPU compressa `garda_development.res` (1024², 7 m/texel). Sostituisce i dischi vuoti di 4 km/3,5 km di boschi ed erba con esclusioni mirate: isolati, strade, aeroporto e avvicinamenti. Lo streamer esistente torna a popolare i boschi negli interstizi; nessun nuovo sistema di popolazione runtime.

La maschera è **statica**, non segue automaticamente futuri spostamenti delle strade o degli edifici. Dopo modifiche al layout va rigenerata; i margini conservativi evitano alberi sul bordo della carreggiata ma non sono una maschera di precisione al centimetro.

## Prestazioni

Godot **4.7.1 editor binary**, RX 9070 XT, D3D12 Forward+, **1920×1080 nativo/TAA/Ultra**, VSync/limite FPS disattivati. Stesse camere e meteo congelato; attesa dello streaming, 2 s di warmup e 3 s di misura per vista. Nessun outlier eliminato. Il confronto comprende sia città sia maggiore copertura forestale, non isola il costo degli edifici.

| Vista | FPS prima → dopo | GPU mediana ms prima → dopo | p95 / massimo frame ms dopo |
|---|---:|---:|---:|
| Insieme | 265,6 → **206,9** | 3,334 → 4,198 | 5,836 / 113,567 |
| Baia | 217,8 → **183,5** | 4,077 → 4,829 | 6,659 / 6,925 |
| Quartiere | 223,3 → **180,3** | 4,096 → 4,675 | 6,576 / 116,166 |
| Rullaggio, camera fissa | 438,9 → **339,2** | 2,009 → 2,355 | 3,784 / 102,883 |

Passaggio continuo della camera sopra i quartieri, circa 2,84 km in 8 s a 200 m AGL: **199,3 FPS**, p95 **6,232 ms**, massimo **105,131 ms**. Nessun salvataggio di immagini durante questa finestra. È una misura di rendering/streaming in movimento, **non un volo pilotato**.

Viste aggiuntive: strada 186,5 FPS, lungomare 200,2, piazzale 190,3, avvicinamento 161,2. **I picchi oltre 100 ms restano un limite reale e non sono diagnosticati completamente.** Nessuna promessa di 200 FPS bloccati o certificazione release; serve profiling dedicato prima di rivendicare assenza di scatti. La riduzione dei dettagli lontani e delle ombre stradali non elimina quel problema.

[Misure prima/dopo e frame time del passaggio](previews/city/measurements.json). PNG originali e log: `subagent-artifacts/city-revision/{baseline,final,closeups}`. Le prove intermedie, soprattutto `after-second` con cache obsoleta, non rappresentano la consegna.

## Verifiche e limiti

**Passati con deadline, exit 0, marker esplicito e senza errori script/assert:**

- `tests/airport_city_check.gd`, headless e GPU: import/materiali, conteggi, landmark, collisione del viadotto, pista/corsia hangar libere, posizione nella mappa, esclusioni e buffer reali dei 168 alberi.
- `tests/airport_asset_check.gd`: geometria, materiali, dimensioni pista, aperture hangar/ricoveri e raccordi conservati.
- `tests/garda_ground_cover_check.gd`, `tools/garda_forest_review.gd`: esclusioni, determinismo, streaming, LOD, ritorno ed eviction.
- `tools/check_garda_roads.gd`: strade preesistenti, collisioni, raccordi T/X e assenza di scritture altimetriche nel controllo.
- `tests/hangar_departure_check.gd`, `tests/tutorial_mission_check.gd`: partenza, quattro marker del percorso a terra, volo e regressioni della missione. Nei test aggiornati: marker compatibili col runner, caricamento differito delle risorse native e rilascio degli stream audio al termine; nessuna modifica al gameplay.
- Catture finali esaminate: insieme, baia, quartieri, strada, lungomare, piazzale, rullaggio e avvicinamento. Passaggio basso e confronto dei rilievi iniziale/finale completati.
- Mappa aperta, freeroam e tutorial avviati via **Godot AI MCP, `autosave=false`**, confermati `live`; log correnti e log editor controllati. Breve prova di input/rullaggio nel tutorial, oltre al percorso automatizzato. Avvio pulito non equivale a certificazione completa del volo/atterraggio.

**Non passato:** `tests/garda_final_import_check.gd` confronta tutte le altezze con l'import geografico originario e fallisce sull'hash di `terrain3d-03-01.res`. Fallisce allo stesso punto caricando la mappa dal backup pre-città. Il rilievo locale prima/dopo è identico: non ho annullato gli sculpt preesistenti per far passare questo controllo storico. Il runner riconosce correttamente il fallimento nonostante il marker stampato dal test dopo l'assert.

Rimangono warning preesistenti dei due UID texture FA-N26, interpolazione deprecata e connessioni del road-generator nell'editor. Il controller del confine segnala l'assenza di player nelle catture statiche; quelle viste non sono scene giocabili. Nessun nuovo errore parse/load/runtime nelle sessioni MCP finali.

La composizione e le facciate restano modulari; gli incroci hanno raccordi geometrici semplici. Non è una ricostruzione fotogrammetrica o una città esplorabile stanza per stanza. Nessun traffico, NPC, movimento delle turbine o passata notturna aggiunti.

## Manutenzione / riproduzione

`build_city.py` ricostruisce **e sostituisce `city_authored`**: non eseguirlo sopra modifiche manuali non salvate. Richiede `airport.blend` aperto, la struttura/materiali aeroportuali esistenti e il rilievo in `subagent-artifacts/city-revision/survey/site.json`. Per rigenerare il rilievo usare il primo comando sotto; non occorre ricostruire la città per utilizzarla.

1. Salvare un backup del sorgente, poi eseguire il generatore in Blender (namespace mantenuto in `bpy.app.driver_namespace['city_author']`). `export()` valida le superfici, salva sorgente, due GLB e manifest. Terreno/acqua di anteprima sono esclusi dagli export.
2. In Godot eseguire scansione filesystem/reimport. **Verificare anche `source_md5` in `.godot/imported/*.md5`**: un precedente reimport MCP aveva risposto positivamente con cache ancora vecchia.
3. Eseguire `prepare_airport_city.gd` **con renderer grafico, non `--headless`**: il renderer dummy non conserva i buffer MultiMesh serializzati. Il tool protegge questa condizione con un assert; scrive solo maschera e contenitore città.
4. Rilanciare regressione e catture. Non spostare l'aeroporto senza aggiornare origine, maschera e layout.

```text
node tools/run_godot_check.cjs 60 survey.log GODOT --headless --path . --script res://tools/city_review.gd -- --survey --out=res://subagent-artifacts/city-revision/survey
node tools/run_godot_check.cjs 90 prepare.log GODOT --path . --script res://tools/prepare_airport_city.gd
node tools/run_godot_check.cjs 80 city.log GODOT --path . --script res://tests/airport_city_check.gd
node tools/run_godot_check.cjs 180 review.log GODOT --path . --script res://tools/city_review.gd -- --motion --out=res://subagent-artifacts/city-revision/new-review
node tools/run_godot_check.cjs 160 closeups.log GODOT --path . --script res://tools/city_review.gd -- --closeups --out=res://subagent-artifacts/city-revision/new-closeups
```

Backup iniziali, diff originale e sessioni Blender/editor precedenti conservati sotto `subagent-artifacts/city-revision/before/` (ignorato da Git). Non usare vecchie ricette aeroportuali per rigenerare la città.

I rilievi e le misure sopra documentano la consegna della città prima dell'ultimo salvataggio manuale di scena e terreno. In preparazione dei commit sono stati conservati anche questi aggiornamenti, senza ripristinare il terreno; i controlli headless di città e strade sono stati rieseguiti con esito positivo. I GLB aeroportuali sono versionati con Git LFS, come già i sorgenti Blender e le regioni Terrain3D.
