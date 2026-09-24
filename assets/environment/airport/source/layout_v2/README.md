# Aero Demons — aeroporto principale, layout V2

## Consegna

- `main_airport_layout.blend`: sorgente Blender 5.2, scena `AERO_DEMONS_LAYOUT_V2` (metri; Z verso l'alto).
- `../../main_airport_layout.glb`: infrastrutture e 23 edifici ancora in blockout. Non contiene copie statiche dei piccoli hangar.
- `res://scenes/maps/main_airport_layout.tscn`: aeroporto completo in Godot; istanzia il GLB e tre copie di `res://scenes/maps/small_hangar.tscn`, con porte animate e collisioni indipendenti.
- `res://scenes/preview/main_airport_layout_preview.tscn`: anteprima navigabile; WASD/mouse, Q/E quota, Shift velocità, Esc.
- `11_n26_hangars_row.png`, `12_n26_hangar_entry_open.png`: render finali della fila e di un portale aperto.

Non sostituisce `airport.blend`, gli asset della città o la mappa esistente. Il sorgente del piccolo hangar (`../../../small_hangar/source/small_hangar.blend`) e il suo GLB restano a scala nativa: la scala 1,5× è applicata **solo alle tre istanze dell'aeroporto**, sia in Blender sia in Godot.

## Geometria

Pista **2400 × 60 m**, taxiway **23 m** a interasse **180 m**, strade di servizio **9 m**, raccordi e due apron modulari da 200 m con marcature. 26 edifici erano inizialmente blockout cromatici: tre arancioni sono ora hangar completi; gli altri 23 restano volumi. Collezioni separate `RUNWAY`, `TAXIWAYS`, `ROADS`, `APRONS`, `BUILDING_BLOCKOUTS`, `INDUSTRIAL_BLOCKOUTS`, `RADAR_BLOCKOUTS`, `MARKINGS`, `UTILITIES`, `COLLISIONS`, più `BUILDING_ASSETS` e le raccolte di presentazione non esportate. Le texture dell'infrastruttura riusano fonti CC0 del progetto (`../DELIVERY.md`, `../../textures/polyhaven/provenance.json`).

Un unico proxy invisibile `Pavement_collision-colonly` (4099 triangoli) evita giunti fisici tra le superfici visive; ciascun blockout restante usa `-col`. Godot importa **134 mesh e 57 collider** nella scena composta. Infrastruttura: **62.065 triangoli visibili**; tre istanze hangar da 37.620 ciascuna: totale **174.925**. Non sono modellati interni per gli altri edifici.

### Hangar per N26

I piazzamenti sono in `asset_placements.json`: centri Blender **(-365,54, -170 / -65 / 40, 0) m**, Z +90°, ingressi verso +X sulla linea **X = -347 m** (in Godot coordinate `(X,Z,-Y)` e rotazione Y +90°). Le tre istanze hanno scala uniforme **1,5×**. Fondazione **37,05 × 42,75 m**; l'apron visivo e i giunti sono ritagliati sulla fondazione, lasciando integro il collider continuo sottostante. Pavimento a quota zero.

Portale aperto: **17,4 m** di larghezza, circa **7,32 m** di altezza; l'N26 importato misura **14,0784 × 4,744 × 20,7585 m** (larghezza × altezza × lunghezza). Margine orizzontale **1,66 m per estremità alare**; profondità interna circa **36 m**. Dimensioni e collider della porta verificati, ma **non** è stata simulata una manovra di rullaggio con l'aereo effettivo. Non usare l'hangar nativo senza scala per l'N26.

## Riproduzione

1. `uv run --with shapely==2.1.2 --with pillow python assets/environment/airport/source/layout_v2/build_geometry.py` genera `geometry.json` e le tre texture base.
2. In una scena Blender nuova, eseguire `author_blender.py` come `__main__`, quindi `place_small_hangars.py`. Quest'ultimo importa la collection dall'asset esistente e crea `asset_placements.json`; rifiuta istanze duplicate.
3. Rigenerare `build_geometry.py` **dopo** i piazzamenti (per ritagliare l'apron sulla loro impronta), richiamare `author_blender.refresh_surfaces()` e poi eseguire `deliver_blender.py` nella scena aperta. Non rigenerare sopra ritocchi Blender non riportati negli script.
4. Eseguire uno scan completo del filesystem Godot dopo l'export. Per verificare l'import già esistente: `node tools/run_godot_check.cjs 35 /tmp/airport-check.log /percorso/a/godot --headless --path . --script tests/main_airport_layout_check.gd`.

Ultimo controllo effettuato: `AIRPORT_PLAN_CHECK_OK`, `AIRPORT_BLENDER_CHECK_OK`, controllo Godot preesistente PASS/exit 0 (1476 campioni continuità pavimentazione); preview lanciata con MCP `autosave=false`, stato live e log game/editor senza errori, poi fermata. Caratteristiche visive valutate sui due render finali. Atterraggi, rullaggio N26 reale, allineamento alla quota del terreno Garda, traffico AI e prestazioni di una missione completa non sono stati collaudati.
