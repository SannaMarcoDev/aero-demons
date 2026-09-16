# Issue #2 — baseline controller

Stato: baseline completata con i limiti dichiarati sotto; decisioni confermate
esplicitamente dall'utente. Nessun cambiamento a input, scene o comportamento.

## Dispositivo e metodo

Xbox Series collegato via USB, dichiarato dall'utente. Prove fisiche eseguite
dall'utente, esiti confermati in chat; non simulati né dedotti dall'avvio MCP.
Godot 4.7.1, main scene `res://scenes/ui/main_menu.tscn`.

## Matrice delle prove

| Percorso e procedura | Esito riferito dall'utente |
|---|---|
| Menu: D-pad e stick sinistro, A su Storia, B indietro; selezione visibile | Funziona |
| Storia → Garda → aereo → Continua; STDM slot 1 e HSSTDM slot 2; B e rientro | Funziona, scelte mantenute |
| Avvio missione | Funziona, ma durante il caricamento sembra bloccato |
| Stick sinistro: beccheggio/rollio; LT e RT separati: imbardata | Funziona correttamente |
| RB accelerazione, LB freno; stick destro visuale | Funziona correttamente |
| Menu ☰ apre pausa, A su Riprendi | Funziona |
| Y breve cambia bersaglio, Y tenuto segue bersaglio; X cannone | Funziona |
| A lancia slot 1; D-pad su cambia slot; A lancia slot 2 | Funziona |
| Pausa → Opzioni: D-pad su/giù, sezioni grafiche/audio/controlli e scorrimento; B e Riprendi | Funziona; valori non modificati |
| Schianto → MISSIONE FALLITA → Menu ☰ → riavvio con A → nuova missione | Funziona; sconfitta per schianto confermata dall'utente |

Non verificati fisicamente: risultato di vittoria e relativo retry,
modifica e persistenza delle opzioni, opzioni dal menu principale, disconnessione,
riconnessione, secondo dispositivo, altri modelli/connessioni, manovre speciali.
Non è una certificazione completa di gameplay, bilanciamento o qualità visiva.

## Evidenze MCP

- `project_run(mode="main", autosave=false)`: helper `live`, nessun errore corrente.
- Run `r483154-1`: `live` anche all'ultima lettura dopo le prove.
- Log gioco: messaggi sulla modalità finestra embedded e warning
  `instance_reset_physics_interpolation() is deprecated`; nessun errore script riportato.
- Log editor prima dell'avvio: cinque errori di risorse stradali mancanti
  (`road_pbr_detail.gdshader` e texture Asphalt012 Color/NormalGL/Roughness),
  due warning UID delle texture F/A-26 con fallback al percorso.
- Letture editor successive con `since_cursor=7`: nessuna nuova voce.
  Gli errori trattenuti precedenti non hanno impedito i percorsi provati;
  non sono stati corretti né considerati regressioni di questa prova.
- `project_manage(op="stop")`: `stopped=true`, `was_running=true` dopo le prove.
- Nessun test headless: non è stata introdotta logica. Nessun salvataggio
  intenzionale di impostazioni, progressi o dati terreno durante l'ispezione.

## Primo intervento segnalato

[Issue #23 — Mostrare un caricamento visibile durante avvio stage e retry](https://github.com/SannaMarcoDev/aero-demons/issues/23),
creata su richiesta esplicita dell'utente. Riproduzione: avviare uno stage dal
loadout; durante l'attesa il gioco sembra bloccato. L'utente conferma che il resto
provato funziona. Durata non misurata; stessa percezione sul retry non confermata
separatamente. Nessun caricamento implementato in questo ticket.

## Ricognizione statica

- `project.godot`: azioni di gioco associate a qualsiasi device (`-1`), ma
  direzioni UI del controller associate al device `0`; dispositivo effettivo
  non interrogato. Nessuna conclusione sul secondo controller dalla prova attuale.
- `player_flight.gd::_update_controls`: letture tramite azioni InputMap;
  inversione Y e sensibilità applicate; Y cambia bersaglio al rilascio entro
  0,30 s. LT+RT attiva High-G; doppio tocco accelerazione attiva spin dash.
- `main_menu.gd`: focus esplicito nei sottomenu; B alla radice chiude il gioco
  (comportamento letto, non provato). Prompt testuali Xbox/tastiera fissi.
- `loadout.gd`: vicini di focus espliciti, scelta slot anche entrando in focus;
  label CARICAMENTO e due frame di attesa prima del cambio scena.
- `options_panel.gd`: focus iniziale sul volume master; save scrive solo se dirty.
- `combat_hud.gd`: risultato con prompt R per retry, ma retry raggiungibile da
  controller attraverso pausa. Prompt diretto controller da migliorare eventualmente.

- `GameSession.change_scene`: percorso condiviso da menu, loadout e HUD;
  rimuove la pausa, chiama `change_scene_to_file`, ripristina la pausa in caso
  d'errore e ferma l'allarme audio in caso di successo. Il retry HUD richiama
  la scena del genitore; non passa dal feedback CARICAMENTO del loadout.
  Questo è il punto comune da valutare per #23, non sei fix nei chiamanti.
- `EnemyFighter extends PlayerFlight`: l'IA sovrascrive il tick fisico e
  `_update_controls`; `_tick_ai` compila i campi di comando, poi usa
  `_apply_flight` e `_apply_triggers` ereditati. Limitazioni del giocatore
  non vanno applicate indiscriminatamente a queste funzioni condivise.
- Nel codice sotto `scripts/` la ricerca di `get_joy_axis`, `get_joy_button`
  e `joy_connection_changed` non trova letture dirette o gestione della
  disconnessione. La camera di volo usa azioni `look_*`; la camera free-fly
  di servizio usa letture dirette di tastiera e mouse, non è il percorso
  `Player/FlightCamera` verificato.
- `tutorial.tscn` istanzia Garda, Player e CombatHUD: i node path HUD puntano
  a `../Player`, `FlightCamera`, `TargetLock`, `WeaponController` e al figlio
  `MissionController`. Quest'ultimo usa `TutorialMission`, derivata da
  `sortie_controller.gd`: eredita la sconfitta collegata a `Player.destroyed`,
  ferma la radio prima del risultato e delega alla base l'overlay e la pausa.
  La vittoria arriva dopo l'outro radio, non al primo gruppo distrutto.
  Questi riferimenti sono coerenti con il percorso caricato e provato;
  nessuna validazione estesa a tutte le mappe o a tutti gli asset.

## Decisioni approvate dall'utente

Le seguenti raccomandazioni sono state sottoposte e approvate con «va bene»;
sono requisiti dei prossimi incrementi, non capacità già implementate:

1. Xbox Series USB come riferimento verificato; altri controller non certificati.
2. Rimappatura di pulsanti, trigger e assi di volo/visuale, inversione e deadzone configurabili.
3. Impedire assegnazioni duplicate nello stesso contesto, consentirle fra menu e volo.
4. Prompt dei comandi effettivi, con etichette Xbox quando si usa il controller.
5. Pausa alla disconnessione; conferma esplicita per riprendere dopo riconnessione.

Primo intervento circoscritto individuato: feedback caricamento #23. La sua
creazione è autorizzata, l'implementazione e l'ordine rispetto agli altri ticket
non sono avviati automaticamente. Non emergono malfunzionamenti controller nei
passaggi fisici confermati; il vincolo UI al device 0 resta un rischio statico,
non un guasto riprodotto sul controller provato.

## Verifiche e stato del checkout

`git diff --check` eseguito senza errori. Unico file aggiunto per #2:
`docs/issue-2-controller-baseline.md`; nessun nuovo test richiesto per un resoconto.
Preservati la modifica preesistente a `docs/demo-playable-plan.md` e il file
non tracciato `tests/utah_levels_check.gd.uid`. Nessun commit o push.
La chiusura di #2 certifica la ricognizione e la baseline descritta, non il
completamento dei requisiti futuri né le prove esplicitamente escluse.
