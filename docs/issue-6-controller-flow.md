# Issue #6 — navigazione e prompt controller

Stato: implementazione e verifiche automatiche completate; l'utente ha dato
l'OK («a posto») e richiesto commit e chiusura della issue. Nessun push richiesto.
L'approvazione non costituisce un resoconto dettagliato delle prove fisiche:
le evidenze dell'agente restano quelle automatiche e simulate riportate sotto.

## Modifiche

- I prompt di menu, loadout, armi, pausa e risultato leggono l'InputMap corrente.
  Nomi Xbox condivisi con la rimappatura; nei suggerimenti compatti si mostra
  la prima alternativa controller, nella schermata di rimappatura tutte.
  Il salvataggio aggiorna subito i prompt; una bozza annullata non li cambia.
- Opzioni: ciclo di focus esplicito tra pulsanti, slider e Indietro; scorrimento
  automatico e riga dello slider evidenziata in ciano. Caricare i valori non
  marca il pannello come modificato. Un errore di salvataggio in pausa lascia
  aperte le opzioni e mantiene la pausa.
- Ritorno dal loadout sul pulsante Volo libero di provenienza; ripristino del
  focus se manca o fallisce un caricamento. Indietro alla radice seleziona Esci:
  per chiudere il gioco serve Conferma.
- Risultato: Conferma (al rilascio) riprova; Indietro apre il menu. Chiudere il
  menu del risultato non toglie la pausa di fine missione. Le azioni UI hanno
  precedenza sulle azioni di volo che condividono il pulsante, anche quando
  Conferma e Pausa hanno lo stesso binding.
- Ripresa dal menu: attendere il rilascio dei comandi evita colpi o movimenti
  residui. I campi di input del giocatore e il tap bersaglio pendente vengono
  azzerati; la lettura dei controlli dell'IA non è stata modificata.
- Disconnessione di un controller: pausa e azzeramento delle azioni latched.
  Senza controller Riprendi è disabilitato; la riconnessione non riprende il
  gioco. Serve Conferma su Riprendi (Indietro non aggira questa protezione).
  Per prudenza la disconnessione di qualsiasi pad causa pausa; con un altro
  già connesso è comunque richiesta la conferma. Multiplayer/multi-pad non
  certificati.

## Verifiche automatiche

Godot 4.7.1. Comandi eseguiti con supervisione esterna: deadline wall-clock,
cleanup con `taskkill /PID <pid-del-test> /T /F` su timeout/errore, senza
terminare editor o processi estranei. Gli assert falliti durante lo sviluppo
sono stati corretti e i check interessati rieseguiti.

```text
godot --headless --path . --script tests/controller_ui_flow_check.gd
godot --headless --path . --script tests/controller_remap_check.gd
godot --headless --path . res://tests/controller_bindings_check.tscn
godot --headless --path . --script tests/menu_flow_check.gd
```

Tutti: marker esplicito di completamento, exit 0, nessun errore script/assert
nelle esecuzioni riuscite. `git diff --check` senza errori.

Il nuovo `controller_ui_flow_check.gd` usa eventi joypad nativi sintetici e le
scene reali. Percorre menu → opzioni → loadout → volo libero → pausa/rimappatura
→ risultato/retry → menu, sia con default sia con Conferma X, Indietro Y,
Cannone B, Bersaglio View, Cambio missile D-pad giù e Pausa X.
Verifica anche focus/scorrimento/evidenziazione, salvataggio fallito, prompt
aggiornati dal segnale reale di salvataggio, rilascio prima della ripresa,
conflitto fra contesti e disconnessione/riconnessione simulate via segnale.

Scritture su file temporaneo isolato, rimosso alla fine; il contenuto della
configurazione personale viene confrontato prima/dopo. Il profilo temporaneo
è reiniettato dopo i caricamenti delle scene, senza cambiare il percorso
production. Questo test non sostituisce una prova fisica né la verifica di
persistenza tra processi del backend di rimappatura.

Warning osservati: UID delle texture F/A-26 con fallback al percorso e API
`instance_reset_physics_interpolation` deprecata. Il vecchio test menu segnala
5 ObjectDB e 3 risorse residue in uscita (già osservati nell'incremento #4);
il nuovo test di flusso e quello di rimappatura terminano senza tali residui.

## Prove Godot AI MCP

`autosave=false`, scene UI aperte nell'editor, run di menu principale e livelli
Garda. Run `r14912400-14`: menu → loadout → tutorial → pausa/opzioni con eventi
controller simulati. Run `r15265290-15`: menu → opzioni → loadout → volo libero
→ pausa; ispezionati screenshot, prompt, focus e slider in ciano. Confermati
`live`; log correnti senza nuovi errori script/load. Warning di deprecazione
separato dagli errori stradali/UID trattenuti precedenti alla sessione corrente
(cursor editor 7, nessuna nuova voce nelle letture incrementali).

Run finale `r15907370-16`, freeroam: inizialmente `not_live` durante il
caricamento, poi `live` confermato senza rilanciare. Verificati layout dei
prompt ingranditi e ripresa: X tenuto + Conferma lascia la pausa con il testo
«RILASCIA I COMANDI PER RIPRENDERE»; rilasciare X chiude la pausa. Nessun errore
nei log correnti di gioco/editor. Esecuzioni di prova fermate.

Queste prove verificano l'interazione simulata e il layout osservato, non il
funzionamento USB fisico, la leggibilità su altri schermi o il gameplay completo.

## Checklist di riferimento per la prova fisica

Riferimento: Xbox Series USB, verificato dall'utente nella baseline #2.
Per #6 è arrivato l'OK dell'utente, senza dettaglio dei singoli passi fisici;
l'agente non li ha verificati direttamente. Altri modelli/connessioni non certificati.

1. Con i default, percorri menu → loadout → volo → pausa → opzioni e ritorno.
   Controlla focus di pulsanti e slider, scorrimento, Indietro e Conferma.
2. Da Opzioni rimappa e salva un comando armi e Conferma/Indietro. Ripeti il
   percorso e controlla che nomi mostrati e comandi effettivi coincidano.
3. In pausa tieni un comando di volo/armi mentre chiedi Riprendi: il gioco deve
   aspettare il rilascio. Nessun colpo deve partire sotto la UI o al rilascio.
4. Scollega il pad durante il volo (anche tenendo un pulsante), poi ricollegalo:
   il gioco deve restare in pausa finché confermi Riprendi.
5. Ripeti la disconnessione nelle opzioni/rimappatura: nessuna ripresa automatica
   né perdita della bozza; devi poter tornare al menu e riprendere esplicitamente.
6. Prova risultato di sconfitta e vittoria: Conferma riprova; Indietro apre il
   menu, che deve consentire ritorno al loadout/menu senza SceneTree bloccato.
7. Ripristina e salva i binding desiderati. Riporta esiti, dispositivo e qualunque
   passo non provato; non considerare automaticamente verificati quelli mancanti.

Le modifiche preesistenti a `docs/demo-playable-plan.md` e
`tests/utah_levels_check.gd.uid`, i dati terreno e i salvataggi personali non
fanno parte di questa implementazione.
