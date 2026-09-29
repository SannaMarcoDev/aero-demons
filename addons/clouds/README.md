# CloudLayer3D — prima integrazione Garda

Importato dal progetto locale `clouds-testing`, cartella `clouds/`, revisione
`cff3257`. Renderer, generatori, shader e preset originali conservati. Adattamenti:
percorsi `res://addons/clouds/` e avvio disabilitato in modalità headless.
Nessun EditorPlugin da abilitare: `class_name CloudLayer3D` registra il nodo.

## Utilizzo

In `scenes/maps/garda_final.tscn`, `CloudLayer3D` usa `Sky3D` come
WorldEnvironment e `Sky3D/SunLight` come sole. Freeroam, tutorial, arena e replay
che caricano Garda ereditano il layer. Cielo, cirri, terreno, acqua e luci
esistenti non sono modificati; i cumuli 2D erano già disattivati.

- Richiede **Forward+**. In headless non alloca risorse né modifica il compositor.
- Preset **Original**, bounds **2000–15000 m**, coverage **1.18**, densità
  **0.0035**, massimo **1024** passi: default del progetto sorgente.
- Il campo è globale, statico e periodico ogni **100 km**. Il transform del nodo
  non lo sposta; le quote sono Y assolute in metri, non altezza sul terreno.
- L'Inspector espone quattro preset, quote, copertura, densità e `Clouds Enabled`.
- `Editor Preview` è disattivato: abilitarlo per vedere le nuvole nell'editor.
  La prima generazione richiede qualche secondo; cambiare sole o formazione
  ricostruisce le cache. Non animare questi parametri ogni frame.
- Non aggiungere più layer allo stesso WorldEnvironment. Il compositor
  preesistente viene preservato e ripristinato all'uscita.

## Limiti di questa prima integrazione

Ombre su terreno/aereo disattivate e nessun materiale registrato: nessuna cache
ombre aggiuntiva. Il supporto originale è incluso (`cloud_receiver.gdshader`,
`cloud_shadow.gdshaderinc`, `register_shadow_material()`), ma richiede adattare
esplicitamente i materiali del gioco. Nessuna modifica automatica ai materiali.

La query asincrona `request_density(world_position, callback)` è disponibile,
ma effetti sul parabrezza, turbolenza e logica del player non sono collegati.
La foschia interna al renderer conserva la taratura della demo: nessuna nuova
taratura artistica o garanzia di prestazioni sulla mappa Garda.

Per esportare mantenere **Export all resources** (già configurato nel progetto):
i compute shader caricati per percorso devono essere inclusi come risorse GLSL
importate. Demo, benchmark e test del progetto sorgente non sono stati copiati.

## Verifiche della prima integrazione

Su Godot 4.7.2 / Forward+ Metal: controllo esistente
`tests/maps/garda_ground_cover_check.gd` passato in headless; Freeroam, Tutorial
ed Arena avviati via Godot AI con `autosave=false`, stato `live`, compositor e
cache forma/luce presenti, nessuna cache ombre e nessun nuovo errore nei log.
Ispezionate immagini da terra, in quota, dentro e sopra le nuvole in Freeroam.
Resta il warning del motore su `instance_reset_physics_interpolation()` deprecato.
Prestazioni, export e gameplay completo non verificati in questa integrazione.
