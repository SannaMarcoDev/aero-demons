# Garda broadleaf — sorgenti e ricostruzione

Mesh generata per Aero Demons in Blender 5.2 tramite Blender MCP e
`tools/build_garda_tree.py`; nessuna mesh di albero di terzi riutilizzata.
Un solo modello, tre LOD espliciti (4.752 / 580 / 6 triangoli), una superficie
per LOD, normali personalizzate, UV e colori vertex `TreeTint`.
Il LOD lontano comprende due proiezioni laterali e una vista dall'alto.

## Texture di terzi: CC0

- **Leafy tree/plant branch**, qubodup, da una fotografia di **titus**.
  [Pagina e licenza CC0](https://opengameart.org/content/leafy-treeplant-branch).
  File: <https://opengameart.org/sites/default/files/branchleaves.png>.
  SHA-256: `8384de5b478e8478405e1ebc7e7b23a4bfb428310048034d7109f5b217cd4273`.
- **Bark Brown 02**, **Rob Tuytel**, Poly Haven.
  [Asset](https://polyhaven.com/a/bark_brown_02), [licenza CC0](https://polyhaven.com/license).
  File: <https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/bark_brown_02/bark_brown_02_diff_1k.jpg>.
  SHA-256: `920fa0bed0c9d78c1d530e99795113afd532d7db746de440f4a85d7c83ed0f1a`.

CC0 permette anche uso commerciale e redistribuzione delle texture modificate.
I crediti sono mantenuti per tracciabilità. La licenza degli asset Poly Haven
non va confusa con quella del sito/API. Non sono stati inclusi i modelli
alternativi CC-BY-SA/GPL esaminati durante la ricerca.

## Atlas 2048 × 2048

Coordinate in pixel dall'angolo superiore sinistro:

| Contenuto | X, Y | Dimensioni |
|---|---|---|
| Ramo fotografico | 0, 0 | 1536 × 394 |
| Corteccia | 1792, 0 | 256 × 512 |
| Proiezione frontale | 0, 512 | 1024 × 1024 |
| Proiezione laterale | 1024, 512 | 1024 × 1024 |
| Proiezione superiore | 0, 1536 | 512 × 512 |

Ramo: luminosità ×1,65, saturazione ×0,8 **prima** del ridimensionamento
Lanczos; alpha originale preservato. Le proiezioni sono bake di albedo EEVEE,
non immagini con luce/ombre già incorporate. RGB sotto alpha 128 inizialmente
azzerato, otto passaggi MaxFilter 3×3 nei texel sotto alpha 128; infine gli RGB
sotto alpha 128 nei riquadri del fogliame vengono riempiti con la media dei
texel con alpha >224. L'alpha non cambia. Questo evita mip lontani neri.

`tools/pack_garda_tree_atlas.py` conserva questa preparazione. La ricostruzione
con i tre bake finali è stata confrontata pixel per pixel con l'atlas consegnato:
uguaglianza completa RGBA. Con sorgenti e bake presenti, ripetere il controllo
senza sovrascrivere l'asset con `python tools/pack_garda_tree_atlas.py check`.
PNG ricompressi possono avere hash di file diversi.

## Ricostruzione

Richiede Blender 5.2 e, per il packing esterno, Python con Pillow e NumPy.
Non sono dipendenze del gioco. Prima di rigenerare, conservare gli asset correnti:
i comandi seguenti sovrascrivono gli output di authoring.

1. Scaricare i due file sopra in
   `subagent-artifacts/garda-forest/tree-source/`, verificando gli SHA-256.
   Escludere gli artefatti dall'import Godot con un file `.gdignore` nella
   directory `subagent-artifacts/garda-forest/`.
2. Dalla radice del progetto: `python tools/pack_garda_tree_atlas.py base`.
3. Eseguire tramite Blender MCP (sostituire il percorso con quello del checkout):

   ```python
   import runpy
   garda = runpy.run_path(r"C:/Users/sanna/Workspace/Godot/Progetti/aero-demons/tools/build_garda_tree.py")
   garda['build']()
   ```

   Poi chiamare separatamente `garda['bake']('front')`,
   `garda['bake']('side')` e `garda['bake']('top')`.
4. Nel Python esterno: `python tools/pack_garda_tree_atlas.py pack`.
5. In Blender MCP: `garda['finish']()`. Esporta il GLB e salva una copia
   `C:/Users/sanna/Workspace/3D_models/garda_broadleaf_game_ready.blend`.
   La scena Blender preesistente viene conservata; viene ricostruito solo lo
   studio nominato `Garda Broadleaf Studio`. Adattare il percorso `.blend`
   in `finish()` su un'altra macchina.
6. Reimportare in Godot mantenendo i file `.import`: LOD automatici disabilitati,
   atlas con mipmap e compressione VRAM ad alta qualità (BPTC sulla macchina testata).

Il GLB contiene l'atlas per essere trasportabile. Godot ne estrae automaticamente
anche `garda_broadleaf_garda_broadleaf_atlas.png`; non è una seconda variante.
Le istanze Terrain3D usano il materiale condiviso
`resources/terrain/garda_tree_material.tres`, che punta all'atlas originale.
Non istanziare insieme le tre mesh sovrapposte: la selezione LOD è gestita da
Terrain3D, slot mesh **1** in `garda_surface_assets.tres`.

L'exporter Blender segnala più nodi immagine per un sampler. Il materiale
Godot di override è quello verificato nei test di gioco.

## File consegnati — SHA-256

- `garda_broadleaf.glb` (2.781.640 byte):
  `6be1302ce9a37e14405e21b8634cc8b8b9eeeb4a714f22cb31cdc0dd3d32f49a`
- `garda_broadleaf_atlas.png` (2.318.927 byte):
  `2497975f37a18658c32c6e36cdadc718546b292d6450e0a71df4b35c897877da`

Prestazioni e limiti: [report](../../../docs/garda-forest-review.md).
