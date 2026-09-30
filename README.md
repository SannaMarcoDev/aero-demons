# Aero Demons

Progetto Godot **4.7**, renderer **Forward+**, fisica **Jolt**.
Aprire `project.godot` e avviare con **F5** il [menu principale](scenes/ui/main_menu.tscn), oppure con **F6** la scena desiderata.
Dal menu si scelgono missione, aereo e due tipi di missile prima del decollo. I livelli giocabili sono in `scenes/levels/`, le mappe Garda e Utah in `scenes/maps/`. Gioco e menu hanno un limite di **30 FPS**; i benchmark diagnostici possono disattivarlo.

## Mappa del progetto

| Percorso | Contenuto |
| --- | --- |
| `scenes/levels/` | Punti di ingresso giocabili: tutorial, freeroam, varianti Utah e arena. |
| `scenes/maps/` | Mappe Garda/Utah e componenti riutilizzabili: aeroporti, città, hangar. `garda_airport.tscn` è parte della mappa di produzione, non una demo. |
| `scenes/aircraft/`, `player/`, `enemies/`, `weapons/` | Aerei, attori e armi. |
| `scenes/ui/`, `replay/`, `vfx/` | Interfaccia, viewer replay ed effetti del gioco. |
| `scripts/core/` | Stato cross-scena, impostazioni e applicazione dei valori fissi. |
| `scripts/input/`, `graphics/`, `performance/` | Binding controller, diagnostica grafica runtime e campionamento condiviso dei benchmark. |
| `scripts/` | Altra logica nel rispettivo dominio: `aircraft`, `audio`, `camera`, `combat`, `enemies`, `maps`, `player`, `replay`, `ui`, `vfx`, `weapons`. |
| `resources/` | Dialoghi, materiali, shader, configurazioni stradali e risorse Terrain3D. |
| `assets/` | Modelli, audio, font, texture e pacchetti esterni; sorgenti/licenze restano accanto agli asset. |
| `terrain/` | Dataset Terrain3D, manifest di importazione, heightmap sorgenti e texture originali. Non è una cache. |
| `textures/terrain/` | Texture fotografiche già impacchettate per Terrain3D e relativa provenienza. |
| `wc_data/` | Output e texture di World Creator Bridge; percorso richiesto dal plugin. |
| `tools/` | Importazione, generazione, benchmark standalone, review e anteprime; vedi sotto. |
| `tests/` | Check esistenti divisi per dominio: `combat`, `flight`, `graphics`, `input`, `maps`, `performance`, `ui`, `vfx`. I due check della vecchia UI non più eseguibili sono documentati in [legacy](tests/legacy/README.md). |
| `docs/` | [Indice](docs/README.md): design, sviluppo, ambiente e funzionalità. |
| `addons/`, `demo/` | Dipendenze e rispettive demo, mantenute nella struttura originale. |

In radice rimangono la configurazione Godot/Git, questa guida, l'icona e `default_bus_layout.tres` (layout audio predefinito).

## Punti di ingresso utili

- Menu e armamento: `scenes/ui/main_menu.tscn`, `loadout.tscn`; selezione cross-scena in `scripts/core/game_session.gd`.
- Giocatore: `scenes/player/player.tscn` → `scripts/player/player_flight.gd`.
- Armi: `scripts/weapons/weapon_controller.gd` e `missile_catalog.gd`.
- Camera: `scripts/camera/follow_camera.gd` e `free_fly_camera.gd`.
- Audio globale: `scripts/audio/audio_manager.gd`, registrato come autoload in `project.godot`.
- Terreni attivi: `terrain/garda_final_wc_uniform_250km/` e `terrain/utah_final_wc_uniform_250km/` (250 × 250 km); origine e parametri nei rispettivi `import_manifest.json`. Gli export World Creator restano la fonte di verità.
- Replay: `scenes/replay/replay_viewer.tscn`, logica in `scripts/replay/`; [guida](docs/features/replays.md).

## Strumenti di sviluppo

| Percorso | Uso |
| --- | --- |
| `tools/airports/` | Import e preparazione di aeroporti, città e hangar. |
| `tools/terrain/` | Download, import World Creator, shader e regioni Terrain3D. |
| `tools/vegetation/` | Costruzione alberi, atlas, bake e conversione foliage. |
| `tools/benchmarks/` | Benchmark standalone e confronto immagini; il sampler usato anche dal gioco vive in `scripts/performance/`. |
| `tools/review/` | Ispezione e catture di terreno, paesaggio e acqua. |
| `tools/preview/airports/`, `tools/preview/vfx/` | Scene di anteprima F6 e relativi script, non livelli giocabili. |
| `tools/fixtures/` | Materiali di riferimento per confronti ripetibili. |
| `tools/run_godot_check.cjs` | Runner con deadline e cleanup del solo processo avviato. |

Eseguire i comandi dalla radice del progetto. I tool di importazione/generazione possono scrivere asset: non avviarli come controlli di sola lettura. Le dipendenze Python/Blender e gli export sorgenti richiesti sono descritti nei singoli tool; la riorganizzazione non li installa né rigenera i dati.

## Menu e armamento

- **Operazioni → Garda → Armamento → Avvia missione**; **Free Flight → Armamento → Decolla** per il volo senza nemici.
- Due slot indipendenti: **STDM** standard, **HSSTDM** veloce, **BAHM** pesante, **NCGBM** incendiario (75 danni in 10 secondi oltre all'impatto), **MTSM** multi-bersaglio. Le statistiche provengono dal catalogo effettivamente usato dalle armi.
- Menu: mouse, frecce/WASD, D-Pad o stick sinistro; Invio/A conferma, Esc/B torna indietro. In volo **Q / D-Pad su** cambia slot, **TAB / Y** cambia bersaglio, **Spazio / A** lancia.
- **Esc / Start** apre la pausa: riprendi, riprova, cambia armamento, menu principale o esci. **R** riavvia la missione mantenendo il loadout.
- Opzioni: volume Master/Music/SFX, fullscreen e V-Sync. **Indietro / Esc** salva in `user://settings.cfg`; la selezione dei missili dura per la sessione corrente.

## Tutorial: radio e tre incontri

Dal menu scegliere Operazioni → Garda, oppure avviare `scenes/levels/tutorial.tscn`. Si parte con due gregari, senza ostili: comunicazione iniziale → avvistamento e **2 nemici** → comunicazione e **4 nemici da est** → comunicazione e **8 nemici da ovest** → comunicazione finale e vittoria. Ogni incontro richiede di eliminare l'intera formazione, inclusi gli abbattimenti dei gregari. I relitti non bloccano la progressione.

**Solo nel tutorial i nemici non attaccano il giocatore**: `CombatDirector.allow_player_attacks = false` esclude duello/pressione sul protagonista e nega i permessi di fuoco contro di lui. Gli ostili combattono contro i gregari. **I due compagni sono immortali solo in questa missione**: `invulnerable = true` sulle istanze `Wingman1` e `Wingman2` blocca danni da armi, incendi e collisioni, senza togliere loro bersagli o armi. Il giocatore e i nemici restano vulnerabili; nelle altre scene gli aerei hanno `invulnerable = false` e il director conserva `allow_player_attacks = true`.

- **Posizioni e numero:** `Tutorial/EnemySpawnMarkers/Encounter1`, `Encounter2`, `Encounter3`. Ogni `Marker3D` genera un aereo con posizione e orientamento del marker. Spostare/ruotare i gruppi cambia la provenienza; duplicare marker aumenta il numero. Tenere i punti nella stessa zona di combattimento, entro portata radar (20 km) dalle posizioni plausibili del giocatore. Non vengono spostati automaticamente.
- **Sequenza:** `scripts/combat/tutorial_mission.gd`, collegato a `CombatHUD/MissionController`, riusa gli esiti di `SortieController` senza la vittoria automatica tra incontri. Non ci sono waypoint obbligatori né trigger di zona.
- **Battute:** `resources/dialogues/tutorial.dialogue`, con Dialogue Manager 4.1 abilitato. Le sezioni sono `intro`, `after_1`, `after_2`, `outro`; i tag `[#spawn=1]`, `[#spawn=2]`, `[#spawn=3]` fanno apparire i nemici esattamente alla visualizzazione dell'avvistamento. Le condizioni `wing_alive()` offrono alternative del pilota anche se si rimuove un gregario dalla scena.
- **Radio:** `scenes/ui/radio_dialogue.tscn`, sottotitoli automatici senza bloccare il volo o catturare input. Tempi di lettura regolabili nell'Inspector. Pausa ferma la radio; sconfitta e riavvio annullano la sequenza. La vittoria arriva dopo l'ultima battuta, non dopo l'ultimo colpo.
- **AI:** `EnemyFighter` resta condiviso tra nemici e gregari. **F7** mostra ruoli, bersagli, stati, permessi e regola degli attacchi al giocatore. **F6** mantiene il confronto dei filtri grafici. Terreno e freeroam non sono modificati.

```sh
godot --headless --path . --script tests/combat/tutorial_mission_check.gd --fixed-fps 60
godot --path . --script tests/combat/tutorial_mission_check.gd --fixed-fps 60 -- --capture
godot --headless --path . --script tests/combat/enemy_fighter_check.gd --fixed-fps 60
godot --headless --path . --script tests/combat/dogfight_simulation_check.gd --fixed-fps 60
```

Il controllo tutorial verifica i tre incontri, trasformazioni, sincronizzazione radio/radar, divieto di fuoco sul giocatore, combattimento contro i gregari, immunità dei compagni a danni/incendi/collisioni, pausa e sconfitta. La variante grafica usa la mappa reale e salva sei schermate in `user://tutorial_mission_check/`. I test del dogfight ordinario usano `tests/combat/dogfight_arena.tscn`, una scena fissa senza terreno né missione, con il giocatore a quota di combattimento. La simulazione tenta 60 secondi con 4, 6 e 1 nemici; il bilanciamento richiede comunque una prova giocata.

## Acqua e catture

La mappa usa `resources/materials/garda_water.tres`: increspature conservate ma ferme, senza schiuma, terreno invariato. FXAA sostituisce FSR2 come antialiasing globale per evitare il tremolio dell'acqua. [Confronti visivi, comandi e limiti](docs/environment/water-lookdev.md); `tools/review/water_capture.gd` offre nove viste A/B, viewer e passaggio diagnostico. `--still --view=low` verifica 32 fotogrammi consecutivi a camera ferma, senza salvare modifiche alla scena.

## Paesaggio Garda

Boschi runtime, albero Blender a tre LOD, erba locale e atmosfera rivista:
[confronti prima/dopo, esperimenti, prestazioni e limiti](docs/environment/landscape-lookdev.md).
Il nuovo paesaggio **non è certificato a 200 FPS costanti**; le misure storiche
precedono l'ampliamento dei boschi. Terrain3D e impostazioni personali non vengono
risalvati dai tool di confronto.

## Sfera energetica viola

Scena pronta all'uso: `scenes/vfx/energy_sphere.tscn`, sfera 3D solida da 500 m con nucleo scuro, energia animata, archi e alone. Anteprima F6: `tools/preview/vfx/energy_sphere_preview.tscn`. Parametri sull'Inspector del nodo radice; [uso, controlli e limiti](docs/features/energy-sphere.md). Nessuna mappa o missione modificata.

## Convenzioni

- Usare `snake_case` per nuovi file e cartelle del progetto; mantenere i nomi originali dei pacchetti esterni.
- Inserire scene, script e risorse nel rispettivo dominio esistente; anteprime in `tools/preview/`, controlli in `tests/<dominio>/`. Aggiungere cartelle solo per contenuti reali.
- Il codice runtime non deve importare da `tools/` o `tests/`: gli helper condivisi appartengono a `scripts/`. Il preset di export `performance` avvia esplicitamente il benchmark standalone.
- Conservare i percorsi delle scene registrate nei replay: livelli, attori e modelli sono parte del formato salvato. Un loro cambio richiede una migrazione dei replay.
- Conservare insieme alle risorse i file `.uid` e `.import`, anche in Git. Per gli spostamenti preferire il pannello FileSystem di Godot e verificare anche i percorsi scritti nelle stringhe.
- Non spostare `wc_data/` senza aggiornare World Creator Bridge: il plugin contiene percorsi fissi verso questa cartella.
- Non riordinare internamente `addons/`, `demo/`, `assets/BinbunVFX/` e `assets/thrusters/`: mantenere la struttura distribuita facilita gli aggiornamenti.
- `.godot/` e `.pi/` sono locali e già escluse da Git. Non confonderle con `wc_data/` o con i sorgenti del terreno.

## Verifica

Con Node e l'eseguibile Godot disponibile come `godot`, dalla radice:

```sh
node tests/performance/performance_runner_check.cjs
node tools/run_godot_check.cjs 25 /tmp/aero-bindings.log godot --headless --path . res://tests/input/controller_bindings_check.tscn
```

Il runner richiede un marker `PASS:`, exit code 0 e nessun errore/leak. Gli altri check possono avere marker specifici: leggere lo script e verificare comunque completamento, uscita e log. Non lanciare più verifiche grafiche insieme.

Il controllo storico `tests/ui/menu_flow_check.gd` copre opzioni, focus, cinque missili, due slot, entrambi i livelli reali, pausa, vittoria/sconfitta, riavvio e ritorno ai menu; usa un marker diverso da quello del runner. Senza `--headless` salva nove schermate in `user://menu_port_check/`; non sovrascrive le impostazioni personali né i dati del terreno.

Per la verifica grafica usare Forward+; i controlli headless non validano la resa di terreno, cielo ed effetti.

### Limiti già documentati

I risultati seguenti sono storici, non una certificazione automatica del checkout corrente.

- `enemy_fighter_check.gd`, il controllo tutorial e quello menu passano. `dogfight_simulation_check.gd` continua a fallire su `Wingmen must actually engage`, anche con la scena di test separata: il limite d'ingaggio già documentato non è risolto da questa modifica.
- Godot 4.7.1 segnala risorse audio ancora in uso alla chiusura; il giro grafico completo segnala anche RID di rendering non liberati. Il controllo tutorial segnala inoltre riferimenti alla risorsa dialogo trattenuti da Dialogue Manager 4.1. I controlli funzionali passano, ma questi warning di teardown rimangono.
