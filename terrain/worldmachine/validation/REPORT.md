# Benchmark World Machine → Terrain3D: Valtellina

## Esito

**Mapping geograficamente allineato dopo la correzione dell'origine UV.** Verificato eseguendo Godot con rendering Vulkan Forward+ e ispezionando gli screenshot reali, non soltanto compilando lo shader. Nessun flip X/V e nessuna rotazione necessari.

Non è una certificazione di precisione sub-pixel: la colormap fornita è 1025×1025 (circa 29,3 m/texel), mentre il terreno è campionato ogni 5 m. La coincidenza visiva di valle, impluvi e cime è verificata alla risoluzione della PNG; non si può promettere precisione di 5 m per i dettagli del colore.

## Problema trovato e correzione

I metadati dichiarano import_position = (-15000, 0, -15000), ma le quote effettive Terrain3D corrispondono alla R16 con origine **(-15360, -15360)**: scarto di -360 m sia in X sia in Z. L'origine effettiva è sul confine delle regioni da 256×5 = 1280 m (-12 regioni). I metadati originali non sono stati modificati.

Con le coordinate nominali, 225 confronti Terrain3D/R16 danno un errore verticale massimo di 613,664 m. La ricerca dello scarto su campioni esportati dal Terrain3D identifica esattamente +72 pixel R16 in entrambi gli assi per risalire dalla posizione nominale al campione corretto. Dopo la correzione, gli stessi 225 confronti danno errore massimo **0,000202 m**. Questa misura verifica l'origine della heightmap esistente, non la precisione semantica del colore.

UV finali:

```glsl
vec2 global_uv = (v_vertex.xz + vec2(15360.0)) / 30000.0;
```

Estensione effettiva X/Z: **-15360 → +14640 m**, 30×30 km, centro (-360, -360). Usare invece -15000 → +15000 produrrebbe una traslazione della colormap rispetto al terreno reale. Nessuna traslazione del nodo o modifica delle altezze è stata effettuata.

## Tecnica/API verificata

- Addon rilevato a runtime: **Terrain3D 1.0.2**; Godot **4.7.2**.
- Proprietà/metodi confermati con ClassDB: `shader_override`, `shader_override_enabled`, `set_shader_param`, `get_shader_param`, `set_camera`, `data.get_height`.
- Copia dello shader `addons/terrain_3d/extras/shaders/minimum.gdshader` dell'addon installato; vertex displacement, geomorph e normali del terreno invariati. Modificati soltanto uniform pubblici e albedo finale.
- Texture unica world-space con `source_color`, filtro lineare/mipmap anisotropico e `repeat_disable`; bypass completo del blending PBR originale.
- Materiale nuovo locale alla scena di test; assets originali solo referenziati. Background disabilitato; fragment fuori dall'estensione della colormap scartati per non mostrare il padding delle regioni. Nessun ritaglio o salvataggio dei dati.
- `mesh_lods = 10` consente la copertura della vista generale; vertex_spacing resta 5.0.

## Verifica visiva

| Screenshot | Osservazione |
| --- | --- |
| [Vista generale](01_overview_color.png) / [geometria](01_overview_geometry.png) | Fondovalle verde coincidente con la depressione principale; diramazioni coerenti, neve sui rilievi. |
| [Fondovalle](02_valley_color.png) / [geometria](02_valley_geometry.png) | Verde sul fondo della valle, pareti grigie sui fianchi; nessuna traslazione evidente dopo la correzione. |
| [Versante](03_slope_color.png) / [geometria](03_slope_geometry.png) | Roccia sui versanti, verde negli impluvi, neve sulle creste alte sullo sfondo. |
| [Alta quota](04_summit_color.png) / [geometria](04_summit_geometry.png) | Neve sulle cime e creste del massiccio del Disgrazia, non sul fondovalle principale. |
| [Vista generale unlit](01_overview_unlit.png) | Intera PNG una sola volta, nord in alto (-Z), est a destra (+X), nessuna rotazione/specchiatura/tiling. |
| [Confronto colore/geometria](comparison.png) | Affiancamento delle tre viste prospettiche, esaminate anche a piena risoluzione. |

Nessun seam evidente della colormap nei campioni osservati. La proiezione XZ è uniforme e continua tra regioni; su pareti ripide resta l'allungamento intrinseco di una proiezione planare, non un difetto UV correggibile mantenendo questo tipo di mapping. Da vicino il colore è sfocato per la bassa risoluzione della PNG. Alcune striature del rilievo compaiono anche negli screenshot geometry-only: non sono seam della colormap. Il grigio della PNG ricopre anche aree non ripide: il test non certifica la classificazione fisica dei materiali.

`before/` conserva la prima prova con UV nominali e origine errata. Una successiva vista fondovalle aveva la camera dentro il versante: posizione corretta e screenshot rigenerati; il test finale verifica che ogni camera sia sopra il terreno. Nessuna correzione artistica applicata.

## File creati

- `scenes/real_terrain_valtellina_worldmachine_test.tscn`
- `scripts/valtellina_worldmachine_test.gd`
- `terrain/worldmachine/valtellina_worldmachine_test.gdshader`
- Questa directory `validation/`: screenshot finali e prima prova, confronto, log Godot, campioni quote CSV, checksum e report; `.gdignore` evita di importare le prove come asset del gioco.

La PNG e il suo `.import` erano già presenti e non sono stati modificati. Nessun file preesistente del progetto modificato. Verifica SHA-256 pre/post: **579 file invariati**, comprendenti tutte le 576 regioni, la R16, gli assets e la scena textured originale. `git diff` vuoto; i file preesistenti non tracciati sono rimasti intatti.

## Ripetere il test

Dalla root del progetto, con display grafico disponibile:

```bash
/home/marco-ubuntu/Workspace/godot/Godot_v4.7.2-stable_linux.x86_64 \
  --path . --resolution 1400x1000 \
  scenes/real_terrain_valtellina_worldmachine_test.tscn -- --capture-wm
sha256sum -c terrain/worldmachine/validation/protected.sha256
```

Il flag rigenera i nove screenshot finali e il CSV, verifica 225 quote e termina. Senza flag la scena resta aperta: **1–4** viste, **G** geometria grigia, **U** colore senza illuminazione, **Esc** uscita. Nessun cambio alla main scene del progetto.

Log finale: nessun errore shader/GDScript; restano warning di driver RADV, deprecazione dell'interpolazione fisica e un messaggio della configurazione esterna MangoHud. Non hanno impedito rendering, screenshot o verifiche.
