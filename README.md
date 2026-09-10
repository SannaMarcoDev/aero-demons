# Aero Demons

Progetto Godot **4.7**, renderer **Forward+**, fisica **Jolt**.
Aprire `project.godot` e avviare con **F5** il [menu principale](scenes/ui/main_menu.tscn), oppure con **F6** la scena desiderata.
Dal menu si scelgono dogfight sul Garda o volo libero, poi due tipi di missile prima del decollo. Entrambi i livelli usano `scenes/maps/garda_final.tscn`.

## Mappa del progetto

| Percorso | Contenuto |
| --- | --- |
| `scenes/maps/` | `garda_final.tscn` è l'unica mappa effettiva, condivisa da freeroam e tutorial, con terreno, cielo, nuvole e controllo dei confini. |
| `scenes/player/`, `scenes/enemies/` | Scene degli aerei e del giocatore. |
| `scenes/ui/`, `scenes/weapons/`, `scenes/vfx/` | HUD, proiettili, missili ed effetti. |
| `scripts/` | Logica divisa per dominio: `audio`, `camera`, `combat`, `player`, `ui`, `vfx`, `weapons`. |
| `resources/materials/` | Materiali condivisi. |
| `resources/shaders/` | Shader del progetto, inclusi quelli VFX. |
| `resources/environments/` | Configurazioni ambientali, come le nuvole della mappa tutorial. |
| `assets/` | Modelli, aerei, audio, font e pacchetti VFX. |
| `terrain/textures/` | Texture del terreno. |
| `terrain/source/` | Heightmap master GeoTIFF, RAW per World Machine, anteprima e informazioni di origine/licenza. |
| `wc_data/` | Dati Terrain3D e texture prodotti da World Creator Bridge. Sono dati del progetto, non cache. |
| `addons/` | Plugin e dipendenze integrate. |
| `demo/` | Scene dimostrative delle dipendenze, separate dal gioco. |
| `tests/` | Controlli eseguibili, separati dagli script di gioco. |

In radice rimangono la configurazione Godot/Git, questa guida, l'icona e `default_bus_layout.tres` (layout audio predefinito).

## Punti di ingresso utili

- Menu e armamento: `scenes/ui/main_menu.tscn`, `loadout.tscn`; selezione cross-scena in `scripts/ui/game_session.gd`.
- Giocatore: `scenes/player/player.tscn` → `scripts/player/player_flight.gd`.
- Armi: `scripts/weapons/weapon_controller.gd` e `missile_catalog.gd`.
- Camera: `scripts/camera/follow_camera.gd` e `free_fly_camera.gd`.
- Audio globale: `scripts/audio/audio_manager.gd`, registrato come autoload in `project.godot`.
- Terreno attivo: `terrain/garda_final_wc_uniform_250km/` (250 × 250 km); origine e parametri in `import_manifest.json` nella stessa cartella. Gli export World Creator restano la fonte di verità.

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
godot --headless --path . --script tests/tutorial_mission_check.gd --fixed-fps 60
godot --path . --script tests/tutorial_mission_check.gd --fixed-fps 60 -- --capture
godot --headless --path . --script tests/enemy_fighter_check.gd --fixed-fps 60
godot --headless --path . --script tests/dogfight_simulation_check.gd --fixed-fps 60
```

Il controllo tutorial verifica i tre incontri, trasformazioni, sincronizzazione radio/radar, divieto di fuoco sul giocatore, combattimento contro i gregari, immunità dei compagni a danni/incendi/collisioni, pausa e sconfitta. La variante grafica usa la mappa reale e salva sei schermate in `user://tutorial_mission_check/`. I test del dogfight ordinario usano `tests/dogfight_arena.tscn`, una scena fissa senza terreno né missione, con il giocatore a quota di combattimento. La simulazione tenta 60 secondi con 4, 6 e 1 nemici; il bilanciamento richiede comunque una prova giocata.

## Acqua e catture

La mappa usa `resources/materials/garda_water.tres`: increspature conservate ma ferme, senza schiuma, terreno invariato. FXAA sostituisce FSR2 come antialiasing globale per evitare il tremolio dell'acqua. [Confronti visivi, comandi e limiti](docs/water-lookdev.md); `tools/water_capture.gd` offre nove viste A/B, viewer e passaggio diagnostico. `--still --view=low` verifica 32 fotogrammi consecutivi a camera ferma, senza salvare modifiche alla scena.

## Convenzioni

- Usare `snake_case` per nuovi file e cartelle del progetto; mantenere i nomi originali dei pacchetti esterni.
- Inserire scene e script nel rispettivo dominio esistente; aggiungere cartelle solo per contenuti reali.
- Conservare insieme alle risorse i file `.uid` e `.import`, anche in Git. Per gli spostamenti preferire il pannello FileSystem di Godot e verificare anche i percorsi scritti nelle stringhe.
- Non spostare `wc_data/` senza aggiornare World Creator Bridge: il plugin contiene percorsi fissi verso questa cartella.
- Non riordinare internamente `addons/`, `demo/`, `assets/BinbunVFX/` e `assets/thrusters/`: mantenere la struttura distribuita facilita gli aggiornamenti.
- `.godot/` e `.pi/` sono locali e già escluse da Git. Non confonderle con `wc_data/` o con i sorgenti del terreno.

## Verifica

Con l'eseguibile Godot disponibile come `godot`, dalla radice:

```sh
godot --headless --path . --script tests/afterburner_check.gd
godot --headless --path . --script tests/menu_flow_check.gd
```

Il controllo menu copre opzioni, focus, cinque missili, due slot, entrambi i livelli reali, pausa, vittoria/sconfitta, riavvio e ritorno ai menu. Senza `--headless` salva nove schermate in `user://menu_port_check/`; non sovrascrive le impostazioni personali né i dati del terreno.

Per la verifica grafica usare Forward+; i controlli headless non validano la resa di terreno, cielo e nuvole.

### Limiti della verifica

- `enemy_fighter_check.gd`, il controllo tutorial e quello menu passano. `dogfight_simulation_check.gd` continua a fallire su `Wingmen must actually engage`, anche con la scena di test separata: il limite d'ingaggio già documentato non è risolto da questa modifica.
- Godot 4.7.1 segnala risorse audio ancora in uso alla chiusura; il giro grafico completo segnala anche RID di rendering non liberati. Il controllo tutorial segnala inoltre riferimenti alla risorsa dialogo trattenuti da Dialogue Manager 4.1. I controlli funzionali passano, ma questi warning di teardown rimangono.
