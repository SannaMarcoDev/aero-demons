# Aero Demons

Progetto Godot **4.7**, renderer **Forward+**, fisica **Jolt**.
Aprire `project.godot` e avviare con **F6** la scena desiderata o **F5** la scena principale: [`scenes/levels/freeroam.tscn`](scenes/levels/freeroam.tscn).
Il gioco principale è il livello freeroam: carica `scenes/maps/garda_final.tscn` e vi istanzia il giocatore.

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

- Giocatore: `scenes/player/player.tscn` → `scripts/player/player_flight.gd`.
- Armi: `scripts/weapons/weapon_controller.gd` e `missile_catalog.gd`.
- Camera: `scripts/camera/follow_camera.gd` e `free_fly_camera.gd`.
- Audio globale: `scripts/audio/audio_manager.gd`, registrato come autoload in `project.godot`.
- Terreno attivo: `terrain/garda_final_wc_uniform_250km/` (250 × 250 km); origine e parametri in `import_manifest.json` nella stessa cartella. Gli export World Creator restano la fonte di verità.

## Prototipo dogfight

Aprire `scenes/levels/tutorial.tscn` e avviare la scena: giocatore, due gregari e quattro nemici, senza obiettivi di missione.
In gioco **F7** mostra ruoli, bersagli, stati, motivi di mancato fuoco e budget del direttore; i gregari hanno indicatori azzurri. In `scenes/levels/tutorial.tscn` e `scenes/levels/freeroam.tscn`, **F6** mantiene il confronto dei filtri grafici.

- `CombatDirector`: durata degli incarichi, pressione/respiro, limite di attaccanti e missili sul giocatore.
- `EnemyFighter` (condiviso con i gregari): tempi tattici, pilotaggio, evasione, tiro e sicurezza, regolabili nell'Inspector.
- Per provare sei nemici, duplicare due istanze nemiche nella scena: il direttore le rileva senza aumentare il budget sul giocatore.

```sh
godot --headless --path . --script tests/enemy_fighter_check.gd --fixed-fps 60
godot --headless --path . --script tests/dogfight_simulation_check.gd --fixed-fps 60
```

Il secondo controllo simula 60 secondi con quattro nemici, sei nemici e un duello finale senza gregari. Il giocatore di test vola diritto e può essere abbattuto: verifica il funzionamento, non il bilanciamento. Aggressività, efficacia dei gregari e finestre di contrattacco richiedono ancora una prova giocata.

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
```

Per la verifica grafica aprire la mappa tutorial nell'editor con Forward+; i controlli headless non validano la resa di terreno, cielo e nuvole.

### Problemi preesistenti rilevati

- `scripts/ui/game_session.gd` contiene ancora il percorso `res://scenes/maps/italian_alps_world.tscn`, ma quella scena non è presente nel repository. Non è la scena principale.
- L'editor segnala `Explosion` non dichiarato in `scripts/player/player_flight.gd:536` e `scripts/weapons/missile.gd:341`; lo script VFX presente dichiara invece `ExplosionFX`.

Il riordino non modifica questa logica. Il test afterburner passa, ma non copre questi errori né costituisce una verifica completa del gioco.
