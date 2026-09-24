# Sfera energetica viola

## Uso

Trascinare `res://scenes/vfx/energy_sphere.tscn` nella scena desiderata. Il centro del nodo è il centro della sfera; **diametro solido 500 m**, raggio 250 m. Nessuna missione, mappa o impostazione globale viene modificata.

Modificare `diameter_m` sull'Inspector del nodo radice, **non la scala del nodo o dei suoi antenati**: la proprietà aggiorna insieme mesh e collisione. Mantenere le trasformazioni senza scala non uniforme per conservare una vera sfera. Materiali e forma di collisione sono locali all'istanza; duplicare la scena non condivide i parametri modificabili.

Parametri del nodo:

| Parametro | Effetto |
| --- | --- |
| `diameter_m` | Diametro fisico, in metri (default 500). |
| `violet`, `magenta`, `emission_strength` | Colori e intensità HDR. |
| `core_radius` | Raggio del nucleo in proporzione al raggio esterno. |
| `filament_width`, `pattern_scale` | Spessore degli archi e scala delle turbolenze. |
| `animation_speed`, `pulse_amount`, `phase` | Movimento, pulsazione luminosa e sfasamento tra istanze. Velocità 0 congela l'energia. |
| `halo_strength`, `halo_width` | Intensità e spessore dell'alone, esterno alla collisione. |

Il `StaticBody3D` usa il layer 1 del mondo. Blocca i corpi fisici che interrogano quel layer; il giocatore di Aero Demons rileva l'impatto tramite la propria hitbox e viene distrutto, come contro gli altri ostacoli solidi. Non sono stati cambiati volo, invulnerabilità, armi o AI. Niente traino, cavi, danno di prossimità o luci ambientali aggiuntive.

L'alone è visibile anche senza glow del `WorldEnvironment`; con Forward+ e glow attivo si aggiunge il bloom HDR. Esposizione e tonemapper del livello influenzano il risultato: tarare `emission_strength` nel livello finale, senza copiare l'ambiente della demo nelle mappe. La sfera non aggiunge un proprio `WorldEnvironment`.

## Anteprima

Aprire `res://scenes/vfx/preview/energy_sphere_preview.tscn` e premere **F6**.

- **1–4**: panoramica, distanza (~3,3 km dalla superficie), vicino (60 m), lato opposto.
- **O**: orbita; **WASD/QE**, **Shift**: movimento; **M**: mouse look; **Esc**: libera mouse/esci.
- **G**: bloom on/off; **B**: cielo/sfondo nero; **H**: nasconde HUD.
- **C**: avvia il giocatore reale verso la sfera; senza sterzare avviene l'impatto. **1–4** tornano all'anteprima.

Griglia ogni 100 m, riferimento verticale da 100 m e N26 alla scala nativa aiutano a leggere le dimensioni. Questi elementi appartengono soltanto all'anteprima.

## Implementazione e limiti

- Due mesh sferiche: superficie opaca con depth buffer e alone additivo. Nessun billboard nell'effetto.
- Shader in coordinate 3D senza cuciture UV: una `NoiseTexture3D` seamless 64³ condivisa, sei campioni noise per pixel della superficie e archi analitici antialiasati.
- Intersezioni analitiche con due sfere interne per parallasse, nucleo scuro e strati energetici. **È profondità a strati, non una simulazione volumetrica completa**; nessun loop di raymarching.
- Animazione esclusivamente GPU; nessun aggiornamento per-frame nello script dell'effetto. Rotazioni/deformazioni riguardano i pattern, pulsazione e flicker riguardano la luminosità: silhouette e collisione restano ferme e sferiche.
- Due mesh/materiali per la sfera, senza ombre aggiuntive o particelle. Nessun LOD dinamico: per molte sfere simultanee profilare prima overdraw e campioni noise, poi ridurre la tessellazione o aggiungere LOD.

La reference ha guidato una seconda taratura: nucleo più scuro, energia superficiale attenuata, archi con spessore variabile, alone indipendente dal bloom. Un prossimo passaggio utile sarebbe tarare contrasto e densità sulla mappa definitiva e rendere il bordo del nucleo meno regolare; il raymarching avrebbe senso solo con una reale necessità di volume, non per questo oggetto non attraversabile.

## Verifiche eseguite

Godot **4.7.2**, Forward+, avvio tramite Godot AI MCP con `autosave=false`, stato `live`. Ispezionate le quattro viste, l'animazione su catture successive, il lato opposto, lo sfondo nero e il bloom disattivato; verificato anche l'impatto del giocatore nella demo grafica. I log della run finale non riportano errori di script/shader o caricamento.

Il controllo eseguibile è integrato nella demo (nessun nuovo file sotto `tests/`):

```sh
node tools/run_godot_check.cjs 30 .pi/energy-sphere/verify.log /percorso/a/godot \
  --headless --path . --fixed-fps 60 \
  res://scenes/vfx/preview/energy_sphere_preview.tscn -- --verify
```

Verifica raggio, ridimensionamento/isolamento di una seconda istanza, raycast sui sei assi, movimento fisico spazzato di 1200 m e impatto dell'aereo reale. Esito: marker `PASS`, exit 0, senza errori di script/assert o risorse trattenute al teardown. Restano due warning preesistenti dei riferimenti UID delle texture N26, risolti da Godot tramite i percorsi testuali.

La demo ha mostrato circa 119–120 FPS a 1920×1080 sulla macchina corrente (limite di refresh apparente): **non è una misura del costo GPU isolato né una garanzia sulle mappe complete**. Integrazione visiva con cielo/nuvole delle mappe e hardware più lento ancora da profilare.
