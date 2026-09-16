# Issue #5 — perimetro della build interna

## Modifiche

- `aircraft_catalog.gd`: un solo ID selezionabile (`fa_n26`, F/A-26 Camo 4); applicazione al player vincolata al modello predefinito. Le altre definizioni e gli asset restano disponibili internamente, senza modificare i modelli dell'IA.
- `game_session.gd`: assegnazioni di ID precedenti o non validi vengono normalizzate al predefinito. Il loadout mostra un solo aereo e mantiene il flusso a due passi.
- `player_flight.gd`: il lettore input del giocatore non abilita High-G o spin dash; anche l'avvio diretto dello spin dash è bloccato per la fazione player. Dinamica condivisa e codice dell'IA invariati.
- Rimossi dal menu gli inviti a usare le manovre speciali. Catalogo missili, binding e salvataggi non modificati.

## Verifiche eseguite

Godot 4.7.1, per ciascuno script:

```text
Godot_v4.7.1-stable_win64.exe --headless --path . --script tests/aircraft_selection_check.gd
Godot_v4.7.1-stable_win64.exe --headless --path . --script tests/flight_inertia_check.gd
Godot_v4.7.1-stable_win64.exe --headless --path . --script tests/enemy_fighter_check.gd
Godot_v4.7.1-stable_win64.exe --headless --path . --script tests/menu_flow_check.gd
```

Eseguiti tramite processo PowerShell con deadline di 210 secondi per test e `taskkill /PID <pid-generato> /T /F` nel cleanup in caso di timeout. Tutti i run finali hanno prodotto il proprio marker di completamento, exit code 0 e nessun errore script/assert.

Copertura: ID obsoleti, preview, modello e scarichi, tutte le 25 coppie dei cinque missili nei due slot, trasferimento al controller armi, cambio slot, input High-G e doppio tap accelerazione, tentativo diretto di spin dash, isolamento modello/armi/manovra IA. Il test menu verifica inoltre lanci effettivi dei cinque missili, avvio tutorial Garda con NCGBM/MTSM, retry e avvio volo libero con selezione aereo obsoleta.

Il primo run del test esteso aveva un'aspettativa errata sul loadout IA (due missili invece del solo STDM della scena): corretto il test, processo terminato alla deadline, poi rieseguito con successo.

`git diff --check`: superato.

## Verifica editor e limiti

- Godot AI MCP, `autosave=false`: loadout avviato `live`, confermati un solo pulsante aereo e i cinque missili; passaggio al volo libero Garda tramite UI.
- Nel volo libero inviati input simultanei yaw sinistro/destro e doppio tap accelerazione tramite sequenza a frame; input poi rilasciati. Gli assert sullo stato delle manovre sono nel test headless, non nell'ispezione MCP delle proprietà esportate.
- Tutorial Utah aperto e avviato `live`; i timeout iniziali dei tool sono stati verificati con il successivo stato editor, senza rilanciare il gioco.
- Log di gioco correnti e log editor dal cursore di avvio: nessun errore script/load corrente. Avviso di API deprecata `instance_reset_physics_interpolation()` nel volo libero Garda e messaggio sulla modalità finestra embedded. Entrambi i run fermati.
- Nei test headless rimangono warning UID delle texture F/A-26; alcuni test segnalano anche ObjectDB leak e `resources still in use at exit`. Queste diagnostiche non sono risolte né certificate come preesistenti da questo intervento; non sono errori script/assert.
- Nessuna prova con controller fisico, valutazione della qualità visiva o collaudo completo della giocabilità. Nessuna modifica al terreno, nessun commit/push e nessuna chiusura automatica della issue.
