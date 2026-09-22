# Biblioteca aeroportuale — dieci edifici e strutture speciali

Aprire **`res://scenes/preview/airport_asset_library.tscn`** e premere **F6**.
La scena di esposizione è indipendente: aprirla non modifica la città, l'aeroporto o il terreno.

- **← / →:** scorrono tutti i 13 elementi (dieci edifici, due strutture, incrocio), con ritorno circolare alla panoramica.
- **1–9:** accesso rapido ai primi nove edifici; **0 / Home:** panoramica.
- **WASD + mouse:** camera libera; **Q/E:** quota; **Shift:** movimento veloce.
- **Esc:** libera il mouse; clic per riprenderlo; un secondo Esc chiude la scena.
- Viste a circa **174 m**, oppure **260 m** per i tre complessi alti. Piazzole e cartigli appartengono soltanto all'esposizione.

## Catalogo: quattro residenziali + sei funzionali

Ogni riga è un GLB diverso, non una variante di scala o colore. Le torri direzionali collegate costituiscono un unico complesso a due ali.

| N. | Edificio | GLB | Triangoli | Altezza circa |
|---|---|---|---:|---:|
| 01 | Palazzina a falde | `residence_gabled.glb` | 4.992 | 17 m |
| 02 | Residenza a corte | `residence_courtyard.glb` | 14.964 | 25 m |
| 03 | Residenza a L, ali diseguali e loggiato interno | `residence_l.glb` | 10.752 | 32 m |
| 04 | Torre residenziale, quattro arretramenti e terrazze | `residence_terraced.glb` | 4.104 | 107 m |
| 05 | Capannone a shed | `industrial_shed.glb` | 2.052 | 14 m |
| 06 | Torri direzionali collegate da ponte sospeso | `offices_twins.glb` | 3.240 | 116 / 91 m |
| 07 | Torre rastremata, corona obliqua e controventi diagonali | `office_spire.glb` | 2.180 | 132 m |
| 08 | Centro ricerca a gradoni | `research_center.glb` | 10.296 | 37 m |
| 09 | Centro civico con grande copertura piegata | `civic_canopy.glb` | 394 | 29 m |
| 10 | Deposito a grande luce con volta nervata | `warehouse_vault.glb` | 1.946 | 21 m |

**54.920 triangoli** per i dieci edifici.

Fuori dal conteggio: **11**, torre di controllo da 70 m (940 triangoli); **12**, parabola da 70 m (9.592 triangoli); **13**, incrocio RoadManager con quattro bracci modificabili e raccordo curvo.
Totale dei dodici modelli: **65.452 triangoli**, esclusi esposizione e strade. Non è un benchmark della città completa.

GLB individuali, scala metrica, origine a terra. Niente auto, arredo o alberi ornamentali.
I cinque GLB del primo campione approvato sono rimasti identici byte per byte.
I materiali riutilizzano intonaco, metalli, vetro opaco riflettente e il mattone Poly Haven CC0 a 1K, documentato in `../textures/polyhaven/provenance.json`.

## Limiti della consegna

Il catalogo è ora integrato nella città: vedere `../source/CITY_DELIVERY.md`.
Alla libreria si aggiungono `standard_1/2/3.glb`, estratti dai vecchi edifici, e `satellite_dish_45m_15.glb` / `satellite_dish_45m_55.glb`. Questi cinque asset non cambiano l'esposizione dei dieci edifici approvati e sono visibili nella città.
I GLB sono esterni visivi; la scena città aggiunge collisioni condivise per modello. RoadManager mantiene le proprie collisioni native.
I LOD automatici sono disabilitati nei dodici import della biblioteca: la decimazione della parabola produceva intersezioni tra le due superfici nella panoramica. Nessun GLB approvato è stato rimodellato.
Le verifiche della città e i relativi limiti sono documentati nella consegna integrata; questa esposizione non è un benchmark della mappa.
L'incrocio espositivo rimane invariato. Nella città la rete RoadManager segue il terreno e comprende anche il viadotto, senza modificare il DEM.

## Sorgente e verifiche

Sorgente separato: `../source/airport_asset_library.blend`, scena `AirportAssetLibrary`, con dodici oggetti disposti separatamente.
Ricetta: `../source/build_library.py`; in Blender `runpy.run_path(path, run_name='__main__')` rigenera l'intera biblioteca.
Per esportare solo modelli scelti: `ns = runpy.run_path(path); ns['build'](export_names={'civic_canopy'})`.
La selezione limita gli export GLB; scena sorgente e metriche vengono ricostruite. Fare backup prima di rigenerare eventuali ritocchi manuali.
Dopo l'export eseguire la scansione filesystem/reimport in Godot e verificare i `source_md5` della cache.

```text
node tools/run_godot_check.cjs 45 subagent-artifacts/catalog-expansion/check.log GODOT --headless --path . --script res://tests/airport_asset_library_check.gd
node tools/run_godot_check.cjs 110 subagent-artifacts/catalog-expansion/capture.log GODOT --path . --script res://tests/airport_asset_library_check.gd -- --capture
```

Passati entrambi: dodici import distinti, conteggi, dimensioni, normali finite, geometria delle strade e rigenerazione spline, quattordici preset, navigazione oltre il nono elemento e ritorno circolare.
Catture reali esaminate in `subagent-artifacts/catalog-expansion/review/`, inclusi prospettive, planimetria e retro della parabola.
Avvio MCP con `autosave=false`: stato `live`, scorciatoie e selezione degli elementi 10–13 verificate, nessun nuovo errore nei log del run/editor.
L'esposizione rimane separata; tutti i modelli approvati sono ora istanziati nella città senza alterare i dodici GLB originali.
