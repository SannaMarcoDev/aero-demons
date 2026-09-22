# Città aeroportuale — catalogo approvato e strade Godot

## Consegna

Aprire `res://scenes/maps/garda_final.tscn`; la città è l'istanza **AirportCity**.
La scena modificabile è `res://scenes/maps/airport_city.tscn`, condivisa da tutorial e freeroam.

- **182 edifici**, distribuiti nei quattro quartieri/42 isolati e nelle aree civiche, logistiche e della baia.
- **13 modelli urbani:** i dieci approvati più tre edifici standard estratti dalla città precedente (`standard_1/2/3.glb`). I tre standard sono riutilizzati come edilizia ordinaria, non come ulteriori torri.
- Skyline: residenza terrazzata da circa 107 m, torri collegate da 116/91 m, torre con corona obliqua da 132 m.
- Separati dal conteggio: torre di controllo da 70 m, parabola nominale Ø70 m e due Ø45 m. Le parabole hanno elevazioni di 55°, 75° e 35°, riflettori pieni concavi e supporti pesanti.
- **187 segmenti e 84 incroci RoadManager**, ricavati dai 64 tracciati del sito, con rete connessa, collegamento nativo alla strada utente e carreggiate del viadotto generate da Godot. Nessuna nuova strada Blender.
- Conservati sei aerogeneratori immobili, traliccio telecom, quattro serbatoi, banchina, tre pontili e sottostrutture del viadotto.
- Rimossi auto, arredi stradali, micro-props separati e tutti i **168 alberi dei cortili**. Restano boschi e vegetazione naturale del sistema esistente.

I dodici GLB della biblioteca approvata sono invariati byte per byte. Sono invariati anche `airport_layout.glb`, `airport.blend`, `airport_city.glb` storico, `airport.tscn`, **l'intero `garda_final.tscn`** e tutte le regioni Terrain3D: verificati tramite SHA-256 contro lo stato iniziale. Pista **2400 × 60 m**, hangar, costa e quote non sono stati rimodellati. Il vecchio GLB città rimane come sorgente storico, ma non viene più istanziato.

## File e authoring

- `build_library.py` / `airport_asset_library.blend`: i dieci edifici e i due landmark originariamente approvati; la funzione della parabola accetta ora l'inclinazione senza alterare il modello predefinito.
- `rebuild_city.py` / `airport_city_retained.blend`: tre edifici originali, infrastrutture mantenute, due parabole da 45 m. Legge gli oggetti originali senza salvare `airport.blend`. Esporta soltanto questi nuovi GLB e il manifest.
- `city_layout.json`: istanze, quote/fondazioni, catalogo, tracciati, grafo connesso ed esclusioni. Tracciati e isolati sono anche l'input conservato per le rigenerazioni successive.
- `tools/prepare_airport_city.gd`: scrive scena Godot ed esclusione vegetazione; può funzionare **headless**, non essendoci più MultiMesh urbani da serializzare.
- `scripts/maps/airport_city.gd`: collega il conformer al Terrain3D della mappa e il terminale della nuova rete al `WestEnd` esistente, senza sostituire eventuali connessioni dell'utente.
- `RoadManager/Ground`: strade proiettate sulle triangolazioni del DEM, separazione 20 cm. `RoadManager/Elevated`: viadotto e rampe a quota progettata, esclusi dalla proiezione. `flatten_terrain=false` ovunque.
- Collisioni concave condivise per modello: corti, loggiati, ponti tra torri e parabole non diventano scatole piene. Fondazioni solide individuali raggiungono il terreno; il viadotto mantiene le collisioni native RoadGenerator.

Materiali del catalogo e texture Poly Haven CC0 già disponibili; provenienza in `../textures/polyhaven/provenance.json`. Le 186 istanze architettoniche/landmark sommano **1.286.168 triangoli sorgente**, esclusi fondazioni, infrastrutture conservate e strade. Non sono 186 mesh uniche: i GLB e le forme di collisione sono condivisi.

## Verifica

Log e PNG effettivi: `subagent-artifacts/city-rebuild/`. Backup e hash protetti: `before/`. Panoramiche in `final/`, viste ravvicinate in `closeups/`.

- `tests/airport_city_check.gd`: catalogo completo, assenza di alberi urbani/vecchie carreggiate Blender, grafo interamente connesso, geometria/UV/collisioni stradali, area conservata dalla proiezione, collegamento nativo alla rete utente, viadotto a quota 204 m, pista/hangar liberi, esclusioni e terreno non scritto.
- `tests/airport_asset_check.gd`: dimensioni pista, geometria, materiali e aperture aeroportuali conservati.
- `tests/airport_asset_library_check.gd`: biblioteca approvata ancora valida e navigabile.
- `tools/check_garda_roads.gd`: regressione della rete preesistente, spline, incroci, collisioni e segnali di sculpt. Il test sposta intenzionalmente solo metà del nuovo collegamento fra container: i warning di disallineamento durante questa prova non sono presenti nell'avvio normale. Dopo spostamenti manuali usare lo snap nativo per riallineare i terminali collegati.
- Scena città aperta tramite Godot AI MCP; tutorial e freeroam avviati con `autosave=false`, entrambi confermati `live`, senza nuovi errori nei log del run o dell'editor. Nel tutorial verificato anche il movimento a terra tramite input (circa 8,6 m). Run terminati dopo le prove.

Ultima acquisizione della rete finale, **1920 × 1080, Forward+/D3D12, RX 9070 XT**, editor aperto: panoramica 178 FPS, baia 159, quartiere 159, taxi 234. Passaggio camera a bassa quota: **171 FPS medi**, p95 **6,925 ms**, massimo **7,593 ms**. Sono misure di questa acquisizione, non confronti controllati con le revisioni precedenti.

Rimangono gli avvisi preesistenti di interpolazione deprecata e dell'editor RoadGenerator. Le catture statiche segnalano correttamente l'assenza di un player. Il vecchio `garda_final_import_check.gd` confronta invece il terreno con l'import geografico originario: non viene usato per annullare gli sculpt manuali preesistenti.

## Limiti

- Esterni, non interni arredati; nessun traffico, NPC o animazione delle turbine.
- La maschera vegetazione è statica: rigenerarla dopo modifiche al layout. I margini evitano tronchi sulle strade, non garantiscono l'assenza di ogni chioma sporgente.
- LOD automatici disabilitati sui modelli approvati, sulle parabole e sulle infrastrutture conservate per evitare danni alle superfici sottili. I tre standard mantengono i LOD importati. Nessun sistema HLOD aggiunto.
- I LOD del DEM a parecchi chilometri possono ancora nascondere piccoli lembi stradali; non è stato modificato il terreno né applicato un materiale che disegni attraverso le colline.
- I benchmark delle catture sono misure brevi di rendering/streaming, non una certificazione di frame rate o del gameplay completo.

## Rigenerazione

Fare backup delle modifiche manuali prima di rigenerare scena o sorgenti. **Non usare `build_city.py` storico:** ricostruisce la vecchia città con carreggiate Blender e modifica anche l'export aeroportuale.

1. Rilievo read-only con il comando sotto.
2. Aprire l'originale `airport.blend` in Blender ed eseguire `runpy.run_path(path_di_rebuild_city_py, run_name='__main__')`. Non salva l'originale. La biblioteca approvata deve essere già disponibile.
3. Scansione filesystem/reimport Godot; attendere gli import e verificare i `source_md5` delle cache.
4. Preparare la scena e rieseguire test/catture.

```text
node tools/run_godot_check.cjs 60 survey.log GODOT --headless --path . --script res://tools/city_review.gd -- --survey --out=res://subagent-artifacts/city-rebuild/survey
node tools/run_godot_check.cjs 60 prepare.log GODOT --headless --path . --script res://tools/prepare_airport_city.gd
node tools/run_godot_check.cjs 100 city.log GODOT --headless --path . --script res://tests/airport_city_check.gd
node tools/run_godot_check.cjs 140 review.log GODOT --path . --script res://tools/city_review.gd -- --motion --out=res://subagent-artifacts/city-rebuild/final
node tools/run_godot_check.cjs 160 closeups.log GODOT --path . --script res://tools/city_review.gd -- --catalog --out=res://subagent-artifacts/city-rebuild/closeups
```
