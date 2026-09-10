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

- **Operazioni → Garda → Armamento → Avvia sortita**; **Free Flight → Armamento → Decolla** per il volo senza nemici.
- Due slot indipendenti: **STDM** standard, **HSSTDM** veloce, **BAHM** pesante, **NCGBM** incendiario (75 danni in 10 secondi oltre all'impatto), **MTSM** multi-bersaglio. Le statistiche provengono dal catalogo effettivamente usato dalle armi.
- Menu: mouse, frecce/WASD, D-Pad o stick sinistro; Invio/A conferma, Esc/B torna indietro. In volo **Q / D-Pad su** cambia slot, **TAB / Y** cambia bersaglio, **Spazio / A** lancia.
- **Esc / Start** apre la pausa: riprendi, riprova, cambia armamento, menu principale o esci. **R** riavvia la sortita mantenendo il loadout.
- Opzioni: volume Master/Music/SFX, fullscreen e V-Sync. **Indietro / Esc** salva in `user://settings.cfg`; la selezione dei missili dura per la sessione corrente.

## Prototipo dogfight

Dal menu scegliere Operazioni → Garda, oppure avviare `scenes/levels/tutorial.tscn`: giocatore, due gregari e quattro nemici. La sortita termina quando tutti i nemici sono distrutti o il giocatore viene abbattuto; pausa e riavvio rimangono disponibili.
In gioco **F7** mostra ruoli, bersagli, stati, motivi di mancato fuoco e budget del direttore; i gregari hanno indicatori azzurri. In `scenes/levels/tutorial.tscn` e `scenes/levels/freeroam.tscn`, **F6** mantiene il confronto dei filtri grafici.

- `CombatDirector`: durata degli incarichi, pressione/respiro, limite di attaccanti e missili sul giocatore.
- `EnemyFighter` (condiviso con i gregari): tempi tattici, pilotaggio, evasione, tiro e sicurezza, regolabili nell'Inspector.
- Per provare sei nemici, duplicare due istanze nemiche nella scena: il direttore le rileva senza aumentare il budget sul giocatore.

```sh
godot --headless --path . --script tests/enemy_fighter_check.gd --fixed-fps 60
godot --headless --path . --script tests/dogfight_simulation_check.gd --fixed-fps 60
```

Il secondo controllo simula 60 secondi con quattro nemici, sei nemici e un duello finale senza gregari. Il giocatore di test vola diritto e può essere abbattuto: verifica il funzionamento, non il bilanciamento. Aggressività, efficacia dei gregari e finestre di contrattacco richiedono ancora una prova giocata.

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

- I test dogfight precedenti eliminano la mappa ma lasciano `HorizonGraphics`, che segnala `Sky3D` mancante. `dogfight_simulation_check.gd` fallisce inoltre sull'ingaggio dei gregari; riprodotto anche ripristinando in memoria gli script di volo/audio precedenti al port.
- Godot 4.7.1 segnala risorse audio ancora in uso alla chiusura; il giro grafico completo segnala anche RID di rendering non liberati. Il controllo funzionale del menu passa, ma questi warning di teardown rimangono.
