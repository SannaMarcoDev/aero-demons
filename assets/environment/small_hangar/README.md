# H-01 — piccolo hangar triangolare

Un solo modulo, realizzato in Blender tramite MCP, separato dall'aeroporto esistente.

## Aprire e usare

- **Godot, pronto da duplicare:** `res://scenes/maps/small_hangar.tscn`.
- **Anteprima F6:** `res://scenes/preview/small_hangar_preview.tscn`.
  `O` apre/chiude; `1/2/3` esterno/interno/distanza; WASD + mouse, Q/E quota,
  Shift veloce, Esc libera il mouse/esce. La camera riusa `free_fly_camera.gd`.
- **Blender:** `source/small_hangar.blend`, scena `SmallHangar`.
- **Export portabile:** `small_hangar.glb`, materiali e animazione inclusi.
- API dell'istanza Godot: `set_open(true)` / `set_open(false)`;
  secondo argomento `true` applica immediatamente la posa. L'inversione non teletrasporta la porta.

Origine al centro del pavimento, quota del pavimento **0 m**. Scala 1 unità = 1 m.
In Godot l'ingresso guarda **+Z**, in Blender **-Y**. Collocare la fondazione,
spessa 36 cm, sotto la quota del terreno; non aggiungere una collisione piena all'intero edificio.

## Forma, dimensioni e struttura

La reference fornita mostra un piccolo fronte triangolare, una copertura chiara quasi
fino a terra e un'apertura centrale scura. I dettagli non risolvibili sono interpretati,
non misure ricavate con precisione dalla fotografia.

- Corpo nominale **28 × 24 m**, fondazione **28,5 × 24,7 m**, colmo/scossaline circa **9,2 m**.
- Porta nominale **11,6 m** di larghezza; altezza geometrica libera aperta **4,88 m**.
  Cartello di esercizio **4,8 m**; prevedere margine: jet fino a circa **10 m di apertura
  alare, 17 m di lunghezza, 4,7 m di altezza**. Non adatto indiscriminatamente a tutti
  i velivoli del progetto. Non è stata provata una manovra con il player reale.
- Falda in lamiera nervata, giunti rialzati, sormonti, colmo, scossaline, canali laterali;
  timpani e basamento in cemento, cornice metallica, piastre e fissaggi.
- Interno con quattro telai controventati, arcarecci, lampade sospese, linee guida,
  quadro e canalina elettrica, aerazione, banco e scaffale. Nessun oggetto esterno
  all'hangar, piazzale, strada o altro edificio.

## Porta bifold

`DoorUpper` ruota attorno alla cerniera superiore lungo X; `DoorLower` è figlio del
pannello superiore e ruota attorno alla cerniera intermedia. Angoli finali locali
**-90° / +180°**: le due ante si ripiegano all'esterno senza accatastare le superfici
nello stesso piano. Guide e rulli mantengono il bordo inferiore sulla verticale;
i due cavi di sollevamento si accorciano verso i gruppi di avvolgimento.

Blender, **30 FPS**, marcatori:

| Frame | Stato |
|---|---|
| 1–31 | chiusa |
| 31–151 | apertura, 4 secondi |
| 151–211 | completamente aperta |
| 211–331 | chiusura, 4 secondi |
| 331–361 | chiusa |

GLB: una clip `SmallHangar`, durata **12 s**, tempi traslati a zero.
Godot campiona il tratto **1–5 s** in avanti/indietro sul tick fisico; 9 primitive
statiche proteggono involucro/pavimento, 2 box mobili seguono le ante.
La scala animata di `LiftCables` è intenzionale: regola la lunghezza dei cavi;
le altre mesh hanno scala unitaria e rotazioni statiche applicate.
L'ottimizzatore delle chiavi Godot è **disabilitato nel solo import di questo GLB**:
la semplificazione indipendente delle due rotazioni spostava i rulli fuori guida.

La porta non ha sensori anticollisione o logica d'accesso AI: verificarne l'area libera
prima di comandare la chiusura. Gli arredi minuti non hanno collisioni dedicate.

## UV, PBR e prestazioni

**37.620 triangoli**, **5 mesh**, **21 superfici/material draw submissions di base**,
**12 materiali**, **13 immagini da 1024²**, GLB circa **9,3 MiB**.
Ombre e pass aggiuntivi non sono inclusi nel conteggio delle superfici.
Mesh, materiali e texture sono condivisi fra istanze; posa/animazione indipendenti.
LOD e shadow mesh nativi Godot abilitati; nessun rig scheletrico, shader custom o
materiale procedurale richiesto a runtime.

UV0 metriche ripetute su involucro e struttura; atlas a piena porta per la vernice.
Le UV ripetute si sovrappongono intenzionalmente: **non sono UV2 per lightmap**.
Base color, roughness e normali OpenGL esportate, metallicità fisica per i metalli;
vernice più opaca, sporco di base sfumato, variazioni fotografiche contenute.
Geometria di giunti/bordi mantiene leggibilità da vicino.

Le immagini provengono dalle risorse Poly Haven **CC0** già nel repository:
[provenienza originale](../airport/textures/polyhaven/provenance.json),
[licenza](https://polyhaven.com/license),
[concrete](https://polyhaven.com/a/concrete),
[concrete_floor_01](https://polyhaven.com/a/concrete_floor_01),
[corrugated_iron_02](https://polyhaven.com/a/corrugated_iron_02).
`source/prepare_textures.py` genera le riduzioni e le tinte in `textures/`;
`small_hangar_*` nella radice sono le texture estratte dall'import Godot.
Il `.blend` conserva le texture packed; il GLB le incorpora.

Le luci dinamiche e MSAA 4× appartengono **solo all'anteprima**, non al modulo:
nessuna modifica a `project.godot`. I bordi sottili possono produrre aliasing con il
solo FXAA della mappa: MSAA o una diversa strategia AA vanno valutati nella scena
finale. Nessun benchmark con decine di hangar o integrazione nel terreno è dichiarato.

## Ricostruire e verificare

1. `python3 assets/environment/small_hangar/source/prepare_textures.py` (Pillow).
2. In un file Blender senza una scena `SmallHangar` già presente:
   ```python
   import bpy, runpy
   sh = runpy.run_path('/percorso/repo/assets/environment/small_hangar/source/build_small_hangar.py')
   sh['blockout']()
   sh['detail']()
   sh['finish']()
   ```
   La ricetta rifiuta di sovrascrivere una scena omonima; fare backup dei ritocchi.
   Per riesportare un sorgente già aperto:
   ```python
   g = sh['export_and_check'].__globals__
   g['SCENE'] = bpy.data.scenes['SmallHangar']
   g['ROOT_OBJ'] = bpy.data.objects['SmallHangar']
   sh['export_and_check']()
   ```
3. Eseguire **scan filesystem** Godot dopo la riesportazione; controllare l'MD5 della
   cache. Il solo `update_file` MCP non ha aggiornato la cache nelle prove.
4. Dalla radice (sostituire `GODOT` col binario):
   ```sh
   node tools/run_godot_check.cjs 35 .pi/small_hangar/prepare.log GODOT --headless --path . --script res://tools/prepare_small_hangar.gd
   node tools/run_godot_check.cjs 25 .pi/small_hangar/check.log GODOT --headless --path . --script res://tests/small_hangar_check.gd
   ```
   Non usare `--fixed-fps` per questo check: l'autoload audio del progetto può
   trattenere uno stream nel teardown accelerato. La variante ordinaria passa pulita.

Verificati: 361 frame Blender (guida/cavi/clearance/UV/scale), import Godot,
61 pose e inversione continua, collisioni a porta chiusa/aperta, passaggio a 4,75 m,
collisioni delle falde, duplicazione con risorse condivise e stato indipendente.
Entrambi i comandi finali: **PASS, exit 0, nessun errore**.

Godot MCP: scena aperta, avvio `autosave=false`, stato **live**, `O` apertura e chiusura,
viste 1/2/3 controllate; log del run finale e log editor senza errori.
Render Blender e catture Godot finali in `source/review/` (09–11); i render
intermedi e i log di esecuzione locali sono stati rimossi. Il viewport
screenshot Blender MCP non scriveva il file nella sandbox: sono stati usati
i render salvati reali.
L'exporter Blender segnala un sampler condiviso fra nodi immagine: tutti i nodi
coinvolti usano gli stessi Repeat/Linear; i materiali sono stati controllati in Godot.

Sorgente `.blend` in Git LFS, GLB separato e scene di preview isolate.
L'istanza scalata per l'N26 vive solo nell'aeroporto V2; l'asset qui descritto
rimane a scala nativa.
