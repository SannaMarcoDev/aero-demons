# M1: volo guidato, spiegazioni armi e ondate 2/4/8

## Flusso attuale

Radio → movimento guidato → avvistamento → velocità/avvicinamento → tre box (targeting, missili, mitragliatrice) → combattimento 2/4/8 → radio di rientro → vittoria.

- Il volo iniziale conserva la protezione e i controlli di pratica dei tre assi e dell'accelerazione.
- Al raggiungimento del punto di contatto terminano la protezione del giocatore e il blocco delle armi. I primi due nemici sono normali combattenti vulnerabili, non bersagli di esercitazione.
- I tre box sono soltanto informativi: avanzano con Conferma, senza richiedere selezioni, agganci, lanci o colpi. Il SceneTree resta in pausa anche nel passaggio tra i box, quindi nessuno viene attaccato mentre legge.
- Le spiegazioni usano i binding correnti e descrivono entrambi gli slot missili, anche identici. Restano supportati i cinque tipi esistenti.
- Chiusa l'ultima spiegazione, il giocatore combatte liberamente. Nessuna verifica didattica delle armi, nessun rifornimento automatico e nessun altro popup tutorial. La radio «Due caccia davanti a noi. Ti copriamo.» non blocca il combattimento.
- Seguono le ondate da 4 e 8 nei marker originali. I gregari mantengono la loro invulnerabilità preesistente.
- Vittoria dopo l'ultima radio, sconfitta alla morte; retry ricarica la scena. Pausa, opzioni, rimappatura e disconnessione restano gestite dalla UI esistente.

## Verifica della semplificazione

Passati con marker esplicito, codice 0 e senza errori script/assertion:

- `tutorial_mission_check.gd`: percorso iniziale, tre sole conferme senza azioni sulle armi con tutti i 25 loadout, pausa continua tra i box, vulnerabilità al contatto, nessun rifornimento automatico, ondate 2/4/8, vittoria/sconfitta e reset.
- `menu_flow_check.gd`: menu, armi, risultati e retry.
- `enemy_fighter_check.gd`: comportamento normale dell'IA e armi.
- `controller_ui_flow_check.gd`: binding standard/personalizzati, pausa e disconnessione.

Godot AI MCP: scena aperta e avviata con `autosave=false`, stato `live`, log del run pulito e nessun nuovo errore editor dal cursore 7; run arrestato. Questa revisione è verificata comportamentalmente dai test headless, non da una nuova partita manuale completa.

Restano gli avvisi preesistenti sugli UID asset, sull'interpolazione deprecata e sulle risorse/ObjectDB alla chiusura headless. Il precedente fallimento di `gun_handling_check.gd` (riga 87, assunzione incompatibile con `control_rise_time = 0.05`) non è stato modificato né rieseguito in questa revisione.
