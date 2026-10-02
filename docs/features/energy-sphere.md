# Sfera energetica viola

## Uso

Trascinare `res://scenes/vfx/energy_sphere.tscn` nella scena desiderata. Il centro del nodo è il centro della sfera; **diametro solido 500 m**, raggio 250 m.

Modificare `diameter_m` sull'Inspector del nodo radice, **non la scala del nodo o dei suoi antenati**: la proprietà aggiorna insieme mesh, corona, lente, luce e collisione. Mantenere le trasformazioni senza scala non uniforme per conservare una vera sfera. Materiali e forma di collisione sono locali all'istanza; duplicare la scena non condivide i parametri modificabili.

Se la sfera viaggia, impostare `travel_velocity` (m/s, spazio mondo) prima di aggiungerla alla scena o in seguito: le fiamme scivolano all'indietro e si allungano sul lato di scia. Il tutorial lo imposta sulla velocità del convoglio. La direzione viene convertita nello spazio locale quando il valore cambia, non a ogni frame: se si ruota la sfera, riassegnare la velocità.

Parametri del nodo:

| Parametro | Effetto |
| --- | --- |
| `diameter_m` | Diametro fisico, in metri (default 500). |
| `travel_velocity` | Velocità di chi trasporta la sfera; piega e allunga le fiamme. |
| `violet`, `magenta`, `ink`, `spark` | Viola e magenta dell'energia, nero-viola del fumo, colore caldo di fulmini e scintille. Anche la luce deriva da viola e magenta. |
| `emission_strength` | Intensità HDR di tutti gli strati. |
| `core_radius` | Raggio dell'occhio nero centrale, in proporzione al raggio. |
| `swirl`, `pattern_scale` | Torsione delle braccia del vortice e scala dei pattern. |
| `animation_speed`, `pulse_amount`, `phase` | Velocità di vortice, fiamme e filamenti, pulsazione luminosa, sfasamento tra istanze. Velocità 0 congela l'energia; fulmini e raffiche seguono il tempo reale. |
| `flame_height`, `flame_density` | Altezza delle lingue d'inchiostro (in raggi) e loro opacità. |
| `arc_rate` | Frequenza delle scariche ordinarie. |
| `lens_strength` | Quanto la silhouette piega lo sfondo. |

Il `StaticBody3D` usa il layer 1 del mondo. Blocca i corpi fisici che interrogano quel layer; il giocatore rileva l'impatto tramite la propria hitbox e viene distrutto, come contro gli altri ostacoli solidi. Fiamme, filamenti, fulmini e lente sono solo visivi: la collisione resta una sfera semplice. Il tutorial azzera i layer: lì la sfera è scenografia.

## Reference e direzione artistica

Reference: la Shadow Ball dei Pokémon nelle sue versioni principali.

- Anime: sfera viola traslucida con centro caldo, scintille interne, scariche scure attorno.
- *Super Smash Bros. Ultimate*: sfera indaco con orlo luminoso netto, fiamme d'inchiostro strappate che si staccano e scivolano dietro, fulmini bianchi sulla superficie.
- *Spada/Scudo*, *Leggende Arceus*, *Scarlatto/Violetto*: nucleo quasi nero a vortice, sottile orlo magenta, filamenti neri a frusta, anello d'urto scuro con distorsione.

Adattamento al mondo di Aero Demons: oggetto da 500 m, tecnologia nemica con interferenza tipo EMP, scortato in volo su Riva di giorno. Quindi scala e moto realistici, nessun contorno cartoon, e la scarica elettrica legata all'impulso, che richiama l'incidente di Nova senza spiegarlo.

## Strati

| Nodo | Cosa fa |
| --- | --- |
| `Surface` | Superficie opaca: vortice che risucchia verso il centro lungo braccia a spirale, vene luminose rade, strato di plasma interno e occhio nero con anello caldo, entrambi con vera parallasse. Scrive la profondità. |
| `Corona` | Fiamme d'inchiostro volumetriche in raymarching: radici violette, frange magenta, punte nere. Si addensano sulla silhouette, sulla faccia resta solo un velo. Un sottile orlo di plasma dà il bordo luminoso. |
| `Tendrils` | Nastri d'inchiostro che nascono all'esterno, girano a spirale e vengono inghiottiti; ognuno rinasce con un percorso nuovo. |
| `Arcs` | Fulmini frastagliati: alcuni strisciano sulla superficie, altri saltano fuori. Un terzo degli slot scatta solo nelle raffiche. |
| `Lens` | Piega lo sfondo attorno alla silhouette e lancia l'anello d'urto dell'impulso. |
| `Light` | Luce viola senza ombre, raggio 6 raggi della sfera: tinge scorte e terreno sotto il convoglio. |

In media ogni 6,5 s (tra 3 e 10 s) parte una **raffica**: plasma e vene si accendono, la corona si gonfia, scattano i fulmini lunghi e si espande l'anello d'urto. Tutti gli strati calcolano la raffica dallo stesso orologio (`energy_sphere_common.gdshaderinc`), quindi restano sincronizzati senza script.

## Anteprima

Aprire `res://tools/preview/vfx/energy_sphere_preview.tscn` e premere **F6**.

- **1–4**: panoramica, distanza (~3,3 km dalla superficie), vicino (60 m), lato opposto.
- **O**: orbita; **WASD/QE**, **Shift**: movimento; **M**: mouse look; **Esc**: libera mouse/esci.
- **G**: bloom on/off; **B**: cielo/sfondo nero; **H**: nasconde HUD.
- **C**: avvia il giocatore reale verso la sfera; senza sterzare avviene l'impatto. **1–4** tornano all'anteprima.

L'ambiente dell'anteprima ha Filmic e bloom; Riva usa AgX (white 6) **senza glow**. Tarare colori e intensità nel tutorial: il bagliore della sfera nasce dagli shader, non dal post-process.

## Implementazione e limiti

- Tutto anima sulla GPU da `TIME`: nessuno script per frame. Come gli altri VFX shader, l'energia continua a muoversi in pausa; nel replay `TIME` viene sostituito dal clock del replay e gli shader riscritti compilano. `travel_velocity` non viene registrata: nei replay le fiamme non si piegano.
- Fulmini e filamenti sono strisce `MultiMesh` con trasformazioni identità salvate nella scena; lo shader di vertice ricostruisce forma e orientamento. Nessuna mesh generata a runtime.
- Vortice e filamenti sono orientati verso la camera: la spirale guarda sempre lo spettatore. È una scelta stilistica, come nella reference; tra uno stacco e l'altro non si nota.
- La corona marcia con un passo di circa 10 m (fino a 56 passi) e si ferma sulla profondità della scena: gli aerei dentro le fiamme sono composti correttamente. Non è una simulazione fisica dei fluidi.
- **Nuvole volumetriche**: `CloudLayer3D` compone dopo i trasparenti usando la profondità. Per non farsi coprire dalle nuvole che stanno dietro, il fumo denso della corona, il corpo dei filamenti e il nucleo dei fulmini scrivono profondità; le parti rade riscrivono il valore esistente, così non si aprono buchi nelle nuvole. Restano coperti dalle nuvole retrostanti solo l'alone dei fulmini e la distorsione della lente.
- La foschia atmosferica di Riva agisce solo sugli opachi: da 10 km la faccia della sfera appare più velata della corona.
- Da molto vicino (camera dentro la corona, sotto ~150 m dalla superficie) la superficie perde dettaglio: la texture di rumore è 64³. La cinematica resta oltre ~300 m.

Costo misurato a 1920×1080 (Forward+, GPU della macchina di sviluppo), tempo GPU del viewport con e senza lo strato: corona circa 1,5 ms nell'inquadratura L, con la sfera quasi a tutto schermo su Riva; superficie, filamenti e fulmini trascurabili, lente circa 0,1 ms. Non è una garanzia su hardware più lento.

## Verifiche eseguite

Godot **4.7.2**, Forward+, avvio tramite Godot AI MCP con `autosave=false`, stato `live`.

- Anteprima con ambiente tipo Riva (AgX, white 6, senza glow): viste 1–4, sfera in moto, tempo GPU per strato.
- Tutorial su Riva, rivelazione completa: beat A (13,9 km), tally con zoom (10,9 km, fov 4,7), F (MiG davanti alla sfera, 555 m), G (teleobiettivo 9,4 km), L (intercettori con la sfera alle spalle). Nuvole verificate accese e spente.
- Materiali riscritti come fa il replay (`TIME` → `replay_clock`): compilano e si vedono.
- Log della run: nessun errore di shader, script o caricamento; restano solo warning GDScript preesistenti in altri script.

Il controllo eseguibile è integrato nella demo (nessun nuovo file sotto `tests/`):

```sh
node tools/run_godot_check.cjs 90 .pi/energy-sphere/verify.log /percorso/a/godot \
  --headless --path . --fixed-fps 60 \
  res://tools/preview/vfx/energy_sphere_preview.tscn -- --verify
```

Verifica raggio, ridimensionamento/isolamento di una seconda istanza, raycast sui sei assi, movimento fisico spazzato di 1200 m e impatto dell'aereo reale. Esito: marker `PASS`, exit 0, nessun errore di script/assert o risorse trattenute. In headless gli shader non vengono renderizzati: la resa è stata verificata solo nelle run con finestra elencate sopra.
