# Aero Demons — aeroporto militare, revisione ravvicinata

> Documento della revisione precedente dell'aeroporto. Il sorgente comprende ora
> anche la città: [consegna e verifiche correnti](CITY_DELIVERY.md).
> Ingombri e geometria aeroportuali restano invariati; asfalto ed export sono aggiornati.

## Consegna

- `../airport_layout.glb`: aeroporto assemblato, componenti separati sotto `airport_root`.
- `airport.blend`: sorgente Blender 5.2, scena `airport_authoring`, texture relative in `../textures/polyhaven/`.
- `scenes/maps/airport.tscn` dalla radice repository: contenitore Godot, collisioni statiche e marker stradale.
- `previews/top.png`, `previews/perspective.png`, `previews/hangar_close.png`: immagini aggiornate del runtime Godot.
- `previews/closeup/godot_contact_sheet.jpg` e dieci `godot_*.png`: verifica per edificio, portale e interno hangar.
- `previews/glb_reimport.png`: render del GLB finale realmente reimportato in una scena Blender distinta.
- Gli altri render `*_review.png` sono documentazione intermedia, non immagini della consegna finale.

Nessuna modifica a Garda, Terrain3D, World Creator, posizionamento definitivo o logica di gioco. Piano verde, camere e luci di presentazione non sono nel GLB.

## Scala e geometria

Metri, Blender Z verticale, pista lungo Y, origine al centro pista. Conversione glTF standard `(X,Y,Z)` → `(X,Z,-Y)` Godot, contenitore a identità.

Pista unica **2.400 × 60 m**. Ingombro verificato del reimport: **1.115 × 2.400 × 76,7 m** in Blender.

- **Hangar:** circa 178 × 352 m, tre campate, portale centrale aperto, ante scorrevoli articolate geometricamente, capriate ripetute, colonne, telai, lucernari traslucidi, finestre laterali, griglie, pluviali e accessi di servizio. Riutilizzata la geometria delle capriate dalla libreria fornita `military_hangar_large.blend`, senza modificare l'originale né scalare indiscriminatamente l'intero edificio.
- **Quattro ricoveri:** gusci e dettagli condivisi, ingressi aperti, bordi, nervature, fondali e accessi tecnici; UV cilindriche metriche sul rivestimento.
- **Complesso tecnico:** volumi conservati, telai, davanzali, partizioni verticali, parapetti, HVAC, tubazioni e scala.
- **Operations, workshop ed equipment:** facciate, porte, serrande, copertine, accessi e impianti; pivot alla base, muri appoggiati alla pavimentazione.
- **Due torri:** tralicci, controventi, piattaforme, parapetti, scale e antenne; prima torre sul tetto equipment.
- **Cupola:** guscio curvo, giunti dei pannelli, basamento e vestibolo tecnico.
- Pavimentazione con giunti da 6 m, segnaletica e raccordi della planimetria conservati.

## Materiali e budget

**103 oggetti mesh, 82 mesh uniche, 379.294 triangoli contando le istanze, 13 materiali, 28 immagini incorporate; 77.477.692 byte di GLB.** Dati in `export_stats.json`.

Texture reali Poly Haven CC0: `concrete_floor_01`, `concrete_floor_02`, `concrete`, `corrugated_iron_02`, `painted_metal_shutter`, `metal_plate`, `asphalt_floor`. Provenienza, URL e hash in `../textures/polyhaven/provenance.json`; licenza: https://polyhaven.com/license.

Tutte le superfici esportate hanno albedo, normal map OpenGL e roughness/metalness PBR. Albedo e normal map a **2K**, maschere scalari esportate a **1K**; gradazioni del colore cotte in JPEG qualità 95, maschere PNG. Nessun materiale procedurale richiesto a runtime. Tangenti presenti su tutte le primitive. I piccoli dettagli non ricevono smussi geometrici costosi: ottimizzazione da circa 1,94 milioni di triangoli a 379 mila, senza eliminare telai e impianti.

Godot estrae le immagini accanto al GLB: conservarle con i relativi `.import`. `textures/polyhaven/.gdignore` evita di importare anche le copie sorgente inutilizzate dal runtime.

## Collisioni

Pavimentazione continua e proxy separati per pareti e coperture; ingressi hangar/ricoveri non chiusi da volumi convessi. Aggiornati gusci, cupola, colonne interne e piattaforme. La corsia centrale rimane aperta. Dettagli minuti, scale, antenne e impianti non hanno collisioni individuali; i proxy non sono una simulazione pedonale precisa.

Le collisioni appartengono al contenitore Godot: cambiando gli ingombri nel sorgente occorre aggiornarle. Nessuna prova di atterraggio o collisione aeronautica ad alta velocità è stata eseguita.

## Verifiche

- Controllo Blender: UV presenti, nessuna faccia degenere, file immagine risolti; GLB con una sola radice, senza camere/luci, mappe PBR e tangenti su tutte le primitive.
- Reimport Blender effettivo: **103 mesh**, scala e ingombro verificati; render esaminato (`glb_reimport_check.json`).
- Godot 4.7.1 headless, deadline 60 s: **exit 0**, marker `AIRPORT_ASSET_CHECK_OK`, nessun errore o warning nel log finale. Verifica materiali, geometria condivisa, basi a terra, dimensioni pista, raccordi, aperture, colonna e cupola. Log: `headless_check.log`.
- Contenitore aperto tramite Godot AI MCP. Preview lanciata con `autosave=false`, stato **live**; dieci viste runtime esaminate, log della sessione finale pulito, nessun nuovo errore editor dopo cursore 7. Esecuzione fermata.
- Il primo controllo headless esponeva un leak dell'autoplay musicale del progetto: il test ora ferma soltanto l'audio del proprio processo, senza cambiare AudioManager.
- Un warning Blender riguarda il sampler condiviso fra immagini roughness/metalness; il GLB e i materiali importati sono stati verificati. Le precedenti segnalazioni di tangenti mancanti sono state risolte triangolando i soli poligoni con più di quattro vertici.

## Limiti e manutenzione

Quote edilizie interpretative, non fotogrammetria. Gli interni completi riguardano gli spazi aperti di hangar/ricoveri; fabbricati tecnici e di servizio restano involucri con dettagli esterni. L'illuminazione delle immagini è di presentazione, non il look finale di Garda; prestazioni nel volo, LOD a distanza e illuminazione definitiva restano da valutare dopo il posizionamento.

Le ricette `build_airport.py`, `finish_airport.py`, `prepare_delivery.py` documentano la precedente versione. `closeup_authoring.py`, `closeup_buildings.py`, `closeup_delivery.py` documentano la revisione eseguita tramite MCP nello stesso namespace Blender. Non sono necessarie per usare l'asset e non sono un comando di rigenerazione autonomo: dipendono dagli stadi precedenti e dalla libreria delle capriate. Non lanciarle sopra modifiche manuali non salvate.

Controllo da eseguire dalla radice repository, con una deadline esterna:

`Godot_v4.7.1-stable_win64.exe --headless --path . --script tests/airport_asset_check.gd`
