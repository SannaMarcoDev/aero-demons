# CloudLayer3D — integrazione Garda

Importato dal progetto locale `clouds-testing`, cartella `clouds/`, revisione
`cff3257`. Renderer, generatori, shader e preset originali conservati. Adattamenti:
percorsi `res://addons/clouds/` e avvio disabilitato in modalità headless.
Nessun EditorPlugin da abilitare: `class_name CloudLayer3D` registra il nodo.

## Utilizzo

In `scenes/maps/riva_sample.tscn`, `CloudLayer3D` usa `Sky3D` come
WorldEnvironment e `Sky3D/SunLight` come sole. Freeroam, tutorial, arena e replay
che caricano la mappa ereditano il layer. Cielo, cirri, terreno, acqua e luci
esistenti non sono modificati; i cumuli 2D erano già disattivati.

- Richiede **Forward+**. In headless non alloca risorse né modifica il compositor.
- Preset **Original**, bounds **2000–15000 m**, coverage **1.18**, densità
  **0.0035**, massimo **1024** passi: default del progetto sorgente.
- Il campo è globale, statico e periodico ogni **100 km**. Il transform del nodo
  non lo sposta; le quote sono Y assolute in metri, non altezza sul terreno.
- L'Inspector espone quattro preset, quote, copertura, densità e `Clouds Enabled`.
- `base_darkening` (gruppo Clouds) scurisce la base delle nuvole: la nuvola
  sopra nasconde il cielo e la luce diffusa cala più in fretta in profondità.
  0 = aspetto originale, 1 = occlusione fisica, oltre 1 = stilizzato. Non
  richiede bake. Garda **1.0**. Per l'aria e il terreno sotto le nuvole vedere
  `shadow_darkness`.
- La luce del cielo dentro/sotto le nuvole usa lo stesso modello dell'aria
  (colore × energia del sole × `haze_color`), non più un blu fisso di mezzogiorno:
  all'alba o al tramonto basi e interni seguono la luce reale.
- `Editor Preview` è disattivato: abilitarlo per vedere le nuvole nell'editor.
  La prima generazione richiede qualche secondo; cambiare sole o formazione
  ricostruisce le cache. Non animare questi parametri ogni frame.
- Non aggiungere più layer allo stesso WorldEnvironment. Il compositor
  preesistente viene preservato e ripristinato all'uscita.

## Ombre su Garda

Le ombre volumetriche sono attive a **512²**, circa **86 MiB** aggiuntivi di VRAM.
Il campo e la formazione delle nuvole restano quelli originali. La cache viene
ricostruita soltanto quando cambiano sole/formazione/risoluzione, non al movimento
della camera o dell'aereo.

`CloudShadowReceivers` (`scripts/maps/garda_cloud_shadows.gd`) collega a runtime
terreno, contesto, edifici, acqua, boschi, player e oggetti aggiunti successivamente
(compresi AI e attori replay). Le copie di materiali/mesh sono locali al mondo:
nessun GLB, materiale importato o asset Terrain3D viene riscritto. I viewport di
anteprima separati e gli effetti unshaded non vengono convertiti.

`register_shadow_material()` accetta ora anche il `Terrain3DMaterial` nativo.
Il terreno usa `cloud_pbr.gdshaderinc`; gli altri shader di Garda ricevono la
stessa funzione di luce nelle loro copie runtime. I materiali StandardMaterial3D
usano `resources/shaders/cloud_standard.gdshader`, conservando albedo, normal,
canali metallic/roughness/AO, emissione, UV, vertex color, culling e modalità
alpha. Il ricevitore copre il PBR isotropo Burley/GGX effettivamente usato su
Garda; clearcoat, anisotropia, SSS e shader con una propria `light()` richiedono
un'integrazione specifica prima di introdurre nuovi asset con quelle funzioni.

Sono attenuati **diffuso, speculare e backlight diretti del sole assegnato**:
emissione e ombre delle mesh non sono moltiplicate per la trasmissione delle
nuvole. `shadow_darkness` (gruppo Cloud Shadows, 0–1) è lo slider unico per
quanto è più buio tutto ciò che sta sotto le nuvole rispetto alle zone aperte:
la nuvola nasconde anche il cielo, quindi l'ombra toglie quella quota di luce
ambientale e riflessi ai ricevitori (`AO`, `cloud_ambient_occlusion()` in
`cloud_shadow.gdshaderinc`) e di luce del cielo all'aria, sia davanti al
terreno sia davanti alle nuvole. 0 = solo il sole diretto è in ombra, 1 = il
massimo. Default 0, Garda **0.85**. Sui ricevitori agisce solo a runtime:
regolarlo dal Remote inspector col gioco avviato. Il collegamento dei materiali
è runtime-only; il solo `Editor Preview` del layer mostra le nuvole ma non
converte i ricevitori.

### Controllo rapido tramite Godot AI

Con una scena Garda in esecuzione, eseguire questo GDScript con
`editor_manage(op="game_eval", params={code: ...})`:

```gdscript
var layer = get_tree().current_scene.find_child("CloudLayer3D", true, false)
assert(layer != null and layer.shadows_enabled)
assert(layer._shadow_pass != null and layer._shadow_pass._active)
assert(layer._runtime_shadow_materials.size() > 1)
for material in layer._runtime_shadow_materials:
    var rid = CloudShadowPass.material_rid(material)
    assert(RenderingServer.material_get_param(rid, "cloud_shadow_enabled"))
    assert(RenderingServer.material_get_param(rid, "cloud_shadow_texture") != null)
return "GARDA CLOUD SHADOW BINDINGS PASS"
```

Per il confronto visivo usare `layer.shadows_enabled = false/true` a camera
ferma e attendere alcuni frame renderizzati. Il toggle non cambia le nuvole
né richiede un nuovo bake. L'integrazione rimane inattiva in headless.

La query asincrona `request_density(world_position, callback)` è disponibile,
ma effetti sul parabrezza, turbolenza e logica del player non sono collegati.

## Atmosfera (prospettiva aerea)

Un solo modello d'aria, `atmosphere.glslinc`, vela sia la geometria opaca sia
ogni campione di nuvola: monti lontani e nuvole lontane ricevono la stessa
foschia. Due componenti esponenziali in quota, integrate analiticamente:
foschia bassa (`haze_distance`, `haze_height`, sopra `haze_base_altitude`) e
aria Rayleigh (`air_density`, tinta blu in distanza). Il colore è
`haze_color` × colore/energia del sole, più `haze_sun_scattering` verso il sole.

- `CloudAtmosphere` è un secondo CompositorEffect creato da `CloudLayer3D` nello
  stesso compositor, dopo il cielo e prima dei trasparenti: scie e particelle
  non vengono velate con la profondità del terreno dietro di loro.
- Il cielo resta a Sky3D. Sotto l'orizzonte, oltre il far plane, la cupola
  mostrerebbe il suo `ground_color` scuro: viene velato come terreno alla quota
  base, così acqua e terreno lontani si fondono con l'orizzonte.
- Raccordo dell'orizzonte: appena sopra l'orizzonte il cielo Sky3D sfuma verso
  la stessa aria che il terreno sotto raggiunge, quindi i due lati coincidono
  senza linea (prima restava una fascia turchese di Sky3D). Conta solo l'aria in
  più rispetto a un raggio verticale: lo zenit resta quello di Sky3D. Funziona
  anche in quota sopra la foschia. `horizon_haze` regola l'altezza della
  sfumatura: 0 = cielo intatto, 1 = default fisico (usato su Garda), più alto =
  più ampia.
- Indipendente da `clouds_enabled`. Con `atmosphere_enabled = false` il terreno
  torna nitido e le nuvole riprendono la foschia originale della demo.
- Nessun bake: i parametri si possono cambiare a runtime.
- Ombre nella foschia: la luce della foschia è divisa tra cielo
  (`haze_sky_light`, non ombreggiata) e sole diretto. La parte solare campiona
  la stessa cache delle ombre lungo il raggio di vista, quindi sotto i banchi
  l'aria si scurisce e compaiono i raggi di luce; `haze_cloud_shadows` regola
  l'intensità (0 = foschia uniforme). Richiede `shadows_enabled` e almeno un
  ricevitore registrato; il jitter dei campioni è risolto dal TAA. Le ombre
  sono campionate nei primi 80 km del raggio; l'aria oltre resta al sole.
- La foschia davanti alle nuvole usa la stessa ombra: la visibilità del sole
  è calcolata una volta per pixel, dalla camera alla prima nuvola, quindi le
  basi lontane viste attraverso l'aria sotto il banco escono scure invece che
  velate di foschia al sole. Con `shadow_darkness` alto la foschia in ombra
  vira verso il caldo: resta soprattutto la diffusione in avanti del sole.
- Garda: `haze_base_altitude = 185` (livello del lago), `haze_sky_light = 0.45`,
  `shadow_darkness = 0.85`, `base_darkening = 1.0`, altri valori di default.

### Luce del mondo su Garda

La radiance del cielo Sky3D fornisce un ambientale quasi nullo: con
`sky_contribution` basso il terreno in ombra risultava nero rispetto al cielo
nuvoloso. Valori in `Sky3D` (che li propaga a Environment e `SunLight`):
`sun_energy = 2.0`, `ambient_energy = 1.75`, `sky_contribution = 0.5`,
`sun_shadow_opacity = 1.0`, `tonemap_exposure = 1.0`. La fog globale di Godot
resta disattivata: la prospettiva aerea è solo `CloudAtmosphere`. L'aeroporto
ha un proprio `DirectionalLight3D` (`Airport/Sun`), non modificato.

Per esportare mantenere **Export all resources** (già configurato nel progetto):
i compute shader caricati per percorso devono essere inclusi come risorse GLSL
importate. Demo, benchmark e test del progetto sorgente non sono stati copiati.

## Verifiche delle ombre

Su Godot 4.7.2 / Forward+ Vulkan: controlli headless esistenti
`garda_ground_cover_check.gd` e `garda_surface_review.gd` passati;
shader ricevitore validato dal compilatore Godot. Freeroam, Arena, Tutorial e
replay avviati via Godot AI con `autosave=false`, stato `live` e nessun nuovo
errore nei log. Verificati 53 ricevitori in Freeroam/replay, 54 in Arena,
registrazione degli oggetti aggiunti dopo l'avvio e un solo bake condiviso.
Confrontate immagini ON/OFF di paesaggio, aeroporto e aereo in volo.
Restano warning preesistenti, inclusa l'interpolazione deprecata nel replay.
Prestazioni, export e gameplay completo non verificati.

## Verifiche della prima integrazione (storiche)

Su Godot 4.7.2 / Forward+ Metal: controllo esistente
`tests/maps/garda_ground_cover_check.gd` passato in headless; Freeroam, Tutorial
ed Arena avviati via Godot AI con `autosave=false`, stato `live`, compositor e
cache forma/luce presenti, nessuna cache ombre e nessun nuovo errore nei log.
Ispezionate immagini da terra, in quota, dentro e sopra le nuvole in Freeroam.
Resta il warning del motore su `instance_reset_physics_interpolation()` deprecato.
Prestazioni, export e gameplay completo non verificati in questa integrazione.
